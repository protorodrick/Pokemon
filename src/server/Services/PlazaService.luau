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
