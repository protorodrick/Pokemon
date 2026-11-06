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
