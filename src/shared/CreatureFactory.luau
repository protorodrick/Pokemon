-- Creates, scales and levels creature instances. Instances are plain tables so they serialise
-- straight into DataStores.
local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Config)
local Creatures = require(script.Parent.Creatures)
local Moves = require(script.Parent.Moves)

local Factory = {}

local STAT_KEYS = { "hp", "atk", "def", "spa", "spd", "spe" }
Factory.STAT_KEYS = STAT_KEYS

function Factory.stats(mon)
	local species = Creatures.get(mon.species)
	local out = {}
	for _, k in STAT_KEYS do
		local base = species.base[k]
		local iv = mon.ivs and mon.ivs[k] or 15
		local core = math.floor(((2 * base + iv) * mon.level) / 100)
		if k == "hp" then
			out[k] = core + mon.level + 10
		else
			out[k] = core + 5
		end
	end
	return out
end

function Factory.maxHp(mon): number
	return Factory.stats(mon).hp
end

-- Total XP needed to *reach* a level (medium-fast curve).
function Factory.xpForLevel(level: number): number
	return level ^ 3
end

local function movesForLevel(speciesId: string, level: number)
	local species = Creatures.get(speciesId)
	local learned = {}
	for _, entry in species.learnset do
		if entry[1] <= level then
			table.insert(learned, entry[2])
		end
	end
	local out = {}
	for i = math.max(1, #learned - 3), #learned do
		local id = learned[i]
		table.insert(out, { id = id, pp = Moves[id].pp })
	end
	return out
end

function Factory.new(speciesId: string, level: number, rng: Random?)
	rng = rng or Random.new()
	local ivs = {}
	for _, k in STAT_KEYS do
		ivs[k] = rng:NextInteger(0, 31)
	end
	local mon = {
		uid = HttpService:GenerateGUID(false),
		species = speciesId,
		level = level,
		xp = Factory.xpForLevel(level),
		ivs = ivs,
		moves = movesForLevel(speciesId, level),
		shiny = rng:NextInteger(1, Config.ShinyOdds) == 1,
		friendship = 70,
	}
	mon.hp = Factory.maxHp(mon)
	return mon
end

function Factory.heal(mon)
	mon.hp = Factory.maxHp(mon)
	mon.status = nil
	for _, m in mon.moves do
		m.pp = Moves[m.id].pp
	end
end

function Factory.copy(mon)
	local c = table.clone(mon)
	c.ivs = table.clone(mon.ivs)
	c.moves = {}
	for i, m in mon.moves do
		c.moves[i] = table.clone(m)
	end
	return c
end

-- Applies XP, handles level-ups, move learning and evolution. Appends events to `events`.
function Factory.giveXp(mon, amount: number, events: { any })
	mon.xp += amount
	table.insert(events, { t = "xp", name = Factory.displayName(mon), amount = amount })
	while mon.level < 100 and mon.xp >= Factory.xpForLevel(mon.level + 1) do
		local oldMax = Factory.maxHp(mon)
		mon.level += 1
		mon.hp = math.min(Factory.maxHp(mon), mon.hp + (Factory.maxHp(mon) - oldMax))
		table.insert(events, { t = "levelup", name = Factory.displayName(mon), level = mon.level })

		local species = Creatures.get(mon.species)
		for _, entry in species.learnset do
			if entry[1] == mon.level then
				local moveId = entry[2]
				local known = false
				for _, m in mon.moves do
					if m.id == moveId then
						known = true
					end
				end
				if not known then
					if #mon.moves >= 4 then
						table.remove(mon.moves, 1) -- forget oldest move
					end
					table.insert(mon.moves, { id = moveId, pp = Moves[moveId].pp })
					table.insert(events, { t = "learn", name = Factory.displayName(mon), move = Moves[moveId].name })
				end
			end
		end

		if species.evolvesTo and species.evolveLevel and mon.level >= species.evolveLevel then
			local before = Factory.displayName(mon)
			local ratio = mon.hp / Factory.maxHp(mon)
			mon.species = species.evolvesTo
			mon.hp = math.max(1, math.floor(Factory.maxHp(mon) * ratio))
			table.insert(events, { t = "evolve", from = before, to = Creatures.get(mon.species).name })
		end
	end
end

function Factory.displayName(mon): string
	if mon.nickname and mon.nickname ~= "" then
		return mon.nickname
	end
	local s = Creatures.get(mon.species)
	return s and s.name or mon.species
end

-- Compact public view sent to clients.
function Factory.summary(mon)
	local species = Creatures.get(mon.species)
	local moves = {}
	for _, m in mon.moves do
		local def = Moves[m.id]
		table.insert(
			moves,
			{ id = m.id, name = def.name, type = def.type, pp = m.pp, maxPp = def.pp, power = def.power, category = def.category }
		)
	end
	return {
		uid = mon.uid,
		species = mon.species,
		name = Factory.displayName(mon),
		level = mon.level,
		hp = mon.hp,
		maxHp = Factory.maxHp(mon),
		types = species.types,
		shiny = mon.shiny,
		xp = mon.xp,
		xpNext = Factory.xpForLevel(mon.level + 1),
		xpCur = Factory.xpForLevel(mon.level),
		moves = moves,
	}
end

return Factory
