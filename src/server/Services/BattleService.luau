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
