-- Generates a playable starter island (terrain, plaza hub, heal station, shop, spawn zones) the first
-- time the place runs. If Workspace already contains a folder named "World" (e.g. you built your own
-- map in Studio), nothing is generated and your map's SpawnZones are used instead.
--
-- Spawn zone contract (for custom maps): Workspace.World.SpawnZones contains anchored, invisible
-- Parts with attributes Biome (string, key of Creatures.Biomes), MinLevel, MaxLevel, MaxSpawns.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local WorldBuilder = {}

local terrain = Workspace.Terrain

local function anchoredPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	return p
end

local function zone(parent, name, cf, size, biome, minL, maxL, maxSpawns)
	local z = anchoredPart({
		Name = name,
		CFrame = cf,
		Size = size,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = parent,
	})
	z:SetAttribute("Biome", biome)
	z:SetAttribute("MinLevel", minL)
	z:SetAttribute("MaxLevel", maxL)
	z:SetAttribute("MaxSpawns", maxSpawns)
	return z
end

local function station(parent, name, cf, color, actionText, objectText)
	local base = anchoredPart({
		Name = name,
		Size = Vector3.new(8, 1, 8),
		CFrame = cf,
		Color = Color3.fromRGB(235, 235, 240),
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	local pillar = anchoredPart({
		Name = "Pillar",
		Size = Vector3.new(3, 6, 3),
		CFrame = cf * CFrame.new(0, 3.5, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Parent = base,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.Parent = pillar
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Parent = pillar
	return base, prompt
end

function WorldBuilder.build()
	local existing = Workspace:FindFirstChild("World")
	if existing then
		return existing
	end

	local world = Instance.new("Folder")
	world.Name = "World"

	-- Terrain: ocean, island, biomes
	terrain:FillBlock(CFrame.new(0, -20, 0), Vector3.new(2400, 30, 2400), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(0, -6, 0), Vector3.new(900, 12, 900), Enum.Material.Sand)
	terrain:FillBlock(CFrame.new(0, -4, 0), Vector3.new(760, 12, 760), Enum.Material.Grass)
	-- Forest (north-west)
	terrain:FillBlock(CFrame.new(-220, -3.5, -220), Vector3.new(300, 12, 300), Enum.Material.LeafyGrass)
	-- Highlands (north-east), stepped plateau
	terrain:FillBlock(CFrame.new(230, 2, -230), Vector3.new(280, 24, 280), Enum.Material.Rock)
	terrain:FillBlock(CFrame.new(240, 10, -240), Vector3.new(180, 20, 180), Enum.Material.Snow)
	-- Plaza ground
	terrain:FillBlock(CFrame.new(0, -2.5, 120), Vector3.new(140, 6, 140), Enum.Material.Pavement)

	local plaza = Instance.new("Folder")
	plaza.Name = "Plaza"
	plaza.Parent = world

	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Name = "PlazaSpawn"
	spawnLoc.Anchored = true
	spawnLoc.Size = Vector3.new(12, 1, 12)
	spawnLoc.CFrame = CFrame.new(0, 1, 120)
	spawnLoc.Color = Color3.fromRGB(255, 200, 80)
	spawnLoc.Material = Enum.Material.Neon
	spawnLoc.Duration = 0
	spawnLoc.Parent = plaza

	-- Central plaza tower (social hub landmark)
	local tower = anchoredPart({
		Name = "PlazaTower",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(60, 10, 10),
		CFrame = CFrame.new(0, 30, 160) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(255, 170, 60),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Parent = plaza,
	})
	local towerLight = Instance.new("PointLight")
	towerLight.Range = 60
	towerLight.Brightness = 2
	towerLight.Color = Color3.fromRGB(255, 200, 120)
	towerLight.Parent = tower

	-- Benches / hangout seating ring
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local pos = Vector3.new(math.cos(a) * 40, 1, 120 + math.sin(a) * 40)
		local seat = Instance.new("Seat")
		seat.Anchored = true
		seat.Size = Vector3.new(6, 1, 2)
		seat.CFrame = CFrame.lookAt(pos, Vector3.new(0, 1, 120))
		seat.Color = Color3.fromRGB(150, 100, 70)
		seat.Material = Enum.Material.Wood
		seat.Parent = plaza
	end

	local _, healPrompt =
		station(plaza, "HealStation", CFrame.new(-30, 0.5, 90), Color3.fromRGB(255, 110, 150), "Heal Party", "Care Fountain")
	healPrompt.Name = "HealPrompt"
	local _, orbPrompt = station(
		plaza,
		"OrbShop",
		CFrame.new(30, 0.5, 90),
		Color3.fromRGB(90, 170, 255),
		"Buy 5 Orbs (" .. Config.OrbPrice * 5 .. "c)",
		"Supply Stand"
	)
	orbPrompt.Name = "OrbPrompt"
	local _, potionPrompt = station(
		plaza,
		"PotionShop",
		CFrame.new(30, 0.5, 70),
		Color3.fromRGB(120, 230, 140),
		"Buy 3 Potions (" .. Config.PotionPrice * 3 .. "c)",
		"Supply Stand"
	)
	potionPrompt.Name = "PotionPrompt"

	-- Trees in the forest (simple stylised)
	local trees = Instance.new("Folder")
	trees.Name = "Trees"
	trees.Parent = world
	local rng = Random.new(42)
	for _ = 1, 70 do
		local x, z = rng:NextNumber(-360, -80), rng:NextNumber(-360, -80)
		local h = rng:NextNumber(14, 26)
		anchoredPart({
			Name = "Trunk",
			Size = Vector3.new(2.5, h, 2.5),
			CFrame = CFrame.new(x, 2 + h / 2, z),
			Color = Color3.fromRGB(110, 80, 55),
			Material = Enum.Material.Wood,
			Parent = trees,
		})
		anchoredPart({
			Name = "Canopy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(10, 16),
			CFrame = CFrame.new(x, 2 + h, z),
			Color = Color3.fromRGB(60, 140, 70),
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = trees,
		})
	end

	local zones = Instance.new("Folder")
	zones.Name = "SpawnZones"
	zones.Parent = world
	zone(zones, "MeadowSouth", CFrame.new(0, 2, 280), Vector3.new(220, 10, 120), "Meadow", 2, 6, 10)
	zone(zones, "MeadowEast", CFrame.new(250, 2, 120), Vector3.new(160, 10, 220), "Meadow", 3, 8, 10)
	zone(zones, "Beach", CFrame.new(0, 2, 410), Vector3.new(600, 10, 50), "Beach", 4, 10, 10)
	zone(zones, "Forest", CFrame.new(-220, 4, -220), Vector3.new(260, 10, 260), "Forest", 8, 16, 14)
	zone(zones, "Highland", CFrame.new(240, 22, -240), Vector3.new(170, 10, 170), "Highland", 14, 24, 12)

	world.Parent = Workspace
	return world
end

return WorldBuilder
