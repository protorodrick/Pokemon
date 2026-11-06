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
