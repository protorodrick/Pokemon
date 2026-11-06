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
