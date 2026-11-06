-- Visible overworld spawns with temperament-driven AI (no random grass encounters).
-- The server simulates lightweight entities (just tables: position, heading, state) at 5 Hz and sends
-- each client only the creatures near them. Clients build and animate the models locally, so the
-- server never replicates hundreds of moving parts — that's the main performance win.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)
local Factory = require(Shared.CreatureFactory)
local Net = require(Shared.Net)

local SpawnService = {}
SpawnService.Entities = {} :: { [number]: any }
SpawnService.OnTouchBattle = nil :: ((Player, any) -> ())?

local nextId = 0
local rng = Random.new()
local zones = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function groundAt(x: number, z: number, fallbackY: number): number?
	local result = Workspace:Raycast(Vector3.new(x, fallbackY + 80, z), Vector3.new(0, -200, 0), rayParams)
	if result then
		if result.Material == Enum.Material.Water then
			return nil
		end
		return result.Position.Y
	end
	return nil
end

local function pickSpecies(biome: string): string?
	local tbl = Creatures.Biomes[biome]
	if not tbl then
		return nil
	end
	local total = 0
	for _, e in tbl do
		total += e[2]
	end
	local roll = rng:NextNumber(0, total)
	for _, e in tbl do
		roll -= e[2]
		if roll <= 0 then
			return e[1]
		end
	end
	return tbl[1][1]
end

local function randomPointIn(zonePart: BasePart): (number, number)
	local half = zonePart.Size / 2
	local local_ = Vector3.new(rng:NextNumber(-half.X, half.X), 0, rng:NextNumber(-half.Z, half.Z))
	local world = zonePart.CFrame:PointToWorldSpace(local_)
	return world.X, world.Z
end

local function spawnIn(zoneState)
	local part = zoneState.part
	local speciesId = pickSpecies(part:GetAttribute("Biome"))
	if not speciesId then
		return
	end
	local x, z = randomPointIn(part)
	local y = groundAt(x, z, part.Position.Y)
	if not y then
		return
	end
	nextId += 1
	local minL = part:GetAttribute("MinLevel") or 2
	local maxL = part:GetAttribute("MaxLevel") or 5
	local mon = Factory.new(speciesId, rng:NextInteger(minL, maxL), rng)
	local ent = {
		id = nextId,
		mon = mon,
		zone = zoneState,
		pos = Vector3.new(x, y, z),
		heading = rng:NextNumber(0, math.pi * 2),
		state = "Wander",
		target = nil,
		born = os.clock(),
		temperament = Creatures.get(speciesId).temperament,
		inBattle = false,
	}
	SpawnService.Entities[ent.id] = ent
	zoneState.count += 1
end

function SpawnService.remove(id: number)
	local ent = SpawnService.Entities[id]
	if ent then
		SpawnService.Entities[id] = nil
		ent.zone.count -= 1
	end
end

local function nearestPlayer(pos: Vector3, radius: number)
	local best, bestDist = nil, radius
	for _, plr in Players:GetPlayers() do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root and not plr:GetAttribute("InBattle") then
			local d = (root.Position - pos).Magnitude
			if d < bestDist then
				best, bestDist = plr, d
			end
		end
	end
	return best, bestDist
end

local function stepEntity(ent, dt: number)
	if ent.inBattle then
		return
	end
	local plr, dist = nearestPlayer(ent.pos, Config.NoticeRadius)
	local speed = 0
	local temperament = ent.temperament

	if plr then
		local root = plr.Character.HumanoidRootPart
		local toPlayer = (root.Position - ent.pos) * Vector3.new(1, 0, 1)
		local dirAngle = math.atan2(-toPlayer.X, -toPlayer.Z)
		if temperament == "Aggressive" then
			ent.state = "Approach"
			ent.heading = dirAngle
			speed = Config.ChaseSpeed
			if dist <= Config.TouchBattleRadius and SpawnService.OnTouchBattle and os.clock() >= (ent.nextTouch or 0) then
				ent.nextTouch = os.clock() + 5 -- don't retry every tick if the battle can't start
				SpawnService.OnTouchBattle(plr, ent)
				return
			end
		elseif temperament == "Skittish" and (plr:GetAttribute("Sprinting") or dist < 10) then
			ent.state = "Flee"
			ent.heading = dirAngle + math.pi
			speed = Config.FleeSpeed
		elseif temperament == "Curious" then
			ent.state = dist > 9 and "Approach" or "Watch"
			ent.heading = dirAngle
			speed = dist > 9 and Config.WanderSpeed or 0
		else
			ent.state = "Wander"
		end
	else
		ent.state = "Wander"
	end

	if ent.state == "Wander" then
		if rng:NextNumber() < 0.08 then
			ent.heading += rng:NextNumber(-1.2, 1.2)
		end
		speed = rng:NextNumber() < 0.6 and Config.WanderSpeed or 0
	end

	if speed > 0 then
		local dir = Vector3.new(-math.sin(ent.heading), 0, -math.cos(ent.heading))
		local nx, nz = ent.pos.X + dir.X * speed * dt, ent.pos.Z + dir.Z * speed * dt
		-- Stay roughly inside the home zone
		local localP = ent.zone.part.CFrame:PointToObjectSpace(Vector3.new(nx, ent.pos.Y, nz))
		local half = ent.zone.part.Size / 2 + Vector3.new(30, 0, 30)
		if math.abs(localP.X) > half.X or math.abs(localP.Z) > half.Z then
			ent.heading += math.pi
			return
		end
		local y = groundAt(nx, nz, ent.pos.Y)
		if y and math.abs(y - ent.pos.Y) < 6 then
			ent.pos = Vector3.new(nx, y, nz)
		else
			ent.heading += math.pi / 2
		end
	end
end

local function zoneHasPlayerNearby(zoneState): boolean
	for _, plr in Players:GetPlayers() do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - zoneState.part.Position).Magnitude < Config.ZoneActiveRadius + zoneState.part.Size.Magnitude / 2 then
			return true
		end
	end
	return false
end

local function broadcast()
	local snapshotRemote = Net.get("SpawnSnapshot")
	for _, plr in Players:GetPlayers() do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local list = {}
			for id, ent in SpawnService.Entities do
				if (ent.pos - root.Position).Magnitude < Config.SnapshotRadius then
					-- Compact array: { id, species, x, y, z, heading, level, shiny, state }
					table.insert(list, {
						id,
						ent.mon.species,
						math.floor(ent.pos.X * 10) / 10,
						math.floor(ent.pos.Y * 10) / 10,
						math.floor(ent.pos.Z * 10) / 10,
						math.floor(ent.heading * 100) / 100,
						ent.mon.level,
						ent.mon.shiny,
						ent.inBattle and "Battle" or ent.state,
					})
				end
			end
			snapshotRemote:FireClient(plr, list)
		end
	end
end

function SpawnService.start(world: Folder)
	local zoneFolder = world:WaitForChild("SpawnZones")
	local filter = { Workspace.Terrain }
	for _, child in world:GetChildren() do
		if child.Name ~= "SpawnZones" then
			table.insert(filter, child)
		end
	end
	rayParams.FilterDescendantsInstances = filter

	for _, part in zoneFolder:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(zones, { part = part, count = 0 })
		end
	end

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.SpawnTickRate)
			local now = os.clock()
			local dt = now - last
			last = now

			for _, z in zones do
				local active = zoneHasPlayerNearby(z)
				local max = z.part:GetAttribute("MaxSpawns") or 8
				if active and z.count < max and rng:NextNumber() < 0.35 then
					spawnIn(z)
				end
				z.active = active
			end

			for id, ent in SpawnService.Entities do
				if not ent.inBattle and (not ent.zone.active or now - ent.born > Config.DespawnAfter) then
					SpawnService.remove(id)
				else
					stepEntity(ent, dt)
				end
			end

			broadcast()
		end
	end)
end

function SpawnService.distanceTo(player: Player, ent): number
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return math.huge
	end
	return (root.Position - ent.pos).Magnitude
end

-- True if the player is outside the creature's view cone or the creature is wandering away.
function SpawnService.isUnaware(player: Player, ent): boolean
	if ent.state == "Approach" or ent.state == "Watch" or ent.state == "Flee" then
		return false
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local facing = Vector3.new(-math.sin(ent.heading), 0, -math.cos(ent.heading))
	local toPlayer = ((root.Position - ent.pos) * Vector3.new(1, 0, 1)).Unit
	return facing:Dot(toPlayer) < 0.3
end

return SpawnService
