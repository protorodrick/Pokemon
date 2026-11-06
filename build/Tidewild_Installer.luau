-- Tidewild one-paste installer. Paste ALL of this into Roblox Studio's Command Bar
-- (View > Command Bar) and press Enter. Re-running replaces the previous install.
local function make(cls, name, parent)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == cls and (cls == 'Folder' or cls == 'StarterPlayerScripts') then return existing end
	if existing then existing:Destroy() end
	local i = Instance.new(cls)
	i.Name = name
	i.Parent = parent
	return i
end
pcall(function() workspace.StreamingEnabled = true end)
local L = game:GetService('Lighting')
L.ClockTime = 14; L.Brightness = 2.5; L.GlobalShadows = true
pcall(function() L.Technology = Enum.Technology.Future end)
local base = workspace:FindFirstChild('Baseplate'); if base then base:Destroy() end
local n1 = make("Folder", "Shared", game:GetService('ReplicatedStorage'))
local n2 = make("ModuleScript", "BattleEngine", n1)
n2.Source = [=[
-- Pure, server-authoritative turn resolver. No Roblox instances are touched here, so it can be
-- unit-tested and reused for wild battles and player-vs-player plaza battles.
local Config = require(script.Parent.Config)
local Creatures = require(script.Parent.Creatures)
local Moves = require(script.Parent.Moves)
local Types = require(script.Parent.Types)
local Factory = require(script.Parent.CreatureFactory)

local Battle = {}
Battle.__index = Battle

local function firstAlive(party)
	for i, mon in party do
		if mon.hp > 0 then
			return i
		end
	end
	return nil
end

local function freshStages()
	return { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
end

--[[
	side = {
		name = string,
		party = { mon },     -- references to live data (wild) or copies (PvP)
		isWild = boolean?,
		isAI = boolean?,
		orbs = number?,       -- only used to report; server deducts
	}
]]
function Battle.new(kind: string, sideA, sideB)
	local self = setmetatable({
		kind = kind, -- "wild" | "pvp"
		sides = { sideA, sideB },
		stages = { freshStages(), freshStages() },
		participants = { {}, {} }, -- uids that fought (for XP share)
		turn = 0,
		ended = false,
		winner = nil,
		caught = nil,
		fled = false,
		rng = Random.new(),
	}, Battle)
	for i, side in self.sides do
		side.active = firstAlive(side.party)
		if side.active then
			self.participants[i][side.party[side.active].uid] = true
		end
	end
	return self
end

function Battle:active(i)
	local side = self.sides[i]
	return side.active and side.party[side.active] or nil
end

local function stageMult(stage)
	if stage >= 0 then
		return (2 + stage) / 2
	end
	return 2 / (2 - stage)
end

function Battle:stat(i, key)
	local mon = self:active(i)
	return Factory.stats(mon)[key] * stageMult(self.stages[i][key] or 0)
end

function Battle:chooseAIMove(i)
	local mon = self:active(i)
	local usable = {}
	for idx, m in mon.moves do
		if m.pp > 0 then
			table.insert(usable, idx)
		end
	end
	if #usable == 0 then
		return { type = "move", index = 0 }
	end
	-- Light heuristic: prefer super-effective damaging moves.
	local foe = self:active(3 - i)
	local foeTypes = Creatures.get(foe.species).types
	local best, bestScore = usable[1], -1
	for _, idx in usable do
		local def = Moves[mon.moves[idx].id]
		local score = def.power * Types.effectiveness(def.type, foeTypes) + self.rng:NextNumber(0, 30)
		if def.category == "Status" then
			score = 25 + self.rng:NextNumber(0, 30)
		end
		if score > bestScore then
			best, bestScore = idx, score
		end
	end
	return { type = "move", index = best }
end

local function actionPriority(action)
	if action.type == "run" then
		return 7
	elseif action.type == "switch" or action.type == "catch" or action.type == "item" then
		return 6
	end
	return 0
end

function Battle:_doMove(i, action, events)
	local user = self:active(i)
	local foeIdx = 3 - i
	local foe = self:active(foeIdx)
	if not user or not foe or user.hp <= 0 then
		return
	end

	local moveId
	local slot = user.moves[action.index or 0]
	if slot and slot.pp > 0 then
		moveId = slot.id
		slot.pp -= 1
	else
		moveId = "Struggle"
	end
	local move = Moves[moveId]
	local userName = Factory.displayName(user)
	local ev = { t = "move", side = i, user = userName, move = move.name, moveType = move.type }
	table.insert(events, ev)

	if self.rng:NextNumber(0, 100) > move.accuracy then
		ev.miss = true
		return
	end

	if move.category ~= "Status" then
		local atkKey = move.category == "Physical" and "atk" or "spa"
		local defKey = move.category == "Physical" and "def" or "spd"
		local A = self:stat(i, atkKey)
		local D = self:stat(foeIdx, defKey)
		local userTypes = Creatures.get(user.species).types
		local foeTypes = Creatures.get(foe.species).types
		local eff = Types.effectiveness(move.type, foeTypes)
		local stab = table.find(userTypes, move.type) and 1.5 or 1
		local crit = self.rng:NextInteger(1, 16) == 1
		local base = ((2 * user.level / 5 + 2) * move.power * A / D) / 50 + 2
		local dmg = base * stab * eff * self.rng:NextNumber(0.85, 1) * (crit and 1.5 or 1)
		dmg = eff == 0 and 0 or math.max(1, math.floor(dmg))
		dmg = math.min(dmg, foe.hp)
		foe.hp -= dmg
		ev.damage, ev.eff, ev.crit = dmg, eff, crit
		ev.targetHp, ev.targetMax = foe.hp, Factory.maxHp(foe)

		if move.recoil then
			local r = math.max(1, math.floor(Factory.maxHp(user) * move.recoil))
			user.hp = math.max(0, user.hp - r)
			table.insert(events, { t = "recoil", side = i, name = userName, damage = r, hp = user.hp })
		end
		if move.effect and move.effect.kind == "drain" and dmg > 0 then
			local heal = math.max(1, math.floor(dmg * move.effect.fraction))
			user.hp = math.min(Factory.maxHp(user), user.hp + heal)
			table.insert(events, { t = "heal", side = i, name = userName, amount = heal, hp = user.hp })
		end
	end

	local effect = move.effect
	if effect and effect.kind == "stat" then
		local target = effect.target == "self" and i or foeIdx
		local stages = self.stages[target]
		local before = stages[effect.stat]
		stages[effect.stat] = math.clamp(before + effect.stages, -6, 6)
		table.insert(events, {
			t = "stat",
			side = target,
			name = Factory.displayName(self:active(target)),
			stat = effect.stat,
			delta = stages[effect.stat] - before,
		})
	elseif effect and effect.kind == "heal" then
		local heal = math.floor(Factory.maxHp(user) * effect.fraction)
		user.hp = math.min(Factory.maxHp(user), user.hp + heal)
		table.insert(events, { t = "heal", side = i, name = userName, amount = heal, hp = user.hp })
	end
end

function Battle:_doCatch(i, action, events)
	local target = self:active(3 - i)
	local species = Creatures.get(target.species)
	local maxHp = Factory.maxHp(target)
	local bonus = action.bonus or 1
	local a = ((3 * maxHp - 2 * target.hp) * species.catchRate * bonus) / (3 * maxHp)
	local chance = math.clamp(a / 255, 0.02, 1)
	local shakes = 0
	local perShake = chance ^ 0.25
	for _ = 1, 4 do
		if self.rng:NextNumber() <= perShake then
			shakes += 1
		else
			break
		end
	end
	local success = shakes == 4
	table.insert(events, { t = "catch", success = success, shakes = math.min(shakes, 3), name = species.name })
	if success then
		self.ended = true
		self.winner = i
		self.caught = target
	end
end

function Battle:_doRun(i, events)
	local mine, theirs = self:stat(i, "spe"), self:stat(3 - i, "spe")
	local chance = math.clamp(0.5 + (mine - theirs) / 100, 0.35, 1)
	local ok = self.rng:NextNumber() <= chance
	table.insert(events, { t = "run", success = ok })
	if ok then
		self.ended = true
		self.fled = true
	end
end

function Battle:_doSwitch(i, action, events)
	local side = self.sides[i]
	local mon = side.party[action.slot]
	if not mon or mon.hp <= 0 or action.slot == side.active then
		return
	end
	side.active = action.slot
	self.stages[i] = freshStages()
	self.participants[i][mon.uid] = true
	table.insert(events, { t = "switch", side = i, name = Factory.displayName(mon), species = mon.species, slot = action.slot })
end

function Battle:_doItem(i, action, events)
	if action.item == "Potion" then
		local mon = self.sides[i].party[action.slot or self.sides[i].active]
		if mon and mon.hp > 0 then
			local heal = math.min(30 + math.floor(Factory.maxHp(mon) * 0.25), Factory.maxHp(mon) - mon.hp)
			mon.hp += heal
			table.insert(events, { t = "heal", side = i, name = Factory.displayName(mon), amount = heal, hp = mon.hp, item = "Potion" })
		end
	end
end

function Battle:_checkFaints(events)
	for i = 1, 2 do
		local mon = self:active(i)
		if mon and mon.hp <= 0 and not self.ended then
			table.insert(events, { t = "faint", side = i, name = Factory.displayName(mon) })

			-- XP for the other side when a wild/opponent creature faints (wild battles only)
			local other = 3 - i
			if self.kind == "wild" and not self.sides[other].isWild then
				local species = Creatures.get(mon.species)
				local total = math.floor(species.xpYield * mon.level / 7)
				local alive = {}
				for _, m in self.sides[other].party do
					if self.participants[other][m.uid] and m.hp > 0 then
						table.insert(alive, m)
					end
				end
				for _, m in alive do
					Factory.giveXp(m, math.max(1, math.floor(total / #alive)), events)
				end
			end

			local nextSlot = firstAlive(self.sides[i].party)
			if nextSlot then
				self.sides[i].active = nextSlot
				self.stages[i] = freshStages()
				local nm = self.sides[i].party[nextSlot]
				self.participants[i][nm.uid] = true
				table.insert(
					events,
					{ t = "switch", side = i, name = Factory.displayName(nm), species = nm.species, slot = nextSlot, forced = true }
				)
			else
				self.ended = true
				self.winner = other
			end
		end
	end
end

-- actions[1], actions[2]: { type = "move", index } | { type = "switch", slot } | { type = "catch", bonus }
--                         | { type = "run" } | { type = "item", item, slot }
function Battle:resolveTurn(actions)
	if self.ended then
		return {}
	end
	self.turn += 1
	local events = {}

	for i = 1, 2 do
		if actions[i] == nil or self.sides[i].isAI then
			actions[i] = self:chooseAIMove(i)
		end
	end

	local order = { 1, 2 }
	local function key(i)
		local a = actions[i]
		local pri = actionPriority(a)
		if a.type == "move" then
			local slot = self:active(i).moves[a.index or 0]
			local def = slot and Moves[slot.id] or Moves.Struggle
			pri += def.priority or 0
		end
		return pri
	end
	local p1, p2 = key(1), key(2)
	if p2 > p1 then
		order = { 2, 1 }
	elseif p1 == p2 then
		local s1, s2 = self:stat(1, "spe"), self:stat(2, "spe")
		if s2 > s1 or (s1 == s2 and self.rng:NextNumber() < 0.5) then
			order = { 2, 1 }
		end
	end

	for _, i in order do
		if self.ended then
			break
		end
		local a = actions[i]
		local actor = self:active(i)
		if actor and actor.hp > 0 then
			if a.type == "move" then
				self:_doMove(i, a, events)
			elseif a.type == "catch" and self.kind == "wild" then
				self:_doCatch(i, a, events)
			elseif a.type == "run" and self.kind == "wild" then
				self:_doRun(i, events)
			elseif a.type == "switch" then
				self:_doSwitch(i, a, events)
			elseif a.type == "item" then
				self:_doItem(i, a, events)
			end
		end
		self:_checkFaints(events)
	end

	if self.ended then
		table.insert(events, { t = "end", winner = self.winner, caught = self.caught ~= nil, fled = self.fled })
	end
	return events
end

-- What a given side is allowed to see.
function Battle:view(i)
	local mine = self.sides[i]
	local foeSide = self.sides[3 - i]
	local foe = self:active(3 - i)
	local party = {}
	for _, mon in mine.party do
		table.insert(party, Factory.summary(mon))
	end
	local foeView
	if foe then
		local s = Factory.summary(foe)
		foeView = { name = s.name, species = s.species, level = s.level, hp = s.hp, maxHp = s.maxHp, types = s.types, shiny = s.shiny }
	end
	return {
		kind = self.kind,
		turn = self.turn,
		active = mine.active,
		party = party,
		foe = foeView,
		foeName = foeSide.name,
		ended = self.ended,
	}
end

Battle.PvPLevel = Config.PvPLevel

return Battle
]=]
local n3 = make("ModuleScript", "Config", n1)
n3.Source = [[
-- Global tuning values. Everything gameplay-related that you may want to tweak lives here.
local Config = {
	GameName = "Tidewild",

	-- Player
	WalkSpeed = 18,
	SprintSpeed = 32,
	SprintFov = 78,
	BaseFov = 70,

	-- Party / progression
	MaxParty = 6,
	StarterLevel = 5,
	StartingOrbs = 10,
	StartingPotions = 3,
	StartingMoney = 500,
	ShinyOdds = 512, -- 1 in N

	-- Overworld spawning (Scarlet/Violet-style visible encounters)
	SpawnTickRate = 0.2, -- seconds between server AI ticks (5 Hz)
	SnapshotRadius = 220, -- creatures farther than this aren't sent to a client (interest management)
	ZoneActiveRadius = 260, -- zones only spawn while a player is this close
	DespawnAfter = 180, -- seconds a creature lives if nobody battles it
	WanderSpeed = 6,
	ChaseSpeed = 14,
	FleeSpeed = 20,
	NoticeRadius = 26,
	TouchBattleRadius = 6, -- aggressive creatures start a battle when this close

	-- Interaction
	InteractDistance = 16,
	ThrowDistance = 45,
	UnawareCatchBonus = 1.75, -- Legends-style sneak catch bonus

	-- Battles
	TurnTimeout = 30,
	PvPLevel = 50, -- plaza battles are level-normalised for fairness

	-- Plaza / social
	GreetCooldown = 4,
	PairGreetRewardCooldown = 300,
	PlazaCoinsPerGreet = 2,
	PlazaCoinsPerBattle = 10,
	PlazaCoinsPerTrade = 15,
	RequestTimeout = 20,

	-- Shop
	OrbPrice = 20,
	PotionPrice = 30,

	-- Persistence
	DataStoreName = "TidewildSave_v1",
	AutosaveInterval = 120,
}

return Config
]]
local n4 = make("ModuleScript", "CreatureFactory", n1)
n4.Source = [[
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
]]
local n5 = make("ModuleScript", "CreatureModel", n1)
n5.Source = [[
-- Builds creature models. If ReplicatedStorage.CreatureModels.<SpeciesId> exists (a Model you made or
-- licensed), it is cloned; otherwise a stylised procedural placeholder is generated from the species'
-- shape and colours so the game is fully playable with zero imported assets.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Creatures = require(script.Parent.Creatures)

local CreatureModel = {}

local SHINY_TINT = Color3.fromRGB(255, 230, 120)

local function part(model, name, shape, size, offset, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function eyes(model, headCf: CFrame, headRadius: number, s: number)
	local white = Color3.new(1, 1, 1)
	local black = Color3.fromRGB(20, 20, 30)
	for _, side in { -1, 1 } do
		local eyeCf = headCf * CFrame.new(side * headRadius * 0.4, headRadius * 0.15, -headRadius * 0.82)
		part(model, "Eye", Enum.PartType.Ball, Vector3.one * 0.32 * s, eyeCf, white)
		part(model, "Pupil", Enum.PartType.Ball, Vector3.one * 0.18 * s, eyeCf * CFrame.new(0, 0, -0.1 * s), black)
	end
end

local builders = {}

function builders.quad(model, sp, s)
	local body = part(model, "Body", Enum.PartType.Ball, Vector3.new(2.2, 1.6, 3) * s, CFrame.new(0, 1.6 * s, 0), sp.color)
	local headCf = CFrame.new(0, 2.4 * s, -1.6 * s)
	part(model, "Head", Enum.PartType.Ball, Vector3.one * 1.5 * s, headCf, sp.color)
	eyes(model, headCf, 0.75 * s, s)
	for _, side in { -1, 1 } do
		part(
			model,
			"Ear",
			Enum.PartType.Block,
			Vector3.new(0.3, 0.8, 0.3) * s,
			headCf * CFrame.new(side * 0.45 * s, 0.75 * s, 0) * CFrame.Angles(0, 0, -side * 0.3),
			sp.accent
		)
		for _, z in { -0.9, 0.9 } do
			part(
				model,
				"Leg",
				Enum.PartType.Cylinder,
				Vector3.new(1.0, 0.45, 0.45) * s,
				CFrame.new(side * 0.7 * s, 0.5 * s, z * s) * CFrame.Angles(0, 0, math.pi / 2),
				sp.color
			)
		end
	end
	part(
		model,
		"Tail",
		Enum.PartType.Ball,
		Vector3.new(0.6, 0.6, 1.4) * s,
		CFrame.new(0, 2.0 * s, 1.8 * s) * CFrame.Angles(0.6, 0, 0),
		sp.accent,
		Enum.Material.Neon
	)
	return body
end

function builders.biped(model, sp, s)
	local body = part(model, "Body", Enum.PartType.Ball, Vector3.new(1.8, 2.2, 1.6) * s, CFrame.new(0, 1.7 * s, 0), sp.color)
	local headCf = CFrame.new(0, 3.2 * s, 0)
	part(model, "Head", Enum.PartType.Ball, Vector3.one * 1.4 * s, headCf, sp.color)
	part(model, "Cap", Enum.PartType.Ball, Vector3.new(2.4, 0.9, 2.4) * s, headCf * CFrame.new(0, 0.6 * s, 0), sp.accent)
	eyes(model, headCf, 0.7 * s, s)
	for _, side in { -1, 1 } do
		part(
			model,
			"Leg",
			Enum.PartType.Cylinder,
			Vector3.new(0.9, 0.5, 0.5) * s,
			CFrame.new(side * 0.45 * s, 0.45 * s, 0) * CFrame.Angles(0, 0, math.pi / 2),
			sp.color
		)
		part(
			model,
			"Arm",
			Enum.PartType.Ball,
			Vector3.new(0.45, 1.1, 0.45) * s,
			CFrame.new(side * 1.0 * s, 1.9 * s, 0) * CFrame.Angles(0, 0, side * 0.4),
			sp.color
		)
	end
	return body
end

function builders.avian(model, sp, s)
	local body = part(model, "Body", Enum.PartType.Ball, Vector3.new(1.4, 1.3, 1.8) * s, CFrame.new(0, 2.6 * s, 0), sp.color)
	local headCf = CFrame.new(0, 3.3 * s, -0.8 * s)
	part(model, "Head", Enum.PartType.Ball, Vector3.one * 1.0 * s, headCf, sp.color)
	eyes(model, headCf, 0.5 * s, s * 0.8)
	part(model, "Beak", Enum.PartType.Block, Vector3.new(0.25, 0.25, 0.5) * s, headCf * CFrame.new(0, -0.1 * s, -0.55 * s), sp.accent)
	for _, side in { -1, 1 } do
		part(
			model,
			"Wing",
			Enum.PartType.Block,
			Vector3.new(1.8, 0.12, 1.0) * s,
			CFrame.new(side * 1.3 * s, 2.8 * s, 0) * CFrame.Angles(0, 0, side * 0.25),
			sp.accent,
			Enum.Material.Glass
		)
	end
	return body
end

function builders.serpent(model, sp, s)
	local root
	for i = 0, 4 do
		local r = (1.3 - i * 0.18) * s
		local p = part(
			model,
			i == 0 and "Body" or "Segment",
			Enum.PartType.Ball,
			Vector3.one * r,
			CFrame.new(math.sin(i * 0.9) * 0.4 * s, r / 2 + 0.2, i * 0.9 * s),
			i % 2 == 0 and sp.color or sp.accent
		)
		if i == 0 then
			root = p
		end
	end
	local headCf = CFrame.new(0, 1.4 * s, -0.9 * s)
	part(model, "Head", Enum.PartType.Ball, Vector3.one * 1.3 * s, headCf, sp.color)
	eyes(model, headCf, 0.65 * s, s)
	for _, side in { -1, 1 } do
		part(
			model,
			"Frill",
			Enum.PartType.Block,
			Vector3.new(0.1, 0.9, 0.5) * s,
			headCf * CFrame.new(side * 0.7 * s, 0.2 * s, 0.2 * s) * CFrame.Angles(0, 0, side * 0.5),
			sp.accent,
			Enum.Material.Neon
		)
	end
	return root
end

function builders.blob(model, sp, s)
	local headCf = CFrame.new(0, 1.0 * s, 0)
	local body = part(model, "Body", Enum.PartType.Ball, Vector3.new(2.0, 1.8, 2.0) * s, headCf, sp.color)
	eyes(model, headCf, 0.95 * s, s)
	part(model, "Spot", Enum.PartType.Ball, Vector3.one * 0.6 * s, headCf * CFrame.new(0.5 * s, 0.7 * s, 0.3 * s), sp.accent)
	return body
end

function CreatureModel.build(speciesId: string, shiny: boolean?): Model
	local library = ReplicatedStorage:FindFirstChild("CreatureModels")
	local custom = library and library:FindFirstChild(speciesId)
	if custom and custom:IsA("Model") then
		local m = custom:Clone()
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		return m
	end

	local sp = Creatures.get(speciesId)
	local model = Instance.new("Model")
	model.Name = speciesId
	local s = sp.size
	local spec = sp
	if shiny then
		spec = table.clone(sp)
		spec.color = sp.color:Lerp(SHINY_TINT, 0.6)
	end
	local body = (builders[sp.shape] or builders.blob)(model, spec, s)
	model.PrimaryPart = body
	-- Pivot at the feet so callers can place models directly on the ground.
	model.WorldPivot = CFrame.new(0, 0, 0)

	if shiny then
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = SHINY_TINT
		sparkle.Parent = body
	end
	return model
end

return CreatureModel
]]
local n6 = make("ModuleScript", "Creatures", n1)
n6.Source = [[
-- Original creature roster for Tidewild.
-- shape: "quad" | "biped" | "avian" | "serpent" | "blob"  (used by CreatureModel's procedural builder)
-- temperament drives overworld AI: "Aggressive" charges you, "Skittish" flees from sprinting players,
-- "Curious" walks up and watches you, "Docile" just wanders.
local Creatures = {
	Cindervix = {
		name = "Cindervix",
		types = { "Ember" },
		shape = "quad",
		size = 1.0,
		color = Color3.fromRGB(230, 120, 60),
		accent = Color3.fromRGB(255, 220, 120),
		base = { hp = 45, atk = 55, def = 45, spa = 60, spd = 50, spe = 65 },
		learnset = { { 1, "Bonk" }, { 1, "Spark" }, { 7, "Bellow" }, { 12, "FlameRush" }, { 22, "QuickDash" }, { 30, "Inferno" } },
		evolvesTo = "Pyrevix",
		evolveLevel = 18,
		catchRate = 45,
		xpYield = 62,
		temperament = "Curious",
		starter = true,
		description = "A kit-fox whose tail tip smoulders like a coal.",
	},
	Pyrevix = {
		name = "Pyrevix",
		types = { "Ember", "Shade" },
		shape = "quad",
		size = 1.6,
		color = Color3.fromRGB(180, 60, 40),
		accent = Color3.fromRGB(40, 20, 40),
		base = { hp = 75, atk = 85, def = 65, spa = 95, spd = 70, spe = 90 },
		learnset = { { 1, "Spark" }, { 1, "FlameRush" }, { 18, "Nibble" }, { 30, "Inferno" }, { 36, "Eclipse" } },
		catchRate = 45,
		xpYield = 175,
		temperament = "Aggressive",
		description = "Leaves trails of black embers when it hunts at dusk.",
	},
	Mossling = {
		name = "Mossling",
		types = { "Bloom" },
		shape = "biped",
		size = 0.9,
		color = Color3.fromRGB(110, 180, 90),
		accent = Color3.fromRGB(220, 90, 90),
		base = { hp = 55, atk = 50, def = 60, spa = 55, spd = 60, spe = 40 },
		learnset = { { 1, "Bonk" }, { 1, "LeafFlick" }, { 7, "Harden" }, { 12, "SapDrain" }, { 20, "Photosynth" }, { 28, "ThornLash" } },
		evolvesTo = "Thornwarden",
		evolveLevel = 18,
		catchRate = 45,
		xpYield = 62,
		temperament = "Docile",
		starter = true,
		description = "A mushroom-capped sprite that naps in sunny clearings.",
	},
	Thornwarden = {
		name = "Thornwarden",
		types = { "Bloom", "Stone" },
		shape = "biped",
		size = 1.7,
		color = Color3.fromRGB(70, 130, 60),
		accent = Color3.fromRGB(150, 120, 90),
		base = { hp = 90, atk = 90, def = 95, spa = 60, spd = 80, spe = 40 },
		learnset = { { 1, "SapDrain" }, { 1, "ThornLash" }, { 18, "PebbleToss" }, { 30, "Boulder" } },
		catchRate = 45,
		xpYield = 175,
		temperament = "Docile",
		description = "Guards old groves; its bark armour is as hard as granite.",
	},
	Ripplet = {
		name = "Ripplet",
		types = { "Tide" },
		shape = "serpent",
		size = 1.0,
		color = Color3.fromRGB(90, 170, 230),
		accent = Color3.fromRGB(255, 170, 200),
		base = { hp = 50, atk = 50, def = 50, spa = 60, spd = 55, spe = 55 },
		learnset = { { 1, "Bonk" }, { 1, "Squirt" }, { 7, "Harden" }, { 12, "RipTide" }, { 24, "Chill" }, { 30, "Tsunami" } },
		evolvesTo = "Mariwyrm",
		evolveLevel = 18,
		catchRate = 45,
		xpYield = 62,
		temperament = "Curious",
		starter = true,
		description = "A frilled tide-salamander that hums when it is happy.",
	},
	Mariwyrm = {
		name = "Mariwyrm",
		types = { "Tide", "Frost" },
		shape = "serpent",
		size = 1.8,
		color = Color3.fromRGB(40, 110, 200),
		accent = Color3.fromRGB(210, 245, 255),
		base = { hp = 85, atk = 70, def = 75, spa = 95, spd = 85, spe = 65 },
		learnset = { { 1, "Squirt" }, { 1, "RipTide" }, { 18, "Chill" }, { 30, "Tsunami" }, { 34, "Glacier" } },
		catchRate = 45,
		xpYield = 175,
		temperament = "Docile",
		description = "Its song can freeze the surface of a lagoon overnight.",
	},
	Burrowpup = {
		name = "Burrowpup",
		types = { "Normal" },
		shape = "quad",
		size = 0.7,
		color = Color3.fromRGB(200, 170, 130),
		accent = Color3.fromRGB(250, 240, 220),
		base = { hp = 40, atk = 45, def = 35, spa = 30, spd = 35, spe = 60 },
		learnset = { { 1, "Bonk" }, { 4, "Bellow" }, { 9, "QuickDash" }, { 20, "HyperRam" } },
		catchRate = 255,
		xpYield = 40,
		temperament = "Skittish",
		description = "Digs dozens of holes a day and forgets every one.",
	},
	Pebbit = {
		name = "Pebbit",
		types = { "Stone" },
		shape = "blob",
		size = 0.9,
		color = Color3.fromRGB(150, 140, 130),
		accent = Color3.fromRGB(90, 80, 75),
		base = { hp = 50, atk = 65, def = 85, spa = 30, spd = 40, spe = 20 },
		learnset = { { 1, "Bonk" }, { 1, "Harden" }, { 8, "PebbleToss" }, { 24, "Boulder" } },
		catchRate = 190,
		xpYield = 55,
		temperament = "Docile",
		description = "Pretends to be a rock. Is mostly successful.",
	},
	Zaphid = {
		name = "Zaphid",
		types = { "Volt", "Gale" },
		shape = "avian",
		size = 0.6,
		color = Color3.fromRGB(240, 200, 40),
		accent = Color3.fromRGB(40, 40, 60),
		base = { hp = 40, atk = 40, def = 40, spa = 70, spd = 45, spe = 85 },
		learnset = { { 1, "Zap" }, { 5, "Gust" }, { 12, "Tailwind" }, { 20, "ArcBolt" } },
		catchRate = 150,
		xpYield = 58,
		temperament = "Aggressive",
		description = "A buzzing beetle that stores static in its wing cases.",
	},
	Galeon = {
		name = "Galeon",
		types = { "Gale" },
		shape = "avian",
		size = 1.1,
		color = Color3.fromRGB(230, 235, 245),
		accent = Color3.fromRGB(80, 120, 200),
		base = { hp = 55, atk = 65, def = 50, spa = 50, spd = 50, spe = 80 },
		learnset = { { 1, "Gust" }, { 1, "QuickDash" }, { 10, "Tailwind" }, { 18, "SkyDive" } },
		catchRate = 120,
		xpYield = 70,
		temperament = "Skittish",
		description = "Rides sea breezes for days without flapping once.",
	},
	Frostfin = {
		name = "Frostfin",
		types = { "Frost", "Tide" },
		shape = "serpent",
		size = 1.2,
		color = Color3.fromRGB(180, 230, 245),
		accent = Color3.fromRGB(90, 150, 200),
		base = { hp = 60, atk = 70, def = 60, spa = 65, spd = 60, spe = 55 },
		learnset = { { 1, "Chill" }, { 1, "Squirt" }, { 14, "RipTide" }, { 26, "Glacier" } },
		catchRate = 90,
		xpYield = 90,
		temperament = "Aggressive",
		description = "Slides across highland snow on its belly fins.",
	},
	Duskmoth = {
		name = "Duskmoth",
		types = { "Shade", "Gale" },
		shape = "avian",
		size = 0.9,
		color = Color3.fromRGB(90, 60, 120),
		accent = Color3.fromRGB(250, 200, 120),
		base = { hp = 50, atk = 40, def = 45, spa = 75, spd = 65, spe = 70 },
		learnset = { { 1, "Gust" }, { 1, "Taunt" }, { 10, "Nibble" }, { 22, "Eclipse" } },
		catchRate = 120,
		xpYield = 75,
		temperament = "Curious",
		description = "Drawn to lanterns, campfires and phone screens.",
	},
	Wispurr = {
		name = "Wispurr",
		types = { "Spirit" },
		shape = "blob",
		size = 0.8,
		color = Color3.fromRGB(250, 200, 240),
		accent = Color3.fromRGB(160, 120, 220),
		base = { hp = 55, atk = 30, def = 45, spa = 70, spd = 75, spe = 60 },
		learnset = { { 1, "Twinkle" }, { 1, "Charm" }, { 16, "Radiance" } },
		catchRate = 75,
		xpYield = 85,
		temperament = "Curious",
		description = "A purring puff of light that follows travellers home.",
	},
	Shellscuttle = {
		name = "Shellscuttle",
		types = { "Tide", "Stone" },
		shape = "quad",
		size = 0.9,
		color = Color3.fromRGB(230, 110, 90),
		accent = Color3.fromRGB(250, 230, 200),
		base = { hp = 50, atk = 75, def = 90, spa = 35, spd = 45, spe = 35 },
		learnset = { { 1, "Bonk" }, { 1, "Harden" }, { 9, "Squirt" }, { 16, "PebbleToss" }, { 25, "RipTide" } },
		catchRate = 150,
		xpYield = 65,
		temperament = "Aggressive",
		description = "Pinches toes on the beach just to make a point.",
	},
}

for id, c in Creatures do
	c.id = id
end

-- Spawn tables per biome. weight = relative frequency.
Creatures.Biomes = {
	Meadow = { { "Burrowpup", 40 }, { "Mossling", 8 }, { "Zaphid", 20 }, { "Galeon", 15 }, { "Cindervix", 5 } },
	Beach = { { "Shellscuttle", 35 }, { "Ripplet", 8 }, { "Galeon", 20 }, { "Burrowpup", 15 } },
	Forest = { { "Duskmoth", 25 }, { "Mossling", 15 }, { "Wispurr", 10 }, { "Zaphid", 20 }, { "Thornwarden", 2 } },
	Highland = { { "Pebbit", 35 }, { "Frostfin", 20 }, { "Wispurr", 10 }, { "Pyrevix", 2 }, { "Mariwyrm", 2 } },
}

function Creatures.get(id: string)
	local c = Creatures[id]
	if type(c) ~= "table" or c.base == nil then
		return nil
	end
	return c
end

function Creatures.starters(): { string }
	return { "Cindervix", "Mossling", "Ripplet" }
end

return Creatures
]]
local n7 = make("ModuleScript", "Moves", n1)
n7.Source = [[
-- Original move list.
-- category: "Physical" | "Special" | "Status"
-- effect (optional): { kind = "stat", target = "self"|"foe", stat = "atk"|"def"|"spa"|"spd"|"spe", stages = n }
--                    { kind = "heal", fraction = 0.5 }
--                    { kind = "drain", fraction = 0.5 }
local Moves = {
	Bonk = { name = "Bonk", type = "Normal", category = "Physical", power = 40, accuracy = 100, pp = 35 },
	QuickDash = { name = "Quick Dash", type = "Normal", category = "Physical", power = 40, accuracy = 100, pp = 30, priority = 1 },
	Bellow = {
		name = "Bellow",
		type = "Normal",
		category = "Status",
		power = 0,
		accuracy = 100,
		pp = 30,
		effect = { kind = "stat", target = "foe", stat = "atk", stages = -1 },
	},
	Harden = {
		name = "Harden",
		type = "Normal",
		category = "Status",
		power = 0,
		accuracy = 100,
		pp = 30,
		effect = { kind = "stat", target = "self", stat = "def", stages = 1 },
	},
	HyperRam = { name = "Hyper Ram", type = "Normal", category = "Physical", power = 90, accuracy = 85, pp = 10 },

	Spark = { name = "Cinder Spit", type = "Ember", category = "Special", power = 40, accuracy = 100, pp = 25 },
	FlameRush = { name = "Flame Rush", type = "Ember", category = "Physical", power = 75, accuracy = 95, pp = 15 },
	Inferno = { name = "Sunflare", type = "Ember", category = "Special", power = 95, accuracy = 90, pp = 10 },

	Squirt = { name = "Squirt", type = "Tide", category = "Special", power = 40, accuracy = 100, pp = 25 },
	RipTide = { name = "Riptide", type = "Tide", category = "Physical", power = 75, accuracy = 95, pp = 15 },
	Tsunami = { name = "Breaker Wave", type = "Tide", category = "Special", power = 95, accuracy = 90, pp = 10 },

	LeafFlick = { name = "Leaf Flick", type = "Bloom", category = "Special", power = 40, accuracy = 100, pp = 25 },
	SapDrain = {
		name = "Sap Drain",
		type = "Bloom",
		category = "Special",
		power = 60,
		accuracy = 100,
		pp = 15,
		effect = { kind = "drain", fraction = 0.5 },
	},
	ThornLash = { name = "Thorn Lash", type = "Bloom", category = "Physical", power = 85, accuracy = 95, pp = 10 },
	Photosynth = {
		name = "Sunbathe",
		type = "Bloom",
		category = "Status",
		power = 0,
		accuracy = 100,
		pp = 10,
		effect = { kind = "heal", fraction = 0.5 },
	},

	Zap = { name = "Zap", type = "Volt", category = "Special", power = 40, accuracy = 100, pp = 30 },
	ArcBolt = { name = "Arc Bolt", type = "Volt", category = "Special", power = 80, accuracy = 95, pp = 15 },

	PebbleToss = { name = "Pebble Toss", type = "Stone", category = "Physical", power = 45, accuracy = 95, pp = 25 },
	Boulder = { name = "Boulder Drop", type = "Stone", category = "Physical", power = 85, accuracy = 90, pp = 10 },

	Gust = { name = "Gust", type = "Gale", category = "Special", power = 40, accuracy = 100, pp = 35 },
	SkyDive = { name = "Sky Dive", type = "Gale", category = "Physical", power = 80, accuracy = 95, pp = 15 },
	Tailwind = {
		name = "Tailwind",
		type = "Gale",
		category = "Status",
		power = 0,
		accuracy = 100,
		pp = 15,
		effect = { kind = "stat", target = "self", stat = "spe", stages = 2 },
	},

	Chill = { name = "Chill Breath", type = "Frost", category = "Special", power = 45, accuracy = 100, pp = 25 },
	Glacier = { name = "Glacier Spike", type = "Frost", category = "Physical", power = 85, accuracy = 90, pp = 10 },

	Nibble = { name = "Shadow Nip", type = "Shade", category = "Physical", power = 50, accuracy = 100, pp = 25 },
	Eclipse = { name = "Eclipse", type = "Shade", category = "Special", power = 80, accuracy = 100, pp = 15 },
	Taunt = {
		name = "Sneer",
		type = "Shade",
		category = "Status",
		power = 0,
		accuracy = 100,
		pp = 20,
		effect = { kind = "stat", target = "foe", stat = "spd", stages = -1 },
	},

	Twinkle = { name = "Twinkle", type = "Spirit", category = "Special", power = 45, accuracy = 100, pp = 25 },
	Radiance = { name = "Radiance", type = "Spirit", category = "Special", power = 85, accuracy = 100, pp = 10 },
	Charm = {
		name = "Lullaby",
		type = "Spirit",
		category = "Status",
		power = 0,
		accuracy = 100,
		pp = 20,
		effect = { kind = "stat", target = "foe", stat = "atk", stages = -2 },
	},

	Struggle = { name = "Struggle", type = "Normal", category = "Physical", power = 50, accuracy = 100, pp = 999, recoil = 0.25 },
}

for id, m in Moves do
	m.id = id
end

return Moves
]]
local n8 = make("ModuleScript", "Net", n1)
n8.Source = [[
-- Single source of truth for remotes. The server creates them; clients wait for them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	-- server -> client
	"ProfileUpdate", -- (profileView)
	"SpawnSnapshot", -- (list of nearby wild creatures)
	"BattleStart", -- (view, context)
	"BattleEvents", -- (events, view)
	"BattleEnd", -- (result)
	"PlazaRequest", -- (requestId, fromName, kind)
	"PlazaNotice", -- (text)
	"Greeting", -- (player, text)
	"TradeUpdate", -- (state)
	"Toast", -- (text)
	-- client -> server
	"ChooseStarter",
	"EngageCreature",
	"ThrowOrb",
	"BattleAction",
	"SetLead",
	"SetSprinting",
	"SendGreeting",
	"PlazaInvite", -- (targetPlayer, kind)
	"PlazaRespond", -- (requestId, accepted)
	"TradeOffer", -- (slot)
	"TradeConfirm",
	"TradeCancel",
	"UsePotion", -- (slot)
}

local FOLDER_NAME = "TidewildRemotes"

function Net.init()
	assert(RunService:IsServer(), "Net.init is server-only")
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in Net.Events do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local cache = {}
function Net.get(name: string): RemoteEvent
	local r = cache[name]
	if r then
		return r
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	r = folder:WaitForChild(name) :: RemoteEvent
	cache[name] = r
	return r
end

return Net
]]
local n9 = make("ModuleScript", "Types", n1)
n9.Source = [[
-- Original elemental type system.
local Types = {}

Types.List = { "Normal", "Ember", "Tide", "Bloom", "Volt", "Stone", "Gale", "Frost", "Shade", "Spirit" }

Types.Colors = {
	Normal = Color3.fromRGB(190, 186, 170),
	Ember = Color3.fromRGB(242, 110, 60),
	Tide = Color3.fromRGB(70, 140, 240),
	Bloom = Color3.fromRGB(100, 200, 90),
	Volt = Color3.fromRGB(250, 210, 50),
	Stone = Color3.fromRGB(170, 140, 100),
	Gale = Color3.fromRGB(150, 200, 240),
	Frost = Color3.fromRGB(150, 230, 235),
	Shade = Color3.fromRGB(110, 80, 140),
	Spirit = Color3.fromRGB(240, 150, 220),
}

-- Chart[attacker][defender] = multiplier (missing entries = 1)
local Chart = {
	Normal = { Stone = 0.5, Spirit = 0 },
	Ember = { Bloom = 2, Frost = 2, Tide = 0.5, Stone = 0.5, Ember = 0.5 },
	Tide = { Ember = 2, Stone = 2, Tide = 0.5, Bloom = 0.5 },
	Bloom = { Tide = 2, Stone = 2, Ember = 0.5, Gale = 0.5, Bloom = 0.5 },
	Volt = { Tide = 2, Gale = 2, Stone = 0, Bloom = 0.5, Volt = 0.5 },
	Stone = { Ember = 2, Gale = 2, Frost = 2, Bloom = 0.5 },
	Gale = { Bloom = 2, Shade = 2, Volt = 0.5, Stone = 0.5 },
	Frost = { Bloom = 2, Gale = 2, Ember = 0.5, Tide = 0.5, Frost = 0.5 },
	Shade = { Spirit = 2, Shade = 0.5, Gale = 0.5 },
	Spirit = { Shade = 2, Normal = 0, Spirit = 0.5 },
}

function Types.effectiveness(attackType: string, defenderTypes: { string }): number
	local row = Chart[attackType] or {}
	local mult = 1
	for _, t in defenderTypes do
		local m = row[t]
		if m ~= nil then
			mult *= m
		end
	end
	return mult
end

return Types
]]
local n10 = make("Script", "Server", game:GetService('ServerScriptService'))
n10.Source = [[
-- Tidewild server entry point.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

Net.init()

local Services = script:WaitForChild("Services")
local WorldBuilder = require(Services.WorldBuilder)
local DataService = require(Services.DataService)
local SpawnService = require(Services.SpawnService)
local BattleService = require(Services.BattleService)
local PlazaService = require(Services.PlazaService)

local world = WorldBuilder.build()

DataService.start()
SpawnService.start(world)
BattleService.start()
PlazaService.start(world)

-- Sprint is client-predicted; the server only accepts the flag and clamps speed so exploiters
-- can't set arbitrary WalkSpeed through this path.
Net.get("SetSprinting").OnServerEvent:Connect(function(player, on)
	on = on == true
	player:SetAttribute("Sprinting", on)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = on and Config.SprintSpeed or Config.WalkSpeed
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		hum.WalkSpeed = Config.WalkSpeed
		player:SetAttribute("Sprinting", false)
		player:SetAttribute("InBattle", false)
	end)
end)

print(("[%s] server ready"):format(Config.GameName))
]]
local n11 = make("Folder", "Services", n10)
local n12 = make("ModuleScript", "BattleService", n11)
n12.Source = [[
-- Runs wild and player-vs-player battles in the overworld. Battles happen where the encounter
-- happened (no screen transition); clients stage their creatures in the world around the player.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)
local Factory = require(Shared.CreatureFactory)
local Battle = require(Shared.BattleEngine)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local SpawnService = require(script.Parent.SpawnService)

local BattleService = {}
BattleService.OnPvPFinished = nil :: ((Player, Player, Player?) -> ())?

local sessions = {} :: { [Player]: { session: any, side: number } }

local function setInBattle(player: Player, v: boolean)
	player:SetAttribute("InBattle", v)
end

function BattleService.isBusy(player: Player): boolean
	return sessions[player] ~= nil
end

local function sendStart(session)
	for side, plr in session.players do
		if plr then
			Net.get("BattleStart"):FireClient(plr, session.battle:view(side), session.context[side])
		end
	end
end

local function teleportToPlaza(player: Player)
	local spawn = Workspace:FindFirstChild("World") and Workspace.World:FindFirstChild("PlazaSpawn", true)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if spawn and root then
		root.CFrame = spawn.CFrame + Vector3.new(0, 4, 0)
	end
end

local function finish(session)
	local battle = session.battle
	for side, plr in session.players do
		if plr then
			sessions[plr] = nil
			setInBattle(plr, false)
		end
	end

	if session.kind == "wild" then
		local plr = session.players[1]
		local ent = session.entity
		local result = { kind = "wild" }
		if battle.caught then
			local where = DataService.addCreature(plr, battle.caught)
			DataService.get(plr).stats.caught += 1
			result.caught = Factory.displayName(battle.caught)
			result.where = where
			SpawnService.remove(ent.id)
		elseif battle.fled then
			ent.inBattle = false
			ent.born = os.clock()
			result.fled = true
		elseif battle.winner == 1 then
			local reward = 20 + ent.mon.level * 6
			local profile = DataService.get(plr)
			profile.money += reward
			profile.stats.battlesWon += 1
			result.won = true
			result.money = reward
			SpawnService.remove(ent.id)
		else
			-- Whiteout: heal up and return to the plaza.
			ent.inBattle = false
			result.lost = true
			DataService.healParty(plr)
			teleportToPlaza(plr)
		end
		if plr.Parent then
			Net.get("BattleEnd"):FireClient(plr, result)
			DataService.push(plr)
		end
	else
		local p1, p2 = session.players[1], session.players[2]
		local winner = battle.winner and session.players[battle.winner] or nil
		for side, plr in session.players do
			if plr.Parent then
				local profile = DataService.get(plr)
				if profile then
					local won = battle.winner == side
					profile.plazaCoins += won and Config.PlazaCoinsPerBattle or math.floor(Config.PlazaCoinsPerBattle / 2)
					if won then
						profile.stats.battlesWon += 1
					end
				end
				Net.get("BattleEnd")
					:FireClient(plr, { kind = "pvp", won = battle.winner == side, opponent = session.players[3 - side].DisplayName })
				DataService.push(plr)
			end
		end
		if BattleService.OnPvPFinished then
			BattleService.OnPvPFinished(p1, p2, winner)
		end
	end
end

local function runTurn(session)
	local battle = session.battle
	local actions = session.pending
	session.pending = {}
	local events = battle:resolveTurn(actions)
	for side, plr in session.players do
		if plr and plr.Parent then
			Net.get("BattleEvents"):FireClient(plr, events, battle:view(side))
		end
	end
	if battle.ended then
		finish(session)
	else
		session.deadline = os.clock() + Config.TurnTimeout
	end
end

function BattleService.startWild(player: Player, ent, preBuilt)
	if sessions[player] or ent.inBattle then
		return false
	end
	local profile = DataService.get(player)
	if not profile or not DataService.hasUsableCreature(profile) then
		Net.get("Toast"):FireClient(player, "Your creatures need rest — visit the Care Fountain in the plaza.")
		return false
	end
	ent.inBattle = true
	profile.dex.seen[ent.mon.species] = true

	local battle = preBuilt
		or Battle.new(
			"wild",
			{ name = player.DisplayName, party = profile.party },
			{ name = "Wild " .. Creatures.get(ent.mon.species).name, party = { ent.mon }, isWild = true, isAI = true }
		)
	local session = {
		kind = "wild",
		battle = battle,
		players = { player },
		entity = ent,
		pending = {},
		context = { { side = 1, entityId = ent.id, foePos = ent.pos } },
		deadline = math.huge,
	}
	sessions[player] = { session = session, side = 1 }
	setInBattle(player, true)
	sendStart(session)
	return true
end

local function pvpParty(profile)
	local out = {}
	for _, mon in profile.party do
		local c = Factory.copy(mon)
		c.level = Config.PvPLevel
		Factory.heal(c)
		table.insert(out, c)
	end
	return out
end

function BattleService.startPvP(p1: Player, p2: Player)
	if sessions[p1] or sessions[p2] then
		return false
	end
	local a, b = DataService.get(p1), DataService.get(p2)
	if not a or not b or #a.party == 0 or #b.party == 0 then
		return false
	end
	local battle = Battle.new("pvp", { name = p1.DisplayName, party = pvpParty(a) }, { name = p2.DisplayName, party = pvpParty(b) })
	local r1 = p1.Character and p1.Character:FindFirstChild("HumanoidRootPart")
	local r2 = p2.Character and p2.Character:FindFirstChild("HumanoidRootPart")
	local session = {
		kind = "pvp",
		battle = battle,
		players = { p1, p2 },
		pending = {},
		context = {
			{ side = 1, opponentUserId = p2.UserId, foePos = r2 and r2.Position },
			{ side = 2, opponentUserId = p1.UserId, foePos = r1 and r1.Position },
		},
		deadline = os.clock() + Config.TurnTimeout,
	}
	sessions[p1] = { session = session, side = 1 }
	sessions[p2] = { session = session, side = 2 }
	setInBattle(p1, true)
	setInBattle(p2, true)
	sendStart(session)
	return true
end

local function sanitizeAction(player: Player, session, side: number, raw)
	if type(raw) ~= "table" or type(raw.type) ~= "string" then
		return nil
	end
	local battle = session.battle
	local profile = DataService.get(player)
	local mine = battle.sides[side]
	if raw.type == "move" then
		local idx = tonumber(raw.index)
		local mon = battle:active(side)
		if idx and mon and mon.moves[math.floor(idx)] then
			return { type = "move", index = math.floor(idx) }
		end
	elseif raw.type == "switch" then
		local slot = tonumber(raw.slot)
		if slot and mine.party[math.floor(slot)] and mine.party[math.floor(slot)].hp > 0 then
			return { type = "switch", slot = math.floor(slot) }
		end
	elseif raw.type == "catch" and session.kind == "wild" then
		if profile.orbs > 0 then
			profile.orbs -= 1
			return { type = "catch", bonus = 1 }
		end
		Net.get("Toast"):FireClient(player, "You're out of Orbs!")
	elseif raw.type == "item" and raw.item == "Potion" then
		if profile.potions > 0 then
			profile.potions -= 1
			return { type = "item", item = "Potion", slot = mine.active }
		end
	elseif raw.type == "run" then
		if session.kind == "wild" then
			return { type = "run" }
		end
		-- Forfeit in PvP
		battle.ended = true
		battle.winner = 3 - side
		for s, plr in session.players do
			Net.get("BattleEvents")
				:FireClient(plr, { { t = "forfeit", side = side }, { t = "end", winner = battle.winner } }, battle:view(s))
		end
		finish(session)
		return nil
	end
	return nil
end

function BattleService.start()
	SpawnService.OnTouchBattle = function(player, ent)
		BattleService.startWild(player, ent)
	end

	Net.get("EngageCreature").OnServerEvent:Connect(function(player, id)
		local ent = SpawnService.Entities[tonumber(id) or -1]
		if ent and SpawnService.distanceTo(player, ent) <= Config.InteractDistance then
			BattleService.startWild(player, ent)
		end
	end)

	-- Legends-style overworld throw: sneak up for a bonus. A miss can start a battle or scare it off.
	Net.get("ThrowOrb").OnServerEvent:Connect(function(player, id)
		local ent = SpawnService.Entities[tonumber(id) or -1]
		local profile = DataService.get(player)
		if not ent or not profile or ent.inBattle or sessions[player] then
			return
		end
		if SpawnService.distanceTo(player, ent) > Config.ThrowDistance or profile.orbs <= 0 then
			return
		end
		profile.orbs -= 1
		local bonus = SpawnService.isUnaware(player, ent) and Config.UnawareCatchBonus or 1
		local battle = Battle.new(
			"wild",
			{ name = player.DisplayName, party = profile.party },
			{ name = "Wild " .. Creatures.get(ent.mon.species).name, party = { ent.mon }, isWild = true, isAI = true }
		)
		local events = {}
		battle:_doCatch(1, { bonus = bonus }, events)
		local ev = events[1]
		Net.get("BattleEvents"):FireClient(player, { ev, { t = "overworldThrow", entityId = ent.id, bonus = bonus > 1 } }, nil)
		if ev.success then
			local where = DataService.addCreature(player, ent.mon)
			profile.stats.caught += 1
			SpawnService.remove(ent.id)
			Net.get("Toast"):FireClient(player, ("Caught %s!%s"):format(ev.name, where == "box" and " (sent to box)" or ""))
		elseif DataService.hasUsableCreature(profile) and math.random() < 0.6 then
			battle.ended = false
			battle.caught = nil
			BattleService.startWild(player, ent, battle)
		else
			Net.get("Toast"):FireClient(player, ev.name .. " broke free and ran off!")
			SpawnService.remove(ent.id)
		end
		DataService.push(player)
	end)

	Net.get("BattleAction").OnServerEvent:Connect(function(player, raw)
		local entry = sessions[player]
		if not entry then
			return
		end
		local session = entry.session
		if session.battle.ended or session.pending[entry.side] then
			return
		end
		local action = sanitizeAction(player, session, entry.side, raw)
		if not action then
			return
		end
		session.pending[entry.side] = action
		if session.kind == "wild" or (session.pending[1] and session.pending[2]) then
			runTurn(session)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local entry = sessions[player]
		if entry then
			local session = entry.session
			session.battle.ended = true
			session.battle.winner = 3 - entry.side
			if session.kind == "wild" then
				session.battle.fled = true
			end
			finish(session)
		end
	end)

	-- PvP turn timer: idle players get an AI-chosen move.
	task.spawn(function()
		while true do
			task.wait(1)
			local seen = {}
			for _, entry in sessions do
				local s = entry.session
				if not seen[s] and s.kind == "pvp" and os.clock() > s.deadline and not s.battle.ended then
					seen[s] = true
					runTurn(s)
				end
			end
		end
	end)
end

return BattleService
]]
local n13 = make("ModuleScript", "DataService", n11)
n13.Source = [[
-- Player save data with DataStore persistence and session caching.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)
local Factory = require(Shared.CreatureFactory)
local Net = require(Shared.Net)

local DataService = {}
DataService.Profiles = {} :: { [Player]: any }

local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[Tidewild] DataStore unavailable (enable Studio API access to persist saves):", result)
	end
end

local function defaultProfile()
	return {
		version = 1,
		party = {},
		box = {},
		orbs = Config.StartingOrbs,
		potions = Config.StartingPotions,
		money = Config.StartingMoney,
		plazaCoins = 0,
		dex = { seen = {}, caught = {} },
		stats = { battlesWon = 0, caught = 0, trades = 0, greets = 0 },
	}
end

local function reconcile(data)
	local def = defaultProfile()
	for k, v in def do
		if data[k] == nil then
			data[k] = v
		end
	end
	return data
end

function DataService.load(player: Player)
	local data
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return store:GetAsync("u_" .. player.UserId)
			end)
			if ok then
				data = result
				break
			end
			warn("[Tidewild] load failed, retrying", attempt, result)
			task.wait(attempt)
		end
	end
	local profile = reconcile(data or defaultProfile())
	-- Drop creatures from species that no longer exist (e.g. after editing the roster).
	for _, list in { profile.party, profile.box } do
		for i = #list, 1, -1 do
			if not Creatures.get(list[i].species) then
				table.remove(list, i)
			end
		end
	end
	DataService.Profiles[player] = profile
	DataService.push(player)
	DataService.updateLeadAttribute(player)
	return profile
end

function DataService.save(player: Player)
	local profile = DataService.Profiles[player]
	if not profile or not store then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync("u_" .. player.UserId, profile)
	end)
	if not ok then
		warn("[Tidewild] save failed for", player.Name, err)
	end
end

function DataService.get(player: Player)
	return DataService.Profiles[player]
end

function DataService.view(profile)
	local party = {}
	for _, mon in profile.party do
		table.insert(party, Factory.summary(mon))
	end
	local seen, caught = 0, 0
	for _ in profile.dex.seen do
		seen += 1
	end
	for _ in profile.dex.caught do
		caught += 1
	end
	return {
		party = party,
		boxCount = #profile.box,
		orbs = profile.orbs,
		potions = profile.potions,
		money = profile.money,
		plazaCoins = profile.plazaCoins,
		plazaRank = 1 + math.floor(math.sqrt(profile.plazaCoins / 10)),
		dexSeen = seen,
		dexCaught = caught,
		needsStarter = #profile.party == 0 and #profile.box == 0,
	}
end

function DataService.push(player: Player)
	local profile = DataService.Profiles[player]
	if profile then
		Net.get("ProfileUpdate"):FireClient(player, DataService.view(profile))
		DataService.updateLeadAttribute(player)
	end
end

-- Replicated attributes let every client render each player's lead creature walking beside them
-- without any server-side physics cost.
function DataService.updateLeadAttribute(player: Player)
	local profile = DataService.Profiles[player]
	local lead = profile and profile.party[1]
	player:SetAttribute("LeadSpecies", lead and lead.species or "")
	player:SetAttribute("LeadShiny", lead and lead.shiny or false)
	if profile then
		player:SetAttribute("PlazaRank", DataService.view(profile).plazaRank)
	end
end

function DataService.addCreature(player: Player, mon)
	local profile = DataService.Profiles[player]
	profile.dex.caught[mon.species] = true
	profile.dex.seen[mon.species] = true
	if #profile.party < Config.MaxParty then
		table.insert(profile.party, mon)
		return "party"
	end
	table.insert(profile.box, mon)
	return "box"
end

function DataService.healParty(player: Player)
	local profile = DataService.Profiles[player]
	if not profile then
		return
	end
	for _, mon in profile.party do
		Factory.heal(mon)
	end
	DataService.push(player)
end

function DataService.hasUsableCreature(profile): boolean
	for _, mon in profile.party do
		if mon.hp > 0 then
			return true
		end
	end
	return false
end

function DataService.start()
	Net.get("ChooseStarter").OnServerEvent:Connect(function(player, speciesId)
		local profile = DataService.Profiles[player]
		if not profile or #profile.party > 0 or #profile.box > 0 then
			return
		end
		if type(speciesId) ~= "string" or not table.find(Creatures.starters(), speciesId) then
			return
		end
		DataService.addCreature(player, Factory.new(speciesId, Config.StarterLevel))
		DataService.push(player)
		Net.get("Toast"):FireClient(player, "You and your new partner are ready to explore!")
	end)

	Net.get("SetLead").OnServerEvent:Connect(function(player, slot)
		local profile = DataService.Profiles[player]
		if not profile or type(slot) ~= "number" or player:GetAttribute("InBattle") then
			return
		end
		slot = math.floor(slot)
		local mon = profile.party[slot]
		if mon and slot ~= 1 then
			table.remove(profile.party, slot)
			table.insert(profile.party, 1, mon)
			DataService.push(player)
		end
	end)

	Net.get("UsePotion").OnServerEvent:Connect(function(player, slot)
		local profile = DataService.Profiles[player]
		if not profile or type(slot) ~= "number" or profile.potions <= 0 or player:GetAttribute("InBattle") then
			return
		end
		local mon = profile.party[math.floor(slot)]
		if mon and mon.hp > 0 and mon.hp < Factory.maxHp(mon) then
			mon.hp = math.min(Factory.maxHp(mon), mon.hp + 30 + math.floor(Factory.maxHp(mon) * 0.25))
			profile.potions -= 1
			DataService.push(player)
		end
	end)

	Players.PlayerAdded:Connect(DataService.load)
	for _, p in Players:GetPlayers() do
		task.spawn(DataService.load, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player)
		DataService.Profiles[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in DataService.Profiles do
				task.spawn(DataService.save, player)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local threads = {}
		for player in DataService.Profiles do
			table.insert(threads, task.spawn(DataService.save, player))
		end
		task.wait(2)
	end)
end

return DataService
]]
local n14 = make("ModuleScript", "PlazaService", n11)
n14.Source = [[
-- Social hub systems inspired by "plaza" style lobbies: quick greetings that earn Plaza Coins,
-- battle / trade invitations between any two players, a server-validated two-step trade, and the
-- heal / shop stations. Normal text chat is Roblox's built-in TextChatService (filtered by Roblox).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Factory = require(Shared.CreatureFactory)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local BattleService = require(script.Parent.BattleService)

local PlazaService = {}

-- Preset greetings only: they're safe to broadcast without filtering and work for every age group.
PlazaService.Greetings = {
	"Hello!",
	"Nice to meet you!",
	"Want to battle?",
	"Want to trade?",
	"Thank you!",
	"Good game!",
	"Cool creature!",
	"Let's explore together!",
	"See you later!",
	"I'm hunting shinies!",
}

local lastGreet = {} :: { [Player]: number }
local pairReward = {} :: { [string]: number }
local requests = {} :: { [string]: any }
local trades = {} :: { [Player]: any }

local function pairKey(a: Player, b: Player)
	local x, y = a.UserId, b.UserId
	if x > y then
		x, y = y, x
	end
	return x .. ":" .. y
end

local function rootOf(p: Player)
	return p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------------------------ Trades
local function tradeState(t, forPlayer)
	local other = t.a == forPlayer and t.b or t.a
	local function offerView(p)
		local slot = t.offers[p]
		local mon = slot and DataService.get(p).party[slot]
		return mon and Factory.summary(mon) or nil
	end
	return {
		open = true,
		partner = other.DisplayName,
		myOffer = offerView(forPlayer),
		theirOffer = offerView(other),
		myConfirm = t.confirm[forPlayer] == true,
		theirConfirm = t.confirm[other] == true,
	}
end

local function pushTrade(t)
	for _, p in { t.a, t.b } do
		if p.Parent then
			Net.get("TradeUpdate"):FireClient(p, tradeState(t, p))
		end
	end
end

local function closeTrade(t, reason)
	trades[t.a] = nil
	trades[t.b] = nil
	for _, p in { t.a, t.b } do
		if p.Parent then
			Net.get("TradeUpdate"):FireClient(p, { open = false, reason = reason })
		end
	end
end

local function startTrade(a: Player, b: Player)
	if trades[a] or trades[b] or BattleService.isBusy(a) or BattleService.isBusy(b) then
		return
	end
	local t = { a = a, b = b, offers = {}, confirm = {} }
	trades[a], trades[b] = t, t
	pushTrade(t)
end

local function executeTrade(t)
	local pa, pb = DataService.get(t.a), DataService.get(t.b)
	local sa, sb = t.offers[t.a], t.offers[t.b]
	local ma, mb = pa and pa.party[sa], pb and pb.party[sb]
	if not ma or not mb then
		closeTrade(t, "Trade failed — an offer was no longer valid.")
		return
	end
	pa.party[sa], pb.party[sb] = mb, ma
	pa.dex.caught[mb.species], pa.dex.seen[mb.species] = true, true
	pb.dex.caught[ma.species], pb.dex.seen[ma.species] = true, true
	for _, prof in { pa, pb } do
		prof.plazaCoins += Config.PlazaCoinsPerTrade
		prof.stats.trades += 1
	end
	-- Save both immediately so a crash can't duplicate or lose creatures.
	task.spawn(DataService.save, t.a)
	task.spawn(DataService.save, t.b)
	closeTrade(t, ("Traded %s for %s!"):format(Factory.displayName(ma), Factory.displayName(mb)))
	DataService.push(t.a)
	DataService.push(t.b)
end

------------------------------------------------------------------ Stations
local function hookStations(world)
	local plaza = world:FindFirstChild("Plaza")
	if not plaza then
		return
	end
	for _, prompt in plaza:GetDescendants() do
		if prompt:IsA("ProximityPrompt") then
			prompt.Triggered:Connect(function(player)
				local profile = DataService.get(player)
				if not profile or BattleService.isBusy(player) then
					return
				end
				if prompt.Name == "HealPrompt" then
					DataService.healParty(player)
					Net.get("Toast"):FireClient(player, "Your party is fully healed!")
				elseif prompt.Name == "OrbPrompt" then
					local cost = Config.OrbPrice * 5
					if profile.money >= cost then
						profile.money -= cost
						profile.orbs += 5
						Net.get("Toast"):FireClient(player, "Bought 5 Orbs.")
					else
						Net.get("Toast"):FireClient(player, "Not enough coins.")
					end
				elseif prompt.Name == "PotionPrompt" then
					local cost = Config.PotionPrice * 3
					if profile.money >= cost then
						profile.money -= cost
						profile.potions += 3
						Net.get("Toast"):FireClient(player, "Bought 3 Potions.")
					else
						Net.get("Toast"):FireClient(player, "Not enough coins.")
					end
				end
				DataService.push(player)
			end)
		end
	end
end

function PlazaService.start(world)
	hookStations(world)

	Net.get("SendGreeting").OnServerEvent:Connect(function(player, index)
		local text = PlazaService.Greetings[tonumber(index) or 0]
		if not text then
			return
		end
		local now = os.clock()
		if lastGreet[player] and now - lastGreet[player] < Config.GreetCooldown then
			return
		end
		lastGreet[player] = now
		local root = rootOf(player)
		if not root then
			return
		end
		local profile = DataService.get(player)
		for _, other in Players:GetPlayers() do
			local r = rootOf(other)
			if r and (r.Position - root.Position).Magnitude < 80 then
				Net.get("Greeting"):FireClient(other, player, text)
				-- Reward meeting new people (per pair cooldown, so it can't be farmed)
				if other ~= player and (r.Position - root.Position).Magnitude < 25 and profile then
					local key = pairKey(player, other)
					if not pairReward[key] or now - pairReward[key] > Config.PairGreetRewardCooldown then
						pairReward[key] = now
						local op = DataService.get(other)
						profile.plazaCoins += Config.PlazaCoinsPerGreet
						profile.stats.greets += 1
						if op then
							op.plazaCoins += Config.PlazaCoinsPerGreet
							DataService.push(other)
						end
						DataService.push(player)
					end
				end
			end
		end
	end)

	Net.get("PlazaInvite").OnServerEvent:Connect(function(player, target, kind)
		if typeof(target) ~= "Instance" or not target:IsA("Player") or target == player then
			return
		end
		if kind ~= "battle" and kind ~= "trade" then
			return
		end
		if BattleService.isBusy(player) or BattleService.isBusy(target) or trades[player] or trades[target] then
			Net.get("Toast"):FireClient(player, target.DisplayName .. " is busy right now.")
			return
		end
		local id = HttpService:GenerateGUID(false)
		requests[id] = { from = player, to = target, kind = kind, expires = os.clock() + Config.RequestTimeout }
		Net.get("PlazaRequest"):FireClient(target, id, player.DisplayName, kind)
		Net.get("Toast"):FireClient(player, ("Sent a %s request to %s."):format(kind, target.DisplayName))
	end)

	Net.get("PlazaRespond").OnServerEvent:Connect(function(player, id, accepted)
		local req = requests[id]
		if not req or req.to ~= player then
			return
		end
		requests[id] = nil
		if os.clock() > req.expires or not req.from.Parent then
			return
		end
		if not accepted then
			Net.get("Toast"):FireClient(req.from, player.DisplayName .. " declined.")
			return
		end
		if req.kind == "battle" then
			if not BattleService.startPvP(req.from, player) then
				Net.get("Toast"):FireClient(req.from, "Couldn't start the battle.")
			end
		else
			startTrade(req.from, player)
		end
	end)

	Net.get("TradeOffer").OnServerEvent:Connect(function(player, slot)
		local t = trades[player]
		local profile = DataService.get(player)
		slot = tonumber(slot)
		if not t or not profile or not slot or not profile.party[math.floor(slot)] then
			return
		end
		t.offers[player] = math.floor(slot)
		t.confirm = {} -- any change resets both confirmations
		pushTrade(t)
	end)

	Net.get("TradeConfirm").OnServerEvent:Connect(function(player)
		local t = trades[player]
		if not t or not t.offers[t.a] or not t.offers[t.b] then
			return
		end
		t.confirm[player] = true
		if t.confirm[t.a] and t.confirm[t.b] then
			executeTrade(t)
		else
			pushTrade(t)
		end
	end)

	Net.get("TradeCancel").OnServerEvent:Connect(function(player)
		local t = trades[player]
		if t then
			closeTrade(t, player.DisplayName .. " cancelled the trade.")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastGreet[player] = nil
		local t = trades[player]
		if t then
			closeTrade(t, "Your trade partner left.")
		end
	end)

	BattleService.OnPvPFinished = function(p1, p2)
		for _, p in { p1, p2 } do
			if p.Parent then
				Net.get("PlazaNotice"):FireClient(p, "Plaza Coins earned for battling!")
			end
		end
	end

	-- Periodic plaza-wide announcement keeps the hangout lively.
	task.spawn(function()
		while true do
			task.wait(240)
			local best, bestCoins = nil, -1
			for p, prof in DataService.Profiles do
				if prof.plazaCoins > bestCoins then
					best, bestCoins = p, prof.plazaCoins
				end
			end
			if best then
				for _, p in Players:GetPlayers() do
					Net.get("PlazaNotice"):FireClient(p, ("Top plaza socialite: %s (%d coins)"):format(best.DisplayName, bestCoins))
				end
			end
		end
	end)
end

return PlazaService
]]
local n15 = make("ModuleScript", "SpawnService", n11)
n15.Source = [[
-- Visible overworld spawns with temperament-driven AI (no random grass encounters).
-- The server simulates lightweight entities (just tables: position, heading, state) at 5 Hz and sends
-- each client only the creatures near them. Clients build and animate the models locally, so the
-- server never replicates hundreds of moving parts — that's the main performance win.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)
local Factory = require(Shared.CreatureFactory)
local Net = require(Shared.Net)

local SpawnService = {}
SpawnService.Entities = {} :: { [number]: any }
SpawnService.OnTouchBattle = nil :: ((Player, any) -> ())?

local nextId = 0
local rng = Random.new()
local zones = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function groundAt(x: number, z: number, fallbackY: number): number?
	local result = Workspace:Raycast(Vector3.new(x, fallbackY + 80, z), Vector3.new(0, -200, 0), rayParams)
	if result then
		if result.Material == Enum.Material.Water then
			return nil
		end
		return result.Position.Y
	end
	return nil
end

local function pickSpecies(biome: string): string?
	local tbl = Creatures.Biomes[biome]
	if not tbl then
		return nil
	end
	local total = 0
	for _, e in tbl do
		total += e[2]
	end
	local roll = rng:NextNumber(0, total)
	for _, e in tbl do
		roll -= e[2]
		if roll <= 0 then
			return e[1]
		end
	end
	return tbl[1][1]
end

local function randomPointIn(zonePart: BasePart): (number, number)
	local half = zonePart.Size / 2
	local local_ = Vector3.new(rng:NextNumber(-half.X, half.X), 0, rng:NextNumber(-half.Z, half.Z))
	local world = zonePart.CFrame:PointToWorldSpace(local_)
	return world.X, world.Z
end

local function spawnIn(zoneState)
	local part = zoneState.part
	local speciesId = pickSpecies(part:GetAttribute("Biome"))
	if not speciesId then
		return
	end
	local x, z = randomPointIn(part)
	local y = groundAt(x, z, part.Position.Y)
	if not y then
		return
	end
	nextId += 1
	local minL = part:GetAttribute("MinLevel") or 2
	local maxL = part:GetAttribute("MaxLevel") or 5
	local mon = Factory.new(speciesId, rng:NextInteger(minL, maxL), rng)
	local ent = {
		id = nextId,
		mon = mon,
		zone = zoneState,
		pos = Vector3.new(x, y, z),
		heading = rng:NextNumber(0, math.pi * 2),
		state = "Wander",
		target = nil,
		born = os.clock(),
		temperament = Creatures.get(speciesId).temperament,
		inBattle = false,
	}
	SpawnService.Entities[ent.id] = ent
	zoneState.count += 1
end

function SpawnService.remove(id: number)
	local ent = SpawnService.Entities[id]
	if ent then
		SpawnService.Entities[id] = nil
		ent.zone.count -= 1
	end
end

local function nearestPlayer(pos: Vector3, radius: number)
	local best, bestDist = nil, radius
	for _, plr in Players:GetPlayers() do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root and not plr:GetAttribute("InBattle") then
			local d = (root.Position - pos).Magnitude
			if d < bestDist then
				best, bestDist = plr, d
			end
		end
	end
	return best, bestDist
end

local function stepEntity(ent, dt: number)
	if ent.inBattle then
		return
	end
	local plr, dist = nearestPlayer(ent.pos, Config.NoticeRadius)
	local speed = 0
	local temperament = ent.temperament

	if plr then
		local root = plr.Character.HumanoidRootPart
		local toPlayer = (root.Position - ent.pos) * Vector3.new(1, 0, 1)
		local dirAngle = math.atan2(-toPlayer.X, -toPlayer.Z)
		if temperament == "Aggressive" then
			ent.state = "Approach"
			ent.heading = dirAngle
			speed = Config.ChaseSpeed
			if dist <= Config.TouchBattleRadius and SpawnService.OnTouchBattle and os.clock() >= (ent.nextTouch or 0) then
				ent.nextTouch = os.clock() + 5 -- don't retry every tick if the battle can't start
				SpawnService.OnTouchBattle(plr, ent)
				return
			end
		elseif temperament == "Skittish" and (plr:GetAttribute("Sprinting") or dist < 10) then
			ent.state = "Flee"
			ent.heading = dirAngle + math.pi
			speed = Config.FleeSpeed
		elseif temperament == "Curious" then
			ent.state = dist > 9 and "Approach" or "Watch"
			ent.heading = dirAngle
			speed = dist > 9 and Config.WanderSpeed or 0
		else
			ent.state = "Wander"
		end
	else
		ent.state = "Wander"
	end

	if ent.state == "Wander" then
		if rng:NextNumber() < 0.08 then
			ent.heading += rng:NextNumber(-1.2, 1.2)
		end
		speed = rng:NextNumber() < 0.6 and Config.WanderSpeed or 0
	end

	if speed > 0 then
		local dir = Vector3.new(-math.sin(ent.heading), 0, -math.cos(ent.heading))
		local nx, nz = ent.pos.X + dir.X * speed * dt, ent.pos.Z + dir.Z * speed * dt
		-- Stay roughly inside the home zone
		local localP = ent.zone.part.CFrame:PointToObjectSpace(Vector3.new(nx, ent.pos.Y, nz))
		local half = ent.zone.part.Size / 2 + Vector3.new(30, 0, 30)
		if math.abs(localP.X) > half.X or math.abs(localP.Z) > half.Z then
			ent.heading += math.pi
			return
		end
		local y = groundAt(nx, nz, ent.pos.Y)
		if y and math.abs(y - ent.pos.Y) < 6 then
			ent.pos = Vector3.new(nx, y, nz)
		else
			ent.heading += math.pi / 2
		end
	end
end

local function zoneHasPlayerNearby(zoneState): boolean
	for _, plr in Players:GetPlayers() do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - zoneState.part.Position).Magnitude < Config.ZoneActiveRadius + zoneState.part.Size.Magnitude / 2 then
			return true
		end
	end
	return false
end

local function broadcast()
	local snapshotRemote = Net.get("SpawnSnapshot")
	for _, plr in Players:GetPlayers() do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local list = {}
			for id, ent in SpawnService.Entities do
				if (ent.pos - root.Position).Magnitude < Config.SnapshotRadius then
					-- Compact array: { id, species, x, y, z, heading, level, shiny, state }
					table.insert(list, {
						id,
						ent.mon.species,
						math.floor(ent.pos.X * 10) / 10,
						math.floor(ent.pos.Y * 10) / 10,
						math.floor(ent.pos.Z * 10) / 10,
						math.floor(ent.heading * 100) / 100,
						ent.mon.level,
						ent.mon.shiny,
						ent.inBattle and "Battle" or ent.state,
					})
				end
			end
			snapshotRemote:FireClient(plr, list)
		end
	end
end

function SpawnService.start(world: Folder)
	local zoneFolder = world:WaitForChild("SpawnZones")
	local filter = { Workspace.Terrain }
	for _, child in world:GetChildren() do
		if child.Name ~= "SpawnZones" then
			table.insert(filter, child)
		end
	end
	rayParams.FilterDescendantsInstances = filter

	for _, part in zoneFolder:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(zones, { part = part, count = 0 })
		end
	end

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.SpawnTickRate)
			local now = os.clock()
			local dt = now - last
			last = now

			for _, z in zones do
				local active = zoneHasPlayerNearby(z)
				local max = z.part:GetAttribute("MaxSpawns") or 8
				if active and z.count < max and rng:NextNumber() < 0.35 then
					spawnIn(z)
				end
				z.active = active
			end

			for id, ent in SpawnService.Entities do
				if not ent.inBattle and (not ent.zone.active or now - ent.born > Config.DespawnAfter) then
					SpawnService.remove(id)
				else
					stepEntity(ent, dt)
				end
			end

			broadcast()
		end
	end)
end

function SpawnService.distanceTo(player: Player, ent): number
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return math.huge
	end
	return (root.Position - ent.pos).Magnitude
end

-- True if the player is outside the creature's view cone or the creature is wandering away.
function SpawnService.isUnaware(player: Player, ent): boolean
	if ent.state == "Approach" or ent.state == "Watch" or ent.state == "Flee" then
		return false
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local facing = Vector3.new(-math.sin(ent.heading), 0, -math.cos(ent.heading))
	local toPlayer = ((root.Position - ent.pos) * Vector3.new(1, 0, 1)).Unit
	return facing:Dot(toPlayer) < 0.3
end

return SpawnService
]]
local n16 = make("ModuleScript", "WorldBuilder", n11)
n16.Source = [[
-- Generates a playable starter island (terrain, plaza hub, heal station, shop, spawn zones) the first
-- time the place runs. If Workspace already contains a folder named "World" (e.g. you built your own
-- map in Studio), nothing is generated and your map's SpawnZones are used instead.
--
-- Spawn zone contract (for custom maps): Workspace.World.SpawnZones contains anchored, invisible
-- Parts with attributes Biome (string, key of Creatures.Biomes), MinLevel, MaxLevel, MaxSpawns.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local WorldBuilder = {}

local terrain = Workspace.Terrain

local function anchoredPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	return p
end

local function zone(parent, name, cf, size, biome, minL, maxL, maxSpawns)
	local z = anchoredPart({
		Name = name,
		CFrame = cf,
		Size = size,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = parent,
	})
	z:SetAttribute("Biome", biome)
	z:SetAttribute("MinLevel", minL)
	z:SetAttribute("MaxLevel", maxL)
	z:SetAttribute("MaxSpawns", maxSpawns)
	return z
end

local function station(parent, name, cf, color, actionText, objectText)
	local base = anchoredPart({
		Name = name,
		Size = Vector3.new(8, 1, 8),
		CFrame = cf,
		Color = Color3.fromRGB(235, 235, 240),
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	local pillar = anchoredPart({
		Name = "Pillar",
		Size = Vector3.new(3, 6, 3),
		CFrame = cf * CFrame.new(0, 3.5, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Parent = base,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.Parent = pillar
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Parent = pillar
	return base, prompt
end

function WorldBuilder.build()
	local existing = Workspace:FindFirstChild("World")
	if existing then
		return existing
	end

	local world = Instance.new("Folder")
	world.Name = "World"

	-- Terrain: ocean, island, biomes
	terrain:FillBlock(CFrame.new(0, -20, 0), Vector3.new(2400, 30, 2400), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(0, -6, 0), Vector3.new(900, 12, 900), Enum.Material.Sand)
	terrain:FillBlock(CFrame.new(0, -4, 0), Vector3.new(760, 12, 760), Enum.Material.Grass)
	-- Forest (north-west)
	terrain:FillBlock(CFrame.new(-220, -3.5, -220), Vector3.new(300, 12, 300), Enum.Material.LeafyGrass)
	-- Highlands (north-east), stepped plateau
	terrain:FillBlock(CFrame.new(230, 2, -230), Vector3.new(280, 24, 280), Enum.Material.Rock)
	terrain:FillBlock(CFrame.new(240, 10, -240), Vector3.new(180, 20, 180), Enum.Material.Snow)
	-- Plaza ground
	terrain:FillBlock(CFrame.new(0, -2.5, 120), Vector3.new(140, 6, 140), Enum.Material.Pavement)

	local plaza = Instance.new("Folder")
	plaza.Name = "Plaza"
	plaza.Parent = world

	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Name = "PlazaSpawn"
	spawnLoc.Anchored = true
	spawnLoc.Size = Vector3.new(12, 1, 12)
	spawnLoc.CFrame = CFrame.new(0, 1, 120)
	spawnLoc.Color = Color3.fromRGB(255, 200, 80)
	spawnLoc.Material = Enum.Material.Neon
	spawnLoc.Duration = 0
	spawnLoc.Parent = plaza

	-- Central plaza tower (social hub landmark)
	local tower = anchoredPart({
		Name = "PlazaTower",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(60, 10, 10),
		CFrame = CFrame.new(0, 30, 160) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(255, 170, 60),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Parent = plaza,
	})
	local towerLight = Instance.new("PointLight")
	towerLight.Range = 60
	towerLight.Brightness = 2
	towerLight.Color = Color3.fromRGB(255, 200, 120)
	towerLight.Parent = tower

	-- Benches / hangout seating ring
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local pos = Vector3.new(math.cos(a) * 40, 1, 120 + math.sin(a) * 40)
		local seat = Instance.new("Seat")
		seat.Anchored = true
		seat.Size = Vector3.new(6, 1, 2)
		seat.CFrame = CFrame.lookAt(pos, Vector3.new(0, 1, 120))
		seat.Color = Color3.fromRGB(150, 100, 70)
		seat.Material = Enum.Material.Wood
		seat.Parent = plaza
	end

	local _, healPrompt =
		station(plaza, "HealStation", CFrame.new(-30, 0.5, 90), Color3.fromRGB(255, 110, 150), "Heal Party", "Care Fountain")
	healPrompt.Name = "HealPrompt"
	local _, orbPrompt = station(
		plaza,
		"OrbShop",
		CFrame.new(30, 0.5, 90),
		Color3.fromRGB(90, 170, 255),
		"Buy 5 Orbs (" .. Config.OrbPrice * 5 .. "c)",
		"Supply Stand"
	)
	orbPrompt.Name = "OrbPrompt"
	local _, potionPrompt = station(
		plaza,
		"PotionShop",
		CFrame.new(30, 0.5, 70),
		Color3.fromRGB(120, 230, 140),
		"Buy 3 Potions (" .. Config.PotionPrice * 3 .. "c)",
		"Supply Stand"
	)
	potionPrompt.Name = "PotionPrompt"

	-- Trees in the forest (simple stylised)
	local trees = Instance.new("Folder")
	trees.Name = "Trees"
	trees.Parent = world
	local rng = Random.new(42)
	for _ = 1, 70 do
		local x, z = rng:NextNumber(-360, -80), rng:NextNumber(-360, -80)
		local h = rng:NextNumber(14, 26)
		anchoredPart({
			Name = "Trunk",
			Size = Vector3.new(2.5, h, 2.5),
			CFrame = CFrame.new(x, 2 + h / 2, z),
			Color = Color3.fromRGB(110, 80, 55),
			Material = Enum.Material.Wood,
			Parent = trees,
		})
		anchoredPart({
			Name = "Canopy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(10, 16),
			CFrame = CFrame.new(x, 2 + h, z),
			Color = Color3.fromRGB(60, 140, 70),
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = trees,
		})
	end

	local zones = Instance.new("Folder")
	zones.Name = "SpawnZones"
	zones.Parent = world
	zone(zones, "MeadowSouth", CFrame.new(0, 2, 280), Vector3.new(220, 10, 120), "Meadow", 2, 6, 10)
	zone(zones, "MeadowEast", CFrame.new(250, 2, 120), Vector3.new(160, 10, 220), "Meadow", 3, 8, 10)
	zone(zones, "Beach", CFrame.new(0, 2, 410), Vector3.new(600, 10, 50), "Beach", 4, 10, 10)
	zone(zones, "Forest", CFrame.new(-220, 4, -220), Vector3.new(260, 10, 260), "Forest", 8, 16, 14)
	zone(zones, "Highland", CFrame.new(240, 22, -240), Vector3.new(170, 10, 170), "Highland", 14, 24, 12)

	world.Parent = Workspace
	return world
end

return WorldBuilder
]]
local n17 = make("LocalScript", "Client", game:GetService('StarterPlayer'):WaitForChild('StarterPlayerScripts'))
n17.Source = [[
-- Tidewild client entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Renderer = require(script.WorldRenderer)
local Controls = require(script.Controls)
local HUD = require(script.UI.HUD)
local BattleUI = require(script.UI.BattleUI)
local PlazaUI = require(script.UI.PlazaUI)

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

HUD.start()
Renderer.start()
BattleUI.start(HUD.toast)
PlazaUI.start(function()
	return HUD.Profile
end, HUD.toast)

Controls.start({
	toast = HUD.toast,
	onTarget = HUD.setTarget,
})

BattleUI.OnStateChanged = function(inBattle)
	Controls.setEnabled(not inBattle)
	HUD.setVisible(not inBattle)
	if inBattle then
		HUD.setTarget(nil)
	end
end

Net.get("SpawnSnapshot").OnClientEvent:Connect(Renderer.applySnapshot)
]]
local n18 = make("ModuleScript", "Controls", n17)
n18.Source = [[
-- Movement feel + overworld interaction.
--   Shift / L3 / touch button : sprint (wider FOV)
--   E / ButtonX               : battle the targeted creature (your lead hops out)
--   Q / ButtonR2              : throw an Orb at the targeted creature (sneak up from behind for a bonus)
-- Targeting picks the creature closest to the camera's centre line within range, and highlights it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Renderer = require(script.Parent.WorldRenderer)

local LocalPlayer = Players.LocalPlayer

local Controls = {}
Controls.Target = nil :: any
Controls.Enabled = true

local highlight = Instance.new("Highlight")
highlight.FillTransparency = 0.75
highlight.FillColor = Color3.fromRGB(255, 200, 80)
highlight.OutlineColor = Color3.fromRGB(255, 220, 120)
highlight.DepthMode = Enum.HighlightDepthMode.Occluded
highlight.Enabled = false
highlight.Parent = Workspace -- kept here permanently; only Adornee changes, so despawning models never destroy it

local sprinting = false
local function setSprint(on: boolean)
	if sprinting == on then
		return
	end
	sprinting = on
	Net.get("SetSprinting"):FireServer(on)
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = on and Config.SprintSpeed or Config.WalkSpeed -- predict locally for responsiveness
	end
	TweenService:Create(Workspace.CurrentCamera, TweenInfo.new(0.25), { FieldOfView = on and Config.SprintFov or Config.BaseFov }):Play()
end

local function pickTarget()
	local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local cam = Workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	local best, bestScore = nil, math.huge
	for _, w in Renderer.Wild do
		if w.state ~= "Battle" then
			local pos = w.model:GetPivot().Position
			local d = (pos - root.Position).Magnitude
			if d <= Config.ThrowDistance then
				local dir = (pos - cam.CFrame.Position).Unit
				local angle = math.acos(math.clamp(look:Dot(dir), -1, 1))
				if angle < 0.6 then
					local score = angle * 30 + d
					if score < bestScore then
						best, bestScore = w, score
					end
				end
			end
		end
	end
	return best
end

function Controls.start(callbacks)
	ContextActionService:BindAction("TW_Sprint", function(_, state)
		if state == Enum.UserInputState.Begin then
			setSprint(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			setSprint(false)
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("TW_Sprint", "Run")
	ContextActionService:SetPosition("TW_Sprint", UDim2.new(1, -170, 1, -90))

	ContextActionService:BindAction("TW_Battle", function(_, state)
		if state == Enum.UserInputState.Begin and Controls.Enabled and Controls.Target then
			local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			local pos = Controls.Target.model:GetPivot().Position
			if root and (root.Position - pos).Magnitude <= Config.InteractDistance then
				Net.get("EngageCreature"):FireServer(Controls.Target.id)
			elseif callbacks.toast then
				callbacks.toast("Get closer to battle!")
			end
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("TW_Battle", "Battle")
	ContextActionService:SetPosition("TW_Battle", UDim2.new(1, -100, 1, -160))

	ContextActionService:BindAction("TW_Throw", function(_, state)
		if state == Enum.UserInputState.Begin and Controls.Enabled and Controls.Target then
			Net.get("ThrowOrb"):FireServer(Controls.Target.id)
			if callbacks.onThrow then
				callbacks.onThrow(Controls.Target)
			end
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle("TW_Throw", "Orb")
	ContextActionService:SetPosition("TW_Throw", UDim2.new(1, -170, 1, -160))

	LocalPlayer.CharacterAdded:Connect(function()
		sprinting = false
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		local t = Controls.Enabled and pickTarget() or nil
		Controls.Target = t
		if t then
			highlight.Adornee = t.model
			highlight.Enabled = true
		else
			highlight.Adornee = nil
			highlight.Enabled = false
		end
		if callbacks.onTarget then
			callbacks.onTarget(t)
		end
	end)
end

function Controls.setEnabled(on: boolean)
	Controls.Enabled = on
	if not on then
		Controls.Target = nil
		highlight.Adornee = nil
		highlight.Enabled = false
	end
end

return Controls
]]
local n19 = make("Folder", "UI", n17)
local n20 = make("ModuleScript", "BattleUI", n19)
n20.Source = [[
-- Overworld battle UI. The world keeps running around you; this is just an overlay with the
-- command menu, HP cards and a scrolling log that plays server events back with short delays.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)

local Theme = require(script.Parent.Theme)
local Renderer = require(script.Parent.Parent.WorldRenderer)

local BattleUI = {}
BattleUI.Active = false
BattleUI.OnStateChanged = nil :: ((boolean) -> ())?

local gui, root, foeCard, myCard, logLabel, menu
local view, context
local busy = false

local STAT_NAMES = { atk = "Attack", def = "Defense", spa = "Sp. Atk", spd = "Sp. Def", spe = "Speed" }

local function card(parent, pos, anchor)
	local c = Theme.frame({
		Size = UDim2.fromOffset(300, 64),
		Position = pos,
		AnchorPoint = anchor,
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.1,
		Parent = parent,
	})
	Theme.stroke(c, Theme.Accent)
	local name = Theme.label({ Name = "Name", Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 6), Parent = c })
	local back, fill = Theme.bar(c, { Size = UDim2.new(1, -20, 0, 10), Position = UDim2.fromOffset(10, 36) })
	back.Name = "Bar"
	local hp = Theme.label({
		Name = "HP",
		Size = UDim2.new(1, -20, 0, 14),
		Position = UDim2.fromOffset(10, 48),
		TextColor3 = Theme.Muted,
		Parent = c,
		MaxTextSize = 12,
	})
	return { frame = c, name = name, fill = fill, hp = hp }
end

local function setCard(cardRef, data)
	if not data then
		return
	end
	local types = table.concat(data.types or {}, "/")
	cardRef.name.Text = ("%s%s  Lv.%d  ·  %s"):format(data.shiny and "★ " or "", data.name, data.level, types)
	local ratio = data.maxHp > 0 and data.hp / data.maxHp or 0
	TweenService:Create(cardRef.fill, TweenInfo.new(0.4), { Size = UDim2.fromScale(ratio, 1), BackgroundColor3 = Theme.hpColor(ratio) })
		:Play()
	cardRef.hp.Text = ("HP %d / %d"):format(data.hp, data.maxHp)
end

local function myActive()
	return view and view.party[view.active]
end

local function log(text)
	logLabel.Text = text
end

local function act(action)
	if busy or not BattleUI.Active then
		return
	end
	busy = true
	log("…")
	Net.get("BattleAction"):FireServer(action)
end

local showRoot

local function showMoves()
	Theme.clear(menu)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0.33, -6)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.Parent = menu
	local mon = myActive()
	for i, m in mon.moves do
		local b = Theme.button({
			Text = ("%s  %d/%d"):format(m.name, m.pp, m.maxPp),
			BackgroundColor3 = Types.Colors[m.type] or Theme.Accent,
			LayoutOrder = i,
			Parent = menu,
			MaxTextSize = 16,
		}, function()
			act({ type = "move", index = i })
		end)
		b.AutoButtonColor = m.pp > 0
	end
	Theme.button({ Text = "Back", BackgroundColor3 = Theme.Muted, LayoutOrder = 10, Parent = menu }, showRoot)
end

local function showParty()
	Theme.clear(menu)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0.25, -6)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.Parent = menu
	for i, mon in view.party do
		local usable = mon.hp > 0 and i ~= view.active
		Theme.button({
			Text = ("%s Lv.%d  %d/%d"):format(mon.name, mon.level, mon.hp, mon.maxHp),
			BackgroundColor3 = usable and Theme.Accent or Color3.fromRGB(80, 80, 90),
			LayoutOrder = i,
			Parent = menu,
			MaxTextSize = 14,
		}, function()
			if usable then
				act({ type = "switch", slot = i })
			end
		end)
	end
	Theme.button({ Text = "Back", BackgroundColor3 = Theme.Muted, LayoutOrder = 10, Parent = menu }, showRoot)
end

function showRoot()
	Theme.clear(menu)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0.33, -6)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.Parent = menu
	Theme.button({ Text = "Fight", LayoutOrder = 1, Parent = menu }, showMoves)
	Theme.button({ Text = "Party", LayoutOrder = 2, Parent = menu, BackgroundColor3 = Theme.Good }, showParty)
	if view.kind == "wild" then
		Theme.button({ Text = "Throw Orb", LayoutOrder = 3, Parent = menu, BackgroundColor3 = Color3.fromRGB(110, 170, 255) }, function()
			act({ type = "catch" })
		end)
	end
	Theme.button({ Text = "Potion", LayoutOrder = 4, Parent = menu, BackgroundColor3 = Color3.fromRGB(150, 230, 160) }, function()
		act({ type = "item", item = "Potion" })
	end)
	Theme.button(
		{ Text = view.kind == "wild" and "Run" or "Forfeit", LayoutOrder = 5, Parent = menu, BackgroundColor3 = Theme.Bad },
		function()
			act({ type = "run" })
		end
	)
end

local function refreshCards()
	setCard(myCard, myActive())
	setCard(foeCard, view.foe)
end

local function describe(ev): string?
	local t = ev.t
	if t == "move" then
		local s = ("%s used %s!"):format(ev.user, ev.move)
		if ev.miss then
			return s .. " It missed."
		end
		if ev.eff == 0 then
			return s .. " It had no effect…"
		elseif ev.eff and ev.eff > 1 then
			s ..= " It's super effective!"
		elseif ev.eff and ev.eff < 1 then
			s ..= " It's not very effective."
		end
		if ev.crit then
			s ..= " Critical hit!"
		end
		return s
	elseif t == "faint" then
		return ev.name .. " fainted!"
	elseif t == "switch" then
		return (ev.forced and "Go, " or "Come back! Go, ") .. ev.name .. "!"
	elseif t == "catch" then
		return ev.success and ("Gotcha! %s was caught!"):format(ev.name)
			or ({ "Oh no! It broke free!", "Argh! Almost had it!", "So close!" })[ev.shakes + 1]
			or "It broke free!"
	elseif t == "run" then
		return ev.success and "Got away safely!" or "Couldn't get away!"
	elseif t == "stat" then
		if ev.delta == 0 then
			return ev.name .. "'s " .. STAT_NAMES[ev.stat] .. " won't go any further!"
		end
		return ("%s's %s %s!"):format(ev.name, STAT_NAMES[ev.stat], ev.delta > 0 and "rose" or "fell")
	elseif t == "heal" then
		return ("%s restored %d HP%s."):format(ev.name, ev.amount, ev.item and " with a Potion" or "")
	elseif t == "recoil" then
		return ev.name .. " is hurt by recoil!"
	elseif t == "xp" then
		return ("%s gained %d XP."):format(ev.name, ev.amount)
	elseif t == "levelup" then
		return ("%s grew to Lv.%d!"):format(ev.name, ev.level)
	elseif t == "learn" then
		return ("%s learned %s!"):format(ev.name, ev.move)
	elseif t == "evolve" then
		return ("What? %s evolved into %s!"):format(ev.from, ev.to)
	elseif t == "forfeit" then
		return "A trainer forfeited."
	end
	return nil
end

local function playEvents(events, newView)
	local mySide = context and context.side or 1
	for _, ev in events do
		local text = describe(ev)
		if text then
			log(text)
		end
		if ev.t == "move" and ev.damage and ev.damage > 0 then
			if ev.side == mySide then
				view.foe.hp = ev.targetHp
				setCard(foeCard, view.foe)
			else
				local mine = myActive()
				if mine then
					mine.hp = ev.targetHp
					setCard(myCard, mine)
				end
				Renderer.hitFlash(Renderer.BattleModel)
			end
		elseif ev.t == "switch" and ev.side == mySide then
			local mon = view.party[ev.slot]
			if mon then
				Renderer.stageBattle(mon.species, mon.shiny, context and context.foePos)
			end
		end
		if text then
			task.wait(1.1)
		end
	end
	if newView then
		view = newView
		refreshCards()
	end
end

function BattleUI.open(v, ctx)
	view, context = v, ctx or {}
	context.side = context.side or 1 -- server tells us which side of the battle we are
	BattleUI.Active = true
	busy = false
	root.Visible = true
	refreshCards()
	local mon = myActive()
	Renderer.stageBattle(mon and mon.species, mon and mon.shiny, context.foePos)
	log(v.kind == "wild" and ("A wild %s appeared!"):format(v.foe.name) or ("%s wants to battle!"):format(v.foeName))
	showRoot()
	if BattleUI.OnStateChanged then
		BattleUI.OnStateChanged(true)
	end
end

function BattleUI.close()
	BattleUI.Active = false
	root.Visible = false
	Renderer.clearBattle()
	if BattleUI.OnStateChanged then
		BattleUI.OnStateChanged(false)
	end
end

function BattleUI.start(toast)
	gui = Instance.new("ScreenGui")
	gui.Name = "TidewildBattle"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.Parent = gui

	foeCard = card(root, UDim2.new(1, -16, 0, 60), Vector2.new(1, 0))
	myCard = card(root, UDim2.new(0, 16, 1, -250), Vector2.new(0, 0))

	local bottom = Theme.frame({
		Size = UDim2.new(1, -32, 0, 170),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.1,
		Parent = root,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(900, 170)
	limit.Parent = bottom

	logLabel = Theme.label({
		Size = UDim2.new(0.45, -16, 1, -20),
		Position = UDim2.fromOffset(12, 10),
		TextWrapped = true,
		Font = Theme.BodyFont,
		Parent = bottom,
	})
	logLabel.TextYAlignment = Enum.TextYAlignment.Top

	menu = Instance.new("Frame")
	menu.BackgroundTransparency = 1
	menu.Size = UDim2.new(0.55, -12, 1, -20)
	menu.Position = UDim2.new(0.45, 0, 0, 10)
	menu.Parent = bottom

	Net.get("BattleStart").OnClientEvent:Connect(function(v, ctx)
		BattleUI.open(v, ctx)
	end)

	Net.get("BattleEvents").OnClientEvent:Connect(function(events, newView)
		if not BattleUI.Active then
			-- Overworld throw result (no battle open)
			for _, ev in events do
				if ev.t == "catch" and not ev.success and toast then
					toast(({ "Oh no! It broke free!", "Argh! Almost had it!", "So close!" })[ev.shakes + 1] or "It broke free!")
				elseif ev.t == "overworldThrow" and ev.bonus and toast then
					toast("Sneak bonus! It didn't see you coming.")
				end
			end
			return
		end
		task.spawn(function()
			playEvents(events, newView)
			busy = false
			if BattleUI.Active and view and not view.ended then
				showRoot()
			end
		end)
	end)

	Net.get("BattleEnd").OnClientEvent:Connect(function(result)
		task.spawn(function()
			while busy do
				task.wait(0.1)
			end
			task.wait(0.6)
			BattleUI.close()
			if not toast then
				return
			end
			if result.caught then
				toast(("%s joined your %s!"):format(result.caught, result.where == "box" and "box" or "party"), Theme.Good)
			elseif result.won and result.kind == "wild" then
				toast(("Victory! +%d coins"):format(result.money or 0), Theme.Good)
			elseif result.lost then
				toast("You blacked out and hurried back to the plaza…", Theme.Bad)
			elseif result.kind == "pvp" then
				toast(result.won and ("You beat %s!"):format(result.opponent) or ("%s won this time. GG!"):format(result.opponent))
			end
		end)
	end)
end

return BattleUI
]]
local n21 = make("ModuleScript", "HUD", n19)
n21.Source = [=[
-- Always-on HUD: party strip, currencies, target hint, toasts, starter picker.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Creatures)
local Types = require(Shared.Types)
local Net = require(Shared.Net)

local Theme = require(script.Parent.Theme)

local HUD = {}
HUD.Profile = nil

local gui, partyFrame, currency, targetHint, toastHolder, starterFrame

function HUD.toast(text: string, color: Color3?)
	local t = Theme.frame({
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.15,
		Parent = toastHolder,
	})
	Theme.stroke(t, color or Theme.Accent)
	Theme.label({
		Size = UDim2.new(1, -20, 1, -10),
		Position = UDim2.fromOffset(10, 5),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = color or Theme.Text,
		Parent = t,
	})
	task.delay(3.5, function()
		TweenService:Create(t, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		task.wait(0.4)
		t:Destroy()
	end)
end

local function renderParty(profile)
	Theme.clear(partyFrame)
	Theme.list(partyFrame, 6)
	for i, mon in profile.party do
		local card = Theme.frame({
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundColor3 = i == 1 and Color3.fromRGB(60, 54, 40) or Theme.Panel,
			BackgroundTransparency = 0.1,
			LayoutOrder = i,
			Parent = partyFrame,
		})
		local typeColor = Types.Colors[mon.types[1]] or Theme.Accent
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 5, 1, 0)
		stripe.BackgroundColor3 = typeColor
		stripe.BorderSizePixel = 0
		stripe.Parent = card
		Theme.label({
			Size = UDim2.new(1, -90, 0, 20),
			Position = UDim2.fromOffset(12, 4),
			Text = (mon.shiny and "★ " or "") .. mon.name .. "  Lv." .. mon.level,
			Parent = card,
			MaxTextSize = 16,
		})
		local ratio = mon.maxHp > 0 and mon.hp / mon.maxHp or 0
		local _, fill = Theme.bar(card, {
			Size = UDim2.new(1, -100, 0, 8),
			Position = UDim2.fromOffset(12, 30),
			Color = Theme.hpColor(ratio),
		})
		fill.Size = UDim2.fromScale(ratio, 1)
		Theme.label({
			Size = UDim2.new(0, 80, 0, 14),
			Position = UDim2.new(1, -170, 0, 38),
			Text = mon.hp .. "/" .. mon.maxHp,
			TextColor3 = Theme.Muted,
			Parent = card,
			MaxTextSize = 12,
		})
		if i ~= 1 then
			Theme.button(
				{ Size = UDim2.fromOffset(38, 22), Position = UDim2.new(1, -84, 0, 15), Text = "Lead", Parent = card, MaxTextSize = 12 },
				function()
					Net.get("SetLead"):FireServer(i)
				end
			)
		end
		if mon.hp > 0 and mon.hp < mon.maxHp and profile.potions > 0 then
			Theme.button({
				Size = UDim2.fromOffset(38, 22),
				Position = UDim2.new(1, -42, 0, 15),
				Text = "Heal",
				BackgroundColor3 = Theme.Good,
				Parent = card,
				MaxTextSize = 12,
			}, function()
				Net.get("UsePotion"):FireServer(i)
			end)
		end
	end
end

local function showStarterPicker()
	if starterFrame then
		return
	end
	starterFrame = Theme.frame({
		Size = UDim2.fromOffset(560, 300),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Bg,
		Parent = gui,
	})
	Theme.stroke(starterFrame, Theme.Accent, 2)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(560, 300)
	sizeLimit.Parent = starterFrame
	starterFrame.Size = UDim2.new(0.95, 0, 0, 300)
	Theme.label({
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.fromOffset(10, 10),
		Text = "Choose your partner",
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = starterFrame,
		MaxTextSize = 28,
	})
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -20, 1, -70)
	row.Position = UDim2.fromOffset(10, 56)
	row.Parent = starterFrame
	local layout = Theme.list(row, 10, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	for i, id in Creatures.starters() do
		local sp = Creatures.get(id)
		local card = Theme.frame({ Size = UDim2.new(0.31, 0, 1, 0), LayoutOrder = i, Parent = row })
		Theme.stroke(card, Types.Colors[sp.types[1]], 2)
		Theme.label({
			Size = UDim2.new(1, -16, 0, 30),
			Position = UDim2.fromOffset(8, 8),
			Text = sp.name,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = card,
		})
		Theme.label({
			Size = UDim2.new(1, -16, 0, 20),
			Position = UDim2.fromOffset(8, 40),
			Text = sp.types[1],
			TextColor3 = Types.Colors[sp.types[1]],
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = card,
			MaxTextSize = 16,
		})
		local desc = Theme.label({
			Size = UDim2.new(1, -16, 0, 80),
			Position = UDim2.fromOffset(8, 66),
			Text = sp.description,
			Font = Theme.BodyFont,
			TextWrapped = true,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = card,
			MaxTextSize = 14,
		})
		desc.TextYAlignment = Enum.TextYAlignment.Top
		Theme.button({ Size = UDim2.new(1, -16, 0, 34), Position = UDim2.new(0, 8, 1, -42), Text = "Choose", Parent = card }, function()
			Net.get("ChooseStarter"):FireServer(id)
		end)
	end
end

function HUD.setTarget(w)
	if w then
		local sp = Creatures.get(w.species)
		targetHint.Text = ("%s%s Lv.%d   [E] Battle   [Q] Throw Orb"):format(w.shiny and "★ " or "", sp.name, w.level)
		targetHint.Visible = true
	else
		targetHint.Visible = false
	end
end

function HUD.setVisible(on: boolean)
	partyFrame.Visible = on
end

function HUD.start()
	local player = Players.LocalPlayer
	gui = Instance.new("ScreenGui")
	gui.Name = "TidewildHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	partyFrame = Instance.new("Frame")
	partyFrame.Name = "Party"
	partyFrame.BackgroundTransparency = 1
	partyFrame.Size = UDim2.fromOffset(240, 360)
	partyFrame.Position = UDim2.fromOffset(12, 60)
	partyFrame.Parent = gui

	currency = Theme.frame({
		Size = UDim2.fromOffset(300, 34),
		Position = UDim2.new(1, -12, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.2,
		Parent = gui,
	})
	local currencyText = Theme.label({
		Name = "Text",
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = currency,
		MaxTextSize = 16,
	})

	targetHint = Theme.label({
		Size = UDim2.fromOffset(420, 32),
		Position = UDim2.new(0.5, 0, 1, -150),
		AnchorPoint = Vector2.new(0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Visible = false,
		Parent = gui,
	})

	toastHolder = Instance.new("Frame")
	toastHolder.BackgroundTransparency = 1
	toastHolder.Size = UDim2.fromOffset(420, 200)
	toastHolder.Position = UDim2.new(0.5, 0, 0, 60)
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Parent = gui
	Theme.list(toastHolder, 6)

	Net.get("ProfileUpdate").OnClientEvent:Connect(function(profile)
		HUD.Profile = profile
		currencyText.Text = ("◎ %d Orbs   ✚ %d   ¢ %d   ✦ %d PC (Rank %d)"):format(
			profile.orbs,
			profile.potions,
			profile.money,
			profile.plazaCoins,
			profile.plazaRank
		)
		renderParty(profile)
		if profile.needsStarter then
			showStarterPicker()
		elseif starterFrame then
			starterFrame:Destroy()
			starterFrame = nil
		end
	end)
	Net.get("Toast").OnClientEvent:Connect(function(text)
		HUD.toast(text)
	end)
	Net.get("PlazaNotice").OnClientEvent:Connect(function(text)
		HUD.toast(text, Color3.fromRGB(255, 200, 120))
	end)
end

return HUD
]=]
local n22 = make("ModuleScript", "PlazaUI", n19)
n22.Source = [[
-- Social layer: greeting wheel, chat bubbles, player interaction menu (battle / trade invites),
-- incoming request popups and the two-step trade window.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Theme = require(script.Parent.Theme)

local LocalPlayer = Players.LocalPlayer

local PlazaUI = {}

-- Must match PlazaService.Greetings order on the server.
local GREETINGS = {
	"Hello!",
	"Nice to meet you!",
	"Want to battle?",
	"Want to trade?",
	"Thank you!",
	"Good game!",
	"Cool creature!",
	"Let's explore together!",
	"See you later!",
	"I'm hunting shinies!",
}

local gui, greetPanel, playerMenu, requestHolder, tradeWindow
local getProfile

local function showBubble(player: Player, text: string)
	local head = player.Character and player.Character:FindFirstChild("Head")
	if head then
		pcall(function()
			TextChatService:DisplayBubble(head, text)
		end)
	end
end

------------------------------------------------------------------ Greeting wheel
local function buildGreetPanel()
	greetPanel = Theme.frame({
		Size = UDim2.fromOffset(240, 330),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = gui,
	})
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = greetPanel
	Theme.list(greetPanel, 4)
	for i, text in GREETINGS do
		Theme.button({ Size = UDim2.new(1, 0, 0, 27), Text = text, LayoutOrder = i, Parent = greetPanel, MaxTextSize = 14 }, function()
			Net.get("SendGreeting"):FireServer(i)
			greetPanel.Visible = false
		end)
	end
end

------------------------------------------------------------------ Player menu
local function openPlayerMenu(target: Player)
	if playerMenu then
		playerMenu:Destroy()
	end
	playerMenu = Theme.frame({
		Size = UDim2.fromOffset(240, 150),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Bg,
		Parent = gui,
	})
	Theme.stroke(playerMenu, Theme.Accent, 2)
	Theme.label({
		Size = UDim2.new(1, -20, 0, 28),
		Position = UDim2.fromOffset(10, 8),
		Text = ("%s  ·  Rank %d"):format(target.DisplayName, target:GetAttribute("PlazaRank") or 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = playerMenu,
	})
	Theme.button({ Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 42), Text = "Invite to Battle" }, function()
		Net.get("PlazaInvite"):FireServer(target, "battle")
		playerMenu:Destroy()
	end).Parent =
		playerMenu
	Theme.button(
		{ Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 78), Text = "Invite to Trade", BackgroundColor3 = Theme.Good },
		function()
			Net.get("PlazaInvite"):FireServer(target, "trade")
			playerMenu:Destroy()
		end
	).Parent =
		playerMenu
	Theme.button({
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.fromOffset(10, 116),
		Text = "Close",
		BackgroundColor3 = Theme.Muted,
		MaxTextSize = 14,
	}, function()
		playerMenu:Destroy()
	end).Parent =
		playerMenu
end

local function playerFromPart(part: Instance?)
	while part and part ~= Workspace do
		local p = Players:GetPlayerFromCharacter(part)
		if p then
			return p
		end
		part = part.Parent
	end
	return nil
end

------------------------------------------------------------------ Requests
local function showRequest(id, fromName, kind)
	local f = Theme.frame({ Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = Theme.Bg, Parent = requestHolder })
	Theme.stroke(f, Theme.Accent, 2)
	Theme.label({
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 4),
		Text = ("%s wants to %s!"):format(fromName, kind),
		Parent = f,
		MaxTextSize = 16,
	})
	local function respond(ok)
		Net.get("PlazaRespond"):FireServer(id, ok)
		f:Destroy()
	end
	Theme.button(
		{ Size = UDim2.new(0.5, -12, 0, 30), Position = UDim2.new(0, 8, 0, 34), Text = "Accept", BackgroundColor3 = Theme.Good, Parent = f },
		function()
			respond(true)
		end
	)
	Theme.button({
		Size = UDim2.new(0.5, -12, 0, 30),
		Position = UDim2.new(0.5, 4, 0, 34),
		Text = "Decline",
		BackgroundColor3 = Theme.Bad,
		Parent = f,
	}, function()
		respond(false)
	end)
	task.delay(20, function()
		if f.Parent then
			f:Destroy()
		end
	end)
end

------------------------------------------------------------------ Trade window
local function renderTrade(state)
	if tradeWindow then
		tradeWindow:Destroy()
		tradeWindow = nil
	end
	if not state.open then
		return
	end
	tradeWindow = Theme.frame({
		Size = UDim2.fromOffset(520, 340),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Bg,
		Parent = gui,
	})
	Theme.stroke(tradeWindow, Theme.Accent, 2)
	Theme.label({
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 8),
		Text = "Trading with " .. state.partner,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = tradeWindow,
	})

	local function offerText(o)
		return o and ("%s%s Lv.%d"):format(o.shiny and "★ " or "", o.name, o.level) or "(nothing yet)"
	end
	Theme.label({
		Size = UDim2.new(0.5, -15, 0, 24),
		Position = UDim2.fromOffset(10, 44),
		Text = "You offer: " .. offerText(state.myOffer),
		Parent = tradeWindow,
		MaxTextSize = 16,
	})
	Theme.label({
		Size = UDim2.new(0.5, -15, 0, 24),
		Position = UDim2.new(0.5, 5, 0, 44),
		Text = "They offer: " .. offerText(state.theirOffer) .. (state.theirConfirm and "  ✔" or ""),
		Parent = tradeWindow,
		MaxTextSize = 16,
	})

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, -20, 0, 190)
	list.Position = UDim2.fromOffset(10, 76)
	list.Parent = tradeWindow
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0, 54)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.Parent = list
	local profile = getProfile()
	for i, mon in profile and profile.party or {} do
		Theme.button({
			Text = ("%s%s Lv.%d"):format(mon.shiny and "★ " or "", mon.name, mon.level),
			BackgroundColor3 = (state.myOffer and state.myOffer.uid == mon.uid) and Theme.Good or Theme.Panel,
			TextColor3 = Theme.Text,
			LayoutOrder = i,
			Parent = list,
			MaxTextSize = 16,
		}, function()
			Net.get("TradeOffer"):FireServer(i)
		end)
	end

	Theme.button({
		Size = UDim2.new(0.5, -15, 0, 40),
		Position = UDim2.new(0, 10, 1, -50),
		Text = state.myConfirm and "Waiting for partner…" or "Confirm Trade",
		BackgroundColor3 = Theme.Good,
		Parent = tradeWindow,
	}, function()
		Net.get("TradeConfirm"):FireServer()
	end)
	Theme.button({
		Size = UDim2.new(0.5, -15, 0, 40),
		Position = UDim2.new(0.5, 5, 1, -50),
		Text = "Cancel",
		BackgroundColor3 = Theme.Bad,
		Parent = tradeWindow,
	}, function()
		Net.get("TradeCancel"):FireServer()
	end)
end

function PlazaUI.start(profileGetter, toast)
	getProfile = profileGetter
	gui = Instance.new("ScreenGui")
	gui.Name = "TidewildPlaza"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	buildGreetPanel()

	Theme.button({
		Size = UDim2.fromOffset(110, 36),
		Position = UDim2.new(1, -12, 0, 54),
		AnchorPoint = Vector2.new(1, 0),
		Text = "Greet [G]",
		Parent = gui,
	}, function()
		greetPanel.Visible = not greetPanel.Visible
	end)

	requestHolder = Instance.new("Frame")
	requestHolder.BackgroundTransparency = 1
	requestHolder.Size = UDim2.fromOffset(300, 240)
	requestHolder.Position = UDim2.new(1, -12, 0, 100)
	requestHolder.AnchorPoint = Vector2.new(1, 0)
	requestHolder.Parent = gui
	Theme.list(requestHolder, 6)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			greetPanel.Visible = not greetPanel.Visible
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			-- Click / tap another player's avatar to open their interaction menu.
			local cam = Workspace.CurrentCamera
			local ray = cam:ViewportPointToRay(input.Position.X, input.Position.Y)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { LocalPlayer.Character }
			local hit = Workspace:Raycast(ray.Origin, ray.Direction * 120, params)
			local target = hit and playerFromPart(hit.Instance)
			if target and target ~= LocalPlayer then
				openPlayerMenu(target)
			end
		end
	end)

	Net.get("Greeting").OnClientEvent:Connect(function(player, text)
		showBubble(player, text)
	end)
	Net.get("PlazaRequest").OnClientEvent:Connect(showRequest)
	Net.get("TradeUpdate").OnClientEvent:Connect(function(state)
		renderTrade(state)
		if not state.open and state.reason and toast then
			toast(state.reason)
		end
	end)
end

return PlazaUI
]]
local n23 = make("ModuleScript", "Theme", n19)
n23.Source = [[
-- Tiny UI helper library so every screen shares one look.
local Theme = {}

Theme.Font = Enum.Font.GothamBold
Theme.BodyFont = Enum.Font.Gotham
Theme.Bg = Color3.fromRGB(24, 28, 40)
Theme.Panel = Color3.fromRGB(36, 42, 60)
Theme.Accent = Color3.fromRGB(255, 170, 60)
Theme.Text = Color3.fromRGB(245, 245, 250)
Theme.Muted = Color3.fromRGB(170, 175, 195)
Theme.Good = Color3.fromRGB(90, 210, 120)
Theme.Warn = Color3.fromRGB(240, 200, 70)
Theme.Bad = Color3.fromRGB(235, 80, 80)

function Theme.corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = parent
	return c
end

function Theme.stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(1, 1, 1)
	s.Transparency = 0.7
	s.Thickness = thickness or 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Theme.frame(props)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Theme.Panel
	f.BorderSizePixel = 0
	for k, v in props do
		f[k] = v
	end
	Theme.corner(f)
	return f
end

function Theme.label(props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Theme.Font
	l.TextColor3 = Theme.Text
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in props do
		l[k] = v
	end
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = props.MaxTextSize or 22
	c.Parent = l
	return l
end

function Theme.button(props, onClick)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = Theme.Accent
	b.BorderSizePixel = 0
	b.Font = Theme.Font
	b.TextColor3 = Color3.fromRGB(25, 25, 35)
	b.TextScaled = true
	b.AutoButtonColor = true
	local maxSize = props.MaxTextSize or 20
	props.MaxTextSize = nil
	for k, v in props do
		b[k] = v
	end
	Theme.corner(b, 8)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = b
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

function Theme.bar(parent, props)
	local back = Theme.frame({
		Size = props.Size,
		Position = props.Position,
		BackgroundColor3 = Color3.fromRGB(15, 15, 22),
		Parent = parent,
	})
	Theme.corner(back, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = props.Color or Theme.Good
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	Theme.corner(fill, 4)
	return back, fill
end

function Theme.hpColor(ratio: number)
	if ratio > 0.5 then
		return Theme.Good
	elseif ratio > 0.2 then
		return Theme.Warn
	end
	return Theme.Bad
end

function Theme.list(parent, padding, horizontal)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, padding or 6)
	l.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

function Theme.clear(parent)
	for _, c in parent:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

return Theme
]]
local n24 = make("ModuleScript", "WorldRenderer", n17)
n24.Source = [[
-- Client-side rendering of everything creature-related:
--   * wild creatures from server snapshots (interpolated every frame, culled by distance)
--   * every player's lead creature following them around (from replicated attributes)
--   * in-world battle staging (your creature hops out in front of you)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Creatures)
local CreatureModel = require(Shared.CreatureModel)

local LocalPlayer = Players.LocalPlayer

local Renderer = {}
Renderer.Wild = {} :: { [number]: any }
Renderer.Followers = {} :: { [Player]: any }
Renderer.BattleModel = nil :: Model?

local container = Instance.new("Folder")
container.Name = "ClientCreatures"
container.Parent = Workspace

local function headingCf(pos: Vector3, heading: number)
	return CFrame.new(pos) * CFrame.Angles(0, heading, 0)
end

local function makeTag(model: Model, text: string, color: Color3?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromOffset(140, 28)
	gui.StudsOffsetWorldSpace = Vector3.new(0, model:GetExtentsSize().Y + 1, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 60
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.Text = text
	l.Parent = gui
	gui.Adornee = model.PrimaryPart
	gui.Parent = model
	return gui
end

------------------------------------------------------------------ Wild creatures
function Renderer.applySnapshot(list)
	local seen = {}
	for _, row in list do
		local id, species, x, y, z, heading, level, shiny, state = table.unpack(row)
		seen[id] = true
		local w = Renderer.Wild[id]
		local pos = Vector3.new(x, y, z)
		if not w then
			if Creatures.get(species) then
				local model = CreatureModel.build(species, shiny)
				model:PivotTo(headingCf(pos, heading))
				model.Parent = container
				makeTag(model, ("%s  Lv.%d"):format(Creatures.get(species).name, level), shiny and Color3.fromRGB(255, 230, 120) or nil)
				w = {
					id = id,
					species = species,
					model = model,
					from = pos,
					to = pos,
					heading = heading,
					t = 1,
					state = state,
					level = level,
					shiny = shiny,
				}
				Renderer.Wild[id] = w
			end
		else
			w.from = w.model:GetPivot().Position
			w.to = pos
			w.heading = heading
			w.t = 0
			w.state = state
		end
	end
	for id, w in Renderer.Wild do
		if not seen[id] then
			w.model:Destroy()
			Renderer.Wild[id] = nil
		end
	end
end

function Renderer.getWild(id: number)
	return Renderer.Wild[id]
end

------------------------------------------------------------------ Followers
local function rootOf(p: Player)
	return p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end

local function refreshFollower(p: Player)
	local species = p:GetAttribute("LeadSpecies")
	local shiny = p:GetAttribute("LeadShiny")
	local f = Renderer.Followers[p]
	if f and (f.species ~= species or f.shiny ~= shiny) then
		f.model:Destroy()
		Renderer.Followers[p] = nil
		f = nil
	end
	if not f and species and species ~= "" and Creatures.get(species) then
		local model = CreatureModel.build(species, shiny)
		model.Parent = container
		Renderer.Followers[p] = { species = species, shiny = shiny, model = model, pos = nil }
	end
end

local function watchPlayer(p: Player)
	refreshFollower(p)
	p:GetAttributeChangedSignal("LeadSpecies"):Connect(function()
		refreshFollower(p)
	end)
	p:GetAttributeChangedSignal("LeadShiny"):Connect(function()
		refreshFollower(p)
	end)
end

------------------------------------------------------------------ Battle staging
function Renderer.stageBattle(speciesId: string?, shiny: boolean?, foePos: Vector3?)
	Renderer.clearBattle()
	local root = rootOf(LocalPlayer)
	if not root or not speciesId or not Creatures.get(speciesId) then
		return
	end
	local model = CreatureModel.build(speciesId, shiny)
	local target = foePos or (root.Position + root.CFrame.LookVector * 12)
	local mid = root.Position:Lerp(target, 0.45)
	local flat = Vector3.new(target.X, mid.Y, target.Z)
	local cf = CFrame.lookAt(Vector3.new(mid.X, root.Position.Y - 3, mid.Z), Vector3.new(flat.X, root.Position.Y - 3, flat.Z))
	model:PivotTo(cf)
	model.Parent = container
	Renderer.BattleModel = model
	-- Hide own follower during battle so there aren't two copies.
	local f = Renderer.Followers[LocalPlayer]
	if f then
		f.model.Parent = nil
	end
	-- Face the player toward the foe
	if foePos then
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(foePos.X, root.Position.Y, foePos.Z))
	end
end

function Renderer.clearBattle()
	if Renderer.BattleModel then
		Renderer.BattleModel:Destroy()
		Renderer.BattleModel = nil
	end
	local f = Renderer.Followers[LocalPlayer]
	if f then
		f.model.Parent = container
	end
end

function Renderer.hitFlash(model: Model?)
	if not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local h = Instance.new("Highlight")
			h.FillColor = Color3.new(1, 1, 1)
			h.FillTransparency = 0.2
			h.OutlineTransparency = 1
			h.Parent = model
			task.delay(0.15, function()
				h:Destroy()
			end)
			break
		end
	end
end

------------------------------------------------------------------ Frame loop
function Renderer.start()
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(p)
		local f = Renderer.Followers[p]
		if f then
			f.model:Destroy()
			Renderer.Followers[p] = nil
		end
	end)

	local camera = Workspace.CurrentCamera
	local clock = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local camPos = camera.CFrame.Position

		-- Wild: interpolate between 5 Hz server ticks; skip work for far-away models.
		for _, w in Renderer.Wild do
			local dist = (w.to - camPos).Magnitude
			if dist < 260 then
				w.t = math.min(1, w.t + dt / 0.2)
				local pos = w.from:Lerp(w.to, w.t)
				local moving = (w.to - w.from).Magnitude > 0.05
				local bob = moving and math.abs(math.sin(clock * 10 + w.id)) * 0.35 or math.sin(clock * 2 + w.id) * 0.08
				w.model:PivotTo(headingCf(pos + Vector3.new(0, bob, 0), w.heading))
			end
		end

		-- Followers trail ~5 studs behind and to the side of their trainer.
		for p, f in Renderer.Followers do
			local root = rootOf(p)
			if root and f.model.Parent then
				local goal = (root.CFrame * CFrame.new(3.5, -3, 4)).Position
				f.pos = f.pos and f.pos:Lerp(goal, math.min(1, dt * 6)) or goal
				local look = root.Position - f.pos
				local heading = math.atan2(-look.X, -look.Z)
				local speed = root.AssemblyLinearVelocity.Magnitude
				local bob = speed > 1 and math.abs(math.sin(clock * 12)) * 0.4 or 0
				f.model:PivotTo(headingCf(f.pos + Vector3.new(0, bob, 0), heading))
			end
		end

		if Renderer.BattleModel then
			local cf = Renderer.BattleModel:GetPivot()
			Renderer.BattleModel:PivotTo(cf * CFrame.new(0, math.sin(clock * 3) * 0.01, 0))
		end
	end)
end

return Renderer
]]
print('[Tidewild] Installed! Press Play (F5) to start.')
