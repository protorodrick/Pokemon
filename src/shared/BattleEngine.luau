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
