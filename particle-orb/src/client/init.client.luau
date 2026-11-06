-- Particle Orb client: a line-for-line port of the three.js scene's initScene / createParticles /
-- animate loop. three.js units = studs, and both engines are right-handed with Y up and the camera
-- looking down -Z, so coordinates carry over unchanged (offset to OrbCenter).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Geometry = require(script:WaitForChild("Geometry"))
local Fly = require(script:WaitForChild("Fly"))

local LocalPlayer = Players.LocalPlayer

local function attr(name, default)
	local v = Workspace:GetAttribute(name)
	while v == nil do
		Workspace:GetAttributeChangedSignal(name):Wait()
		v = Workspace:GetAttribute(name)
	end
	return v or default
end

local CENTER: Vector3 = attr("OrbCenter", Vector3.new(0, 300, 0))
local SEED: number = attr("ParticleSeed", 1)
local EPOCH: number = attr("OrbEpoch", 0)

local particleCount = 1000
local CAMERA_FOV = 75 -- PerspectiveCamera(75, ...) — vertical FOV, same as Roblox's FieldOfView
local CAMERA_OFFSET = Vector3.new(0, 0, 300) -- camera.position.z = 300

local scene = Instance.new("Folder")
scene.Name = "OrbScene"
scene.Parent = Workspace

-- Shared clock: everyone's animation is in sync (THREE.Clock started when the server did).
local function elapsed(): number
	return Workspace:GetServerTimeNow() - EPOCH
end

------------------------------------------------------------------ initScene()
local WHITE = Color3.new(1, 1, 1)
-- SphereGeometry(30, 32, 32), wireframe
local centralOrb = Geometry.newWire("CentralOrb", scene, Geometry.sphereEdges(30, 32, 32), Geometry.sphereEdges(30, 12, 10), WHITE)
-- TorusGeometry(45, 1.5, 16, 100), wireframe
local wireframeRing =
	Geometry.newWire("WireframeRing", scene, Geometry.torusEdges(45, 1.5, 16, 100), Geometry.torusEdges(45, 1.5, 6, 48), WHITE)

------------------------------------------------------------------ createParticles()
-- Seeded so every player gets the same field (Math.random() differs per browser tab).
local rng = Random.new(SEED)
local positions = table.create(particleCount * 3)
local parts = table.create(particleCount)
local cframes = table.create(particleCount)

local particleFolder = Instance.new("Folder")
particleFolder.Name = "ParticleSystem"

for i = 0, particleCount - 1 do
	local x = rng:NextNumber() * 500 - 250
	local y = rng:NextNumber() * 500 - 250
	local z = rng:NextNumber() * 500 - 250
	positions[i * 3 + 1], positions[i * 3 + 2], positions[i * 3 + 3] = x, y, z

	local p = Instance.new("Part")
	p.Name = "P"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon -- unlit-looking, like PointsMaterial
	p.Size = Vector3.new(2, 2, 2) -- PointsMaterial({ size: 2 })
	p.Color = Color3.new(x / 500 + 0.5, y / 500 + 0.5, z / 500 + 0.5)
	p.CFrame = CFrame.new(CENTER + Vector3.new(x, y, z))
	p.Parent = particleFolder
	parts[i + 1] = p
end
particleFolder.Parent = scene

------------------------------------------------------------------ helpers
-- JavaScript's % keeps the sign of the dividend, exactly like math.fmod.
local function channel(v: number): number
	return math.clamp(math.fmod(v, 1), 0, 1) -- WebGL clamps negative colour channels to 0
end

------------------------------------------------------------------ animate()
local orbRotX, orbRotY = 0, 0
local ringRotX, ringRotY = 0, 0
local centerCf = CFrame.new(CENTER)

RunService.RenderStepped:Connect(function(dt)
	local elapsedTime = elapsed()
	-- The original adds a fixed amount per frame at ~60 fps; scale by dt so it matches at any frame rate.
	local frames = dt * 60

	-- particleSystem.rotation.y = elapsedTime * 0.05
	local systemCf = centerCf * CFrame.Angles(0, elapsedTime * 0.05, 0)

	-- centralOrb.rotation.x/y += 0.01 ; color.setHSL(t * 0.1 % 1, 1, 0.5)  (HSL l=0.5,s=1 == HSV v=1,s=1)
	orbRotX += 0.01 * frames
	orbRotY += 0.01 * frames
	centralOrb:setCFrame(centerCf * CFrame.Angles(orbRotX, orbRotY, 0)) -- three.js Euler 'XYZ' == CFrame.Angles order
	centralOrb:setColor(Color3.fromHSV((elapsedTime * 0.1) % 1, 1, 1))

	-- wireframeRing.rotation.x += 0.005 ; rotation.y += 0.01
	ringRotX += 0.005 * frames
	ringRotY += 0.01 * frames
	wireframeRing:setCFrame(centerCf * CFrame.Angles(ringRotX, ringRotY, 0))

	-- Update particle positions (group rotation) and colours (position + time)
	for i = 0, particleCount - 1 do
		local index = i * 3
		local x, y, z = positions[index + 1], positions[index + 2], positions[index + 3]
		cframes[i + 1] = systemCf * CFrame.new(x, y, z)
		local vx = (x / 500) + 0.5 + math.sin(elapsedTime + i * 0.1) * 0.5
		local vy = (y / 500) + 0.5 + math.cos(elapsedTime + i * 0.1) * 0.5
		local vz = (z / 500) + 0.5
		parts[i + 1].Color = Color3.new(channel(vx), channel(vy), channel(vz))
	end
	Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end)

------------------------------------------------------------------ Interaction: original camera + fly
local camera = Workspace.CurrentCamera
local originalView = false

local function setOriginalView(on: boolean)
	originalView = on
	camera = Workspace.CurrentCamera
	if on then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = CAMERA_FOV
		camera.CFrame = CFrame.lookAt(CENTER + CAMERA_OFFSET, CENTER)
	else
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
		end
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "OrbControls"
gui.ResetOnSpawn = false
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local function button(text, pos, onClick)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(170, 38)
	b.Position = pos
	b.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	b.BackgroundTransparency = 0.2
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.Text = text
	b.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(1, 1, 1)
	s.Transparency = 0.6
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local flyBtn, viewBtn
local function refreshLabels()
	flyBtn.Text = Fly.Flying and "Stop Flying [F]" or "Fly [F]"
	viewBtn.Text = originalView and "Explore View [V]" or "Original View [V]"
end

flyBtn = button("Fly [F]", UDim2.new(0, 16, 1, -100), function()
	Fly.toggle()
	refreshLabels()
end)
viewBtn = button("Original View [V]", UDim2.new(0, 16, 1, -54), function()
	setOriginalView(not originalView)
	refreshLabels()
end)

-- Touch: hold-to-rise / hold-to-sink while flying.
if UserInputService.TouchEnabled then
	local function holdButton(text, pos, dir)
		local b = button(text, pos)
		b.Size = UDim2.fromOffset(60, 60)
		b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				Fly.Vertical = dir
			end
		end)
		b.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				Fly.Vertical = 0
			end
		end)
	end
	holdButton("▲", UDim2.new(1, -90, 1, -230), 1)
	holdButton("▼", UDim2.new(1, -90, 1, -160), -1)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		Fly.toggle()
		refreshLabels()
	elseif input.KeyCode == Enum.KeyCode.V then
		setOriginalView(not originalView)
		refreshLabels()
	end
end)

LocalPlayer.CharacterAdded:Connect(function()
	task.defer(function()
		if originalView then
			setOriginalView(true)
		end
		refreshLabels()
	end)
end)
