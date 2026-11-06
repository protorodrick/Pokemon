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
