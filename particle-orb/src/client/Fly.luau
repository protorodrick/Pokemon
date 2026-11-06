-- Simple free-flight so players can fly into the particle field and around the orb.
-- Move with WASD / thumbstick, Space or E to rise, Ctrl or Q to sink.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Fly = {}
Fly.Flying = false
Fly.Speed = 60
Fly.Vertical = 0 -- set by touch buttons (-1, 0, 1)

local attachment, velocity, align, conn

local function stop()
	Fly.Flying = false
	if conn then
		conn:Disconnect()
		conn = nil
	end
	for _, inst in { velocity, align, attachment } do
		if inst then
			inst:Destroy()
		end
	end
	velocity, align, attachment = nil, nil, nil
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function start()
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return
	end
	Fly.Flying = true
	attachment = Instance.new("Attachment")
	attachment.Name = "FlyAttachment"
	attachment.Parent = root

	velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = math.huge
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root

	align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = math.huge
	align.Responsiveness = 30
	align.CFrame = root.CFrame.Rotation
	align.Parent = root

	hum.PlatformStand = true

	conn = RunService.RenderStepped:Connect(function()
		if not hum.Parent or hum.Health <= 0 then
			stop()
			return
		end
		local cam = Workspace.CurrentCamera
		local up = Fly.Vertical
		if not UserInputService:GetFocusedTextBox() then
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then
				up += 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
				up -= 1
			end
		end
		-- MoveDirection is already camera-relative; tilt it with the camera pitch for true 3D flight.
		local move = hum.MoveDirection
		if move.Magnitude > 0 then
			local look = cam.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude > 1e-3 then
				local forwardAmount = move:Dot(flatLook.Unit)
				move = move + Vector3.new(0, look.Y * forwardAmount, 0)
			end
		end
		velocity.VectorVelocity = (move + Vector3.new(0, math.clamp(up, -1, 1), 0)) * Fly.Speed
		local facing = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		if facing.Magnitude > 1e-3 then
			align.CFrame = CFrame.lookAt(Vector3.zero, facing)
		end
	end)
end

function Fly.toggle()
	if Fly.Flying then
		stop()
	else
		start()
	end
	return Fly.Flying
end

LocalPlayer.CharacterAdded:Connect(function()
	if Fly.Flying then
		stop()
	end
end)

return Fly
