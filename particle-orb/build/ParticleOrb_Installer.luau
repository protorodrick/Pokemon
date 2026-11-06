-- ParticleOrb one-paste installer. Paste ALL of this into Roblox Studio's Command Bar
-- (View > Command Bar) and press Enter. Re-running replaces the previous install.
local function make(cls, name, parent)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == cls and cls == 'Folder' then return existing end
	if existing then existing:Destroy() end
	local i = Instance.new(cls)
	i.Name = name
	i.Parent = parent
	return i
end
local base = workspace:FindFirstChild('Baseplate'); if base then base:Destroy() end
local n1 = make("Script", "OrbServer", game:GetService('ServerScriptService'))
n1.Source = [[
-- Particle Orb server: sets up the black void, the spawn platform and the shared clock.
-- The orb, ring and particles are drawn by each client (like the browser's render loop), using the
-- same random seed and server time, so every player sees exactly the same scene.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

-- Scene centre (three.js origin). Lifted into the sky so the 500-stud particle cube fits above the void.
local CENTER = Vector3.new(0, 300, 0)
-- three.js camera sat at z = 300 looking toward the origin; players spawn there.
local SPAWN_POS = CENTER + Vector3.new(0, -6, 300)

Workspace:SetAttribute("OrbCenter", CENTER)
Workspace:SetAttribute("ParticleSeed", 20250101)
Workspace:SetAttribute("OrbEpoch", Workspace:GetServerTimeNow())

-- Black background like the default WebGL clear colour.
local baseplate = Workspace:FindFirstChild("Baseplate")
if baseplate then
	baseplate:Destroy()
end
for _, child in Lighting:GetChildren() do
	if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("PostEffect") or child:IsA("Clouds") then
		child:Destroy()
	end
end
local sky = Instance.new("Sky")
sky.StarCount = 0
sky.CelestialBodiesShown = false
sky.Parent = Lighting -- midnight + no stars/moon = near-black sky
Lighting.ClockTime = 0
Lighting.Brightness = 0
Lighting.Ambient = Color3.new(0, 0, 0)
Lighting.OutdoorAmbient = Color3.fromRGB(20, 20, 26)
Lighting.EnvironmentDiffuseScale = 0
Lighting.EnvironmentSpecularScale = 0
Lighting.GlobalShadows = false
Lighting.FogEnd = 100000
pcall(function()
	Workspace.Terrain:Clear()
end)

local world = Instance.new("Folder")
world.Name = "OrbWorld"
world.Parent = Workspace

local platform = Instance.new("Part")
platform.Name = "ViewingPlatform"
platform.Anchored = true
platform.Size = Vector3.new(40, 1, 40)
platform.CFrame = CFrame.new(SPAWN_POS - Vector3.new(0, 0.5, 0))
platform.Material = Enum.Material.Glass
platform.Transparency = 0.6
platform.Color = Color3.fromRGB(40, 40, 50)
platform.Parent = world

local edge = Instance.new("SelectionBox")
edge.Adornee = platform
edge.LineThickness = 0.05
edge.Color3 = Color3.fromRGB(255, 255, 255)
edge.SurfaceTransparency = 1
edge.Parent = platform

local spawn = Instance.new("SpawnLocation")
spawn.Name = "Spawn"
spawn.Anchored = true
spawn.Size = Vector3.new(6, 0.2, 6)
spawn.CFrame = CFrame.lookAt(SPAWN_POS + Vector3.new(0, 0.1, 0), CENTER * Vector3.new(1, 0, 1) + Vector3.new(0, SPAWN_POS.Y, 0))
spawn.Transparency = 1
spawn.CanCollide = false
spawn.Duration = 0
spawn.Neutral = true
spawn.Parent = world

-- Safety net: anyone who falls into the void is put back on the platform instead of dying.
local net = Instance.new("Part")
net.Name = "VoidNet"
net.Anchored = true
net.Size = Vector3.new(4000, 4, 4000)
net.CFrame = CFrame.new(0, -40, 0)
net.Transparency = 1
net.CanCollide = false
net.Parent = world
net.Touched:Connect(function(hit)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if player then
		character:PivotTo(CFrame.lookAt(SPAWN_POS + Vector3.new(0, 4, 0), CENTER))
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end)

print("[ParticleOrb] server ready")
]]
local n2 = make("LocalScript", "OrbClient", game:GetService('StarterPlayer'):WaitForChild('StarterPlayerScripts'))
n2.Source = [[
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
]]
local n3 = make("ModuleScript", "Fly", n2)
n3.Source = [[
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
]]
local n4 = make("ModuleScript", "Geometry", n2)
n4.Source = [[
-- Rebuilds three.js r128 SphereGeometry / TorusGeometry vertex + index layouts, then turns their
-- triangles into unique edges so the wireframe looks the same as `wireframe: true`.
-- Wireframes are drawn with a WireframeHandleAdornment (thousands of lines, one instance). If that
-- class isn't available, it falls back to thin Neon parts at lower resolution.
local Workspace = game:GetService("Workspace")

local Geometry = {}

local function edgesFromTriangles(vertices, indices)
	local seen, edges = {}, {}
	local function add(a, b)
		if a > b then
			a, b = b, a
		end
		local key = a * 1000003 + b
		if not seen[key] then
			seen[key] = true
			table.insert(edges, { vertices[a], vertices[b] })
		end
	end
	for i = 1, #indices, 3 do
		local a, b, c = indices[i], indices[i + 1], indices[i + 2]
		add(a, b)
		add(b, c)
		add(c, a)
	end
	return edges
end

-- THREE.SphereGeometry(radius, widthSegments, heightSegments)
function Geometry.sphereEdges(radius, widthSegments, heightSegments)
	local vertices, grid, indices = {}, {}, {}
	local index = 0
	for iy = 0, heightSegments do
		local row = {}
		local v = iy / heightSegments
		for ix = 0, widthSegments do
			local u = ix / widthSegments
			local x = -radius * math.cos(u * math.pi * 2) * math.sin(v * math.pi)
			local y = radius * math.cos(v * math.pi)
			local z = radius * math.sin(u * math.pi * 2) * math.sin(v * math.pi)
			index += 1
			vertices[index] = Vector3.new(x, y, z)
			row[ix] = index
		end
		grid[iy] = row
	end
	for iy = 0, heightSegments - 1 do
		for ix = 0, widthSegments - 1 do
			local a = grid[iy][ix + 1]
			local b = grid[iy][ix]
			local c = grid[iy + 1][ix]
			local d = grid[iy + 1][ix + 1]
			if iy ~= 0 then
				table.insert(indices, a)
				table.insert(indices, b)
				table.insert(indices, d)
			end
			if iy ~= heightSegments - 1 then
				table.insert(indices, b)
				table.insert(indices, c)
				table.insert(indices, d)
			end
		end
	end
	return edgesFromTriangles(vertices, indices)
end

-- THREE.TorusGeometry(radius, tube, radialSegments, tubularSegments) — lies in the XY plane.
function Geometry.torusEdges(radius, tube, radialSegments, tubularSegments)
	local vertices, indices = {}, {}
	local function id(j, i)
		return (tubularSegments + 1) * j + i + 1
	end
	for j = 0, radialSegments do
		for i = 0, tubularSegments do
			local u = i / tubularSegments * math.pi * 2
			local v = j / radialSegments * math.pi * 2
			vertices[id(j, i)] =
				Vector3.new((radius + tube * math.cos(v)) * math.cos(u), (radius + tube * math.cos(v)) * math.sin(u), tube * math.sin(v))
		end
	end
	for j = 1, radialSegments do
		for i = 1, tubularSegments do
			local a, b, c, d = id(j, i - 1), id(j - 1, i - 1), id(j - 1, i), id(j, i)
			for _, n in { a, b, d, b, c, d } do
				table.insert(indices, n)
			end
		end
	end
	return edgesFromTriangles(vertices, indices)
end

------------------------------------------------------------------ Wire objects
local Wire = {}
Wire.__index = Wire

local function newAnchor(name, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.Parent = parent
	return p
end

-- edges: full-detail edge list; fallbackEdges: lower-detail list used only if adornments are unavailable.
function Geometry.newWire(name, parent, edges, fallbackEdges, color)
	local self = setmetatable({ color = color }, Wire)
	self.anchor = newAnchor(name, parent)

	local ok = pcall(function()
		local adorn = Instance.new("WireframeHandleAdornment")
		adorn.Name = name .. "Lines"
		adorn.Adornee = self.anchor
		adorn.Color3 = color
		adorn.Thickness = 1
		adorn.AlwaysOnTop = false
		local points = table.create(#edges * 2)
		for _, e in edges do
			table.insert(points, e[1])
			table.insert(points, e[2])
		end
		adorn:AddLines(points)
		adorn.Parent = self.anchor
		self.adorn = adorn
	end)

	if not ok then
		-- Fallback: one thin neon part per edge, moved together with BulkMoveTo.
		self.parts, self.offsets, self.cframes = {}, {}, {}
		for i, e in fallbackEdges do
			local a, b = e[1], e[2]
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.Neon
			p.Color = color
			p.Size = Vector3.new(0.12, 0.12, (b - a).Magnitude)
			p.Parent = self.anchor
			self.parts[i] = p
			self.offsets[i] = CFrame.lookAt((a + b) / 2, b)
		end
	end
	return self
end

function Wire:setCFrame(cf: CFrame)
	self.anchor.CFrame = cf
	if self.parts then
		for i, off in self.offsets do
			self.cframes[i] = cf * off
		end
		Workspace:BulkMoveTo(self.parts, self.cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Wire:setColor(color: Color3)
	if color == self.color then
		return
	end
	self.color = color
	if self.adorn then
		self.adorn.Color3 = color
	else
		for _, p in self.parts do
			p.Color = color
		end
	end
end

return Geometry
]]
pcall(function() game:GetService('Lighting').ClockTime = 0 end)
pcall(function() game:GetService('Lighting').Brightness = 0 end)
pcall(function() game:GetService('Lighting').GlobalShadows = false end)
pcall(function() game:GetService('Lighting').Ambient = Color3.new(0, 0, 0) end)
pcall(function() game:GetService('Lighting').OutdoorAmbient = Color3.new(0.08, 0.08, 0.1) end)
pcall(function() game:GetService('Lighting').Technology = Enum.Technology.Future end)
print('[ParticleOrb] Installed! Press Play (F5) to start.')
