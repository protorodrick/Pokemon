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
