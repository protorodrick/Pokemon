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
