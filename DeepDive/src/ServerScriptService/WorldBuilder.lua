--[[
	WorldBuilder  (ModuleScript)
	LOCATION: ServerScriptService > WorldBuilder

	Builds the map with code when the server starts:

	  THE WELL - a giant round shaft that drops 600 m straight down.
	    0-200 m    Sunlit Reef: bright limestone walls, coral, sponges, kelp
	               on rock ledges, light rays from the surface
	    ~200 m     the Lip: the shaft narrows, a wrecked research sub rests here
	    200-600 m  Twilight Drop: dark slate and basalt, glowing crystals,
	               hidden side caves
	    ~600 m     the bottom: silt floor, whale skeleton, bubbling vents and
	               the sealed door to the Midnight Trench (future update)
	    Depth-marker lights ring the wall every 50 m.

	  HARBOR TOWN on top: a round boardwalk dock with 8 berths, salvage shop,
	  warehouses, shipping containers, a crane, lamp posts, palm trees and a
	  lighthouse, on an island in the open sea.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("DeepDiveConfig"))

local S = Config.SURFACE_Y
local WorldBuilder = {}

local rng = Random.new(1337) -- fixed seed = same map every server
local TAU = math.pi * 2

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function lerp(a, b, t)
	return a + (b - a) * t
end

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "Mesh" and k ~= "Sway" then
			p[k] = v
		end
	end
	if props.Mesh then
		-- SpecialMesh sphere = smooth rounded shape instead of a box
		local m = Instance.new("SpecialMesh")
		m.MeshType = props.Mesh
		m.Parent = p
	end
	if props.Sway then
		p:SetAttribute("Sway", props.Sway) -- clients gently sway these (kelp, sea fans)
	end
	p.Parent = props.Parent
	return p
end

-- Decorations: no collisions, no raycasts, no shadows (cheap for phones).
local function deco(props)
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	if props.CastShadow == nil then
		props.CastShadow = false
	end
	return part(props)
end

local SPHERE = Enum.MeshType.Sphere

local function light(parent, range, brightness, color, shadows)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = color
	l.Shadows = shadows == true
	l.Parent = parent
	return l
end

local function surfaceText(parent, face, text, textColor, size)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = size or 40
	gui.LightInfluence = 0
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = textColor or Color3.new(1, 1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	return label, gui
end

-- A frame at radius r / angle theta: local X points OUT from the centre,
-- local Z runs along the circle, so "-X" faces the middle of the Well.
local function radial(r, theta, y)
	return CFrame.new(math.cos(theta) * r, y, math.sin(theta) * r) * CFrame.Angles(0, -theta, 0)
end

local function angleDiff(a, b)
	local d = (a - b) % TAU
	if d > math.pi then
		d = TAU - d
	end
	return d
end

------------------------------------------------------------------------
-- Shape of the Well
------------------------------------------------------------------------
local FLOOR_DEPTH = 606

function WorldBuilder.ShaftRadius(depth)
	if depth < 0 then
		return 132
	elseif depth < 30 then
		return lerp(132, 106, smooth(depth / 30))
	elseif depth < 200 then
		return 106
	elseif depth < 216 then
		return lerp(106, 82, smooth((depth - 200) / 16))
	end
	return 82
end

local CAVES = {
	{ Angle = 3.3, Depth = 140 },
	{ Angle = 0.6, Depth = 300 },
	{ Angle = 2.4, Depth = 385 },
	{ Angle = 4.1, Depth = 470 },
	{ Angle = 5.4, Depth = 545 },
}
WorldBuilder.Caves = CAVES

-- Distance from the centre to the rock wall at this angle and depth.
function WorldBuilder.WallRadius(theta, depth)
	local base = WorldBuilder.ShaftRadius(depth)
	if depth < -1 then
		return base
	end
	local c, s = math.cos(theta), math.sin(theta)
	local r = base + math.noise(c * 1.6, s * 1.6, depth / 38) * 9 + math.noise(c * 5, s * 5, depth / 9) * 2.5
	-- rounded rock ledges stick out every 45 m
	local m = depth % 45
	if depth > 25 and m < 9 then
		r -= 7 * math.sin(m / 9 * math.pi)
	end
	-- side caves
	for _, cave in ipairs(CAVES) do
		local ad = angleDiff(theta, cave.Angle)
		local dd = math.abs(depth - cave.Depth)
		if ad < 0.32 and dd < 16 then
			r += 30 * (1 - ad / 0.32) * (1 - (dd / 16) ^ 2)
		end
	end
	return r
end

function WorldBuilder.FloorDepth(x, z)
	local r = math.sqrt(x * x + z * z)
	return FLOOR_DEPTH + 10 - 14 * math.min(r / 82, 1.3) ^ 2 + math.noise(x / 30, z / 30, 3.3) * 3
end

function WorldBuilder.FloorY(x, z)
	return S - WorldBuilder.FloorDepth(x, z)
end

-- Keeps a point inside the water of the Well (used by monsters).
function WorldBuilder.ClampToWater(pos, margin)
	margin = margin or 18
	local y = math.min(pos.Y, S - 8)
	y = math.max(y, WorldBuilder.FloorY(pos.X, pos.Z) + 4)
	local depth = S - y
	local maxR = math.max(10, WorldBuilder.ShaftRadius(depth) - margin)
	local flat = Vector3.new(pos.X, 0, pos.Z)
	if flat.Magnitude > maxR then
		flat = flat.Unit * maxR
	end
	return Vector3.new(flat.X, y, flat.Z)
end

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { workspace.Terrain }
terrainParams.IgnoreWater = true

-- Finds the rock wall at this angle and depth. Returns position, normal.
local function wallHit(theta, depth)
	local origin = Vector3.new(0, S - depth, 0)
	local dir = Vector3.new(math.cos(theta), 0, math.sin(theta))
	local result = workspace:Raycast(origin, dir * 260, terrainParams)
	if result then
		return result.Position, result.Normal
	end
	return nil
end

local function groundBelow(pos, maxDrop)
	local result = workspace:Raycast(pos, Vector3.new(0, -(maxDrop or 80), 0), terrainParams)
	if result then
		return result.Position, result.Normal
	end
	return nil
end

function WorldBuilder.RealFloorY(x, z)
	local hit = groundBelow(Vector3.new(x, WorldBuilder.FloorY(x, z) + 40, z), 90)
	return hit and hit.Y or WorldBuilder.FloorY(x, z)
end

-- A random spot for salvage between two depths: resting on a rock ledge,
-- on the floor, or stuck to the wall.
function WorldBuilder.LootSpot(minDepth, maxDepth)
	for _ = 1, 25 do
		local theta = rng:NextNumber(0, TAU)
		local depth = rng:NextNumber(minDepth, maxDepth)
		local wallR = WorldBuilder.ShaftRadius(depth)
		local r = rng:NextNumber(wallR * 0.55, wallR - 6)
		local start = Vector3.new(math.cos(theta) * r, S - depth, math.sin(theta) * r)
		local ground = groundBelow(start, 70)
		if ground and S - ground.Y <= maxDepth + 15 and S - ground.Y >= minDepth then
			return ground + Vector3.new(0, 1.6, 0)
		end
		local wall, normal = wallHit(theta, depth)
		if wall and normal then
			return wall + normal * 1.8
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Terrain
------------------------------------------------------------------------
local M = Enum.Material

local function wallMaterial(depth, x, z, y)
	if depth < 0 then
		return M.Pavement
	elseif depth < 30 then
		return M.Rock
	elseif depth < 200 then
		return math.noise(x / 40, y / 25, z / 40) > 0.1 and M.Sandstone or M.Limestone
	elseif depth < 216 then
		return M.Rock
	elseif depth < 420 then
		return math.noise(x / 40, y / 30, z / 40) > 0.25 and M.Basalt or M.Slate
	end
	return M.Basalt
end

local function buildTerrain()
	local terrain = workspace.Terrain
	terrain:Clear()
	pcall(function()
		terrain.WaterColor = Color3.fromRGB(18, 88, 112)
		terrain.WaterTransparency = 0.5
		terrain.WaterReflectance = 0.7
		terrain.WaterWaveSize = 0.2
		terrain.WaterWaveSpeed = 9
	end)

	-- Open sea around the island, sandy seabed under it
	terrain:FillBlock(CFrame.new(0, S - 13, 0), Vector3.new(2048, 6, 2048), M.Sand)
	terrain:FillBlock(CFrame.new(0, S - 5, 0), Vector3.new(2048, 10, 2048), M.Water)
	-- The island: beach ring, then grass
	terrain:FillCylinder(CFrame.new(0, S - 9, 0), 20, 320, M.Sand)
	terrain:FillCylinder(CFrame.new(0, S - 8.5, 0), 23, 300, M.Grass)
	task.wait()
	-- Distant islands on the horizon (so the view isn't empty)
	for i = 1, 9 do
		local a = i / 9 * TAU + rng:NextNumber(-0.25, 0.25)
		local r = rng:NextNumber(560, 900)
		local cx, cz = math.cos(a) * r, math.sin(a) * r
		local height = rng:NextNumber(25, 110)
		local radius = rng:NextNumber(50, 120)
		for k = 0, 5 do
			local t = k / 5
			local bx = cx + rng:NextNumber(-radius, radius) * 0.4
			local bz = cz + rng:NextNumber(-radius, radius) * 0.4
			terrain:FillBall(
				Vector3.new(bx, S - 20 + height * t, bz),
				radius * (1 - t * 0.75),
				t > 0.5 and M.Grass or (t > 0.2 and M.Rock or M.Sand)
			)
		end
		terrain:FillCylinder(CFrame.new(cx, S - 6, cz), 10, radius * 1.15, M.Sand)
		task.wait()
	end

	-- The Well itself, written voxel by voxel so the walls are smooth
	local RES = 4
	local CHUNK = 64
	local MIN, MAX = -176, 208
	local yTop = S + 16
	local yBottom = S - 640
	local ny = (yTop - yBottom) / RES
	local n = CHUNK / RES
	local count = 0
	for x0 = MIN, MAX - CHUNK, CHUNK do
		for z0 = MIN, MAX - CHUNK, CHUNK do
			local materials, occupancy = {}, {}
			for ix = 1, n do
				local x = x0 + (ix - 0.5) * RES
				materials[ix], occupancy[ix] = {}, {}
				for iy = 1, ny do
					materials[ix][iy], occupancy[ix][iy] = {}, {}
				end
				for iz = 1, n do
					local z = z0 + (iz - 0.5) * RES
					local dist = math.sqrt(x * x + z * z)
					local theta = math.atan2(z, x)
					local floorY = WorldBuilder.FloorY(x, z)
					local landTop = S + 3
					for iy = 1, ny do
						local vy = yBottom + (iy - 1) * RES
						local depth = S - (vy + RES / 2)
						local base = WorldBuilder.ShaftRadius(depth)
						local occWall
						if dist > base + 45 then
							occWall = 1
						elseif dist < base - 22 then
							occWall = 0
						else
							occWall = math.clamp((dist - WorldBuilder.WallRadius(theta, depth)) / RES + 0.5, 0, 1)
						end
						if vy >= S - RES then
							-- above the sea: land only up to the plaza level
							occWall = math.min(occWall, math.clamp((landTop - vy) / RES, 0, 1))
						end
						local occFloor = math.clamp((floorY - vy) / RES, 0, 1)
						local occ = math.max(occWall, occFloor)
						local mat
						if occ <= 0 then
							mat = M.Air
						elseif occFloor >= occWall then
							mat = (math.noise(x / 25, z / 25) > 0) and M.Mud or M.Sand
						else
							mat = wallMaterial(depth, x, z, vy)
							if depth < 0 and dist > 185 then
								mat = M.Grass
							end
						end
						if vy + RES <= S and occ < 0.5 then
							mat = M.Water -- the Well is full of real water
							occ = 1
						end
						materials[ix][iy][iz] = mat
						occupancy[ix][iy][iz] = occ
					end
				end
			end
			local region = Region3.new(Vector3.new(x0, yBottom, z0), Vector3.new(x0 + CHUNK, yTop, z0 + CHUNK))
			terrain:WriteVoxels(region, RES, materials, occupancy)
			count += 1
			task.wait()
		end
	end
	_ = count

	-- Boulders on the floor
	for _ = 1, 26 do
		local a = rng:NextNumber(0, TAU)
		local r = rng:NextNumber(20, 78)
		local x, z = math.cos(a) * r, math.sin(a) * r
		terrain:FillBall(Vector3.new(x, WorldBuilder.FloorY(x, z), z), rng:NextNumber(3, 8), M.Basalt)
	end
end

------------------------------------------------------------------------
-- Harbor town
------------------------------------------------------------------------
local DOCK_TOP = S + 4
local BOARD_IN, BOARD_OUT = 119, 135
local BERTH_COUNT = 8
local WOOD = Color3.fromRGB(122, 88, 58)
local DARK_WOOD = Color3.fromRGB(78, 54, 36)
local IRON = Color3.fromRGB(38, 40, 46)

local function lampPost(parent, cf, height)
	height = height or 10
	part({
		Name = "LampPost",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 0.45, 0.45),
		CFrame = cf * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = M.Metal,
		Color = IRON,
		Parent = parent,
	})
	part({
		Name = "LampArm",
		Size = Vector3.new(1.6, 0.25, 0.25),
		CFrame = cf * CFrame.new(-0.6, height - 0.4, 0),
		Material = M.Metal,
		Color = IRON,
		Parent = parent,
	})
	local bulb = deco({
		Name = "Lamp",
		Size = Vector3.new(0.9, 1.2, 0.9),
		CFrame = cf * CFrame.new(-1.3, height - 1, 0),
		Material = M.Neon,
		Color = Color3.fromRGB(255, 214, 150),
		Mesh = SPHERE,
		Parent = parent,
	})
	deco({
		Name = "LampCap",
		Size = Vector3.new(1.3, 0.5, 1.3),
		CFrame = cf * CFrame.new(-1.3, height - 0.35, 0),
		Material = M.Metal,
		Color = IRON,
		Mesh = SPHERE,
		Parent = parent,
	})
	light(bulb, 22, 1.4, Color3.fromRGB(255, 210, 150), false)
	return bulb
end

local function palmTree(parent, pos)
	local lean = rng:NextNumber(0, TAU)
	local leanDir = Vector3.new(math.cos(lean), 0, math.sin(lean))
	local p = pos
	local segH = 3
	for i = 1, 6 do
		local nextP = p + Vector3.new(0, segH, 0) + leanDir * (0.25 * i)
		deco({
			Name = "PalmTrunk",
			Size = Vector3.new(1.3 - i * 0.08, (nextP - p).Magnitude + 0.3, 1.3 - i * 0.08),
			CFrame = CFrame.lookAt((p + nextP) / 2, nextP) * CFrame.Angles(math.rad(90), 0, 0),
			Material = M.Wood,
			Color = Color3.fromRGB(140 - i * 5, 110 - i * 4, 75),
			Mesh = SPHERE,
			CastShadow = true,
			Parent = parent,
		})
		p = nextP
	end
	for i = 1, 7 do
		local a = i / 7 * TAU
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local frondCenter = p + dir * 3.2 + Vector3.new(0, -0.6, 0)
		deco({
			Name = "PalmFrond",
			Size = Vector3.new(1.6, 0.18, 7.5),
			CFrame = CFrame.lookAt(frondCenter, frondCenter + dir) * CFrame.Angles(math.rad(-18), 0, 0),
			Material = M.Grass,
			Color = Color3.fromRGB(70, rng:NextInteger(140, 165), 55),
			Mesh = SPHERE,
			CastShadow = true,
			Sway = 2,
			Parent = parent,
		})
	end
	deco({
		Name = "Coconuts",
		Size = Vector3.new(1.4, 1, 1.4),
		CFrame = CFrame.new(p - Vector3.new(0, 0.6, 0)),
		Material = M.SmoothPlastic,
		Color = Color3.fromRGB(95, 70, 40),
		Mesh = SPHERE,
		Parent = parent,
	})
end

local function container(parent, cf, color)
	part({
		Name = "Container",
		Size = Vector3.new(8, 8.5, 20),
		CFrame = cf,
		Material = M.CorrodedMetal,
		Color = color,
		Parent = parent,
	})
	for i = -4, 4 do
		deco({
			Name = "Rib",
			Size = Vector3.new(8.2, 8.1, 0.25),
			CFrame = cf * CFrame.new(0, 0, i * 2.2),
			Material = M.Metal,
			Color = color:Lerp(Color3.new(0, 0, 0), 0.25),
			Parent = parent,
		})
	end
end

local function building(parent, cf, w, d, h, wallColor, roofColor, label)
	-- cf: centre of the floor, -X faces the Well
	local model = Instance.new("Model")
	model.Name = label or "Building"
	model.Parent = parent
	part({
		Name = "Walls",
		Size = Vector3.new(d, h, w),
		CFrame = cf * CFrame.new(0, h / 2, 0),
		Material = M.Brick,
		Color = wallColor,
		Parent = model,
	})
	part({
		Name = "Roof",
		Size = Vector3.new(d + 2, 1, w + 2),
		CFrame = cf * CFrame.new(0, h + 0.5, 0),
		Material = M.Slate,
		Color = roofColor,
		Parent = model,
	})
	part({
		Name = "RoofTrim",
		Size = Vector3.new(d + 2.4, 0.4, w + 2.4),
		CFrame = cf * CFrame.new(0, h, 0),
		Material = M.SmoothPlastic,
		Color = Color3.fromRGB(235, 235, 230),
		Parent = model,
	})
	part({
		Name = "Door",
		Size = Vector3.new(0.3, h * 0.6, w * 0.35),
		CFrame = cf * CFrame.new(-d / 2 - 0.1, h * 0.3, 0),
		Material = M.Metal,
		Color = IRON,
		Parent = model,
	})
	for _, z in ipairs({ -w * 0.35, w * 0.35 }) do
		local win = deco({
			Name = "Window",
			Size = Vector3.new(0.2, h * 0.25, w * 0.15),
			CFrame = cf * CFrame.new(-d / 2 - 0.1, h * 0.62, z),
			Material = M.Neon,
			Color = Color3.fromRGB(255, 220, 160),
			Parent = model,
		})
		_ = win
	end
	if label then
		local sign = part({
			Name = "Sign",
			Size = Vector3.new(0.3, 3, w * 0.6),
			CFrame = cf * CFrame.new(-d / 2 - 0.3, h - 2, 0),
			Material = M.SmoothPlastic,
			Color = Color3.fromRGB(20, 30, 50),
			Parent = model,
		})
		surfaceText(sign, Enum.NormalId.Left, label, Color3.fromRGB(255, 220, 120), 30)
	end
	return model
end

-- Swap in a real model from ReplicatedStorage > DeepDiveModels if there is one.
-- cf uses this file's "radial" frames (-X faces the Well); models usually face
-- -Z, so we turn them 90 degrees so their front faces the middle.
local function useCustom(name, cf, size, parent)
	local m = Config.PlaceCustomModel(name, cf * CFrame.Angles(0, math.rad(90), 0), size, { Ground = true })
	if m then
		m.Parent = parent
	end
	return m
end

local function cottage(parent, cf)
	local model = Instance.new("Model")
	model.Name = "Cottage"
	model.Parent = parent
	local wallColors = {
		Color3.fromRGB(240, 230, 210),
		Color3.fromRGB(200, 225, 235),
		Color3.fromRGB(245, 215, 190),
		Color3.fromRGB(215, 235, 205),
	}
	local roofColors = { Color3.fromRGB(170, 60, 45), Color3.fromRGB(50, 80, 120), Color3.fromRGB(90, 70, 60) }
	local w, d, h = 18, 14, 9
	part({
		Name = "Walls",
		Size = Vector3.new(d, h, w),
		CFrame = cf * CFrame.new(0, h / 2, 0),
		Material = M.Plaster,
		Color = wallColors[rng:NextInteger(1, #wallColors)],
		CastShadow = true,
		Parent = model,
	})
	local roofColor = roofColors[rng:NextInteger(1, #roofColors)]
	for _, side in ipairs({ -1, 1 }) do
		local roof = Instance.new("WedgePart")
		roof.Anchored = true
		roof.Size = Vector3.new(w + 1.5, 5, d / 2 + 1)
		roof.CFrame = cf * CFrame.new(side * (d / 4 + 0.25), h + 2.5, 0) * CFrame.Angles(0, side * math.rad(90), 0)
		roof.Material = M.Slate
		roof.Color = roofColor
		roof.Parent = model
	end
	part({
		Name = "Chimney",
		Size = Vector3.new(1.6, 4, 1.6),
		CFrame = cf * CFrame.new(2, h + 4, w * 0.3),
		Material = M.Brick,
		Color = Color3.fromRGB(140, 70, 55),
		Parent = model,
	})
	part({
		Name = "Door",
		Size = Vector3.new(0.3, 5, 2.6),
		CFrame = cf * CFrame.new(-d / 2 - 0.1, 2.5, 0),
		Material = M.Wood,
		Color = DARK_WOOD,
		Parent = model,
	})
	for _, z in ipairs({ -5, 5 }) do
		deco({
			Name = "Window",
			Size = Vector3.new(0.2, 2.4, 2.6),
			CFrame = cf * CFrame.new(-d / 2 - 0.1, 5, z),
			Material = M.Neon,
			Color = Color3.fromRGB(255, 220, 160),
			Parent = model,
		})
		deco({
			Name = "Shutter",
			Size = Vector3.new(0.2, 2.6, 0.6),
			CFrame = cf * CFrame.new(-d / 2 - 0.15, 5, z - 1.6),
			Material = M.Wood,
			Color = roofColor,
			Parent = model,
		})
	end
	-- little picket fence out front
	for z = -w / 2, w / 2, 1.5 do
		if math.abs(z) > 2 then
			deco({
				Name = "Picket",
				Size = Vector3.new(0.25, 2, 0.4),
				CFrame = cf * CFrame.new(-d / 2 - 4, 1, z),
				Material = M.Wood,
				Color = Color3.fromRGB(245, 245, 240),
				Parent = model,
			})
		end
	end
	return model
end

local function sailboat(parent, cf)
	local model = Instance.new("Model")
	model.Name = "Sailboat"
	model.Parent = parent
	local hullColor = rng:NextNumber() < 0.5 and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(40, 70, 120)
	part({
		Name = "Hull",
		Size = Vector3.new(7, 3.5, 22),
		CFrame = cf * CFrame.new(0, 0.6, 0),
		Material = M.SmoothPlastic,
		Color = hullColor,
		Mesh = SPHERE,
		Parent = model,
	})
	part({
		Name = "Deck",
		Size = Vector3.new(5.6, 0.4, 17),
		CFrame = cf * CFrame.new(0, 1.9, 0),
		Material = M.WoodPlanks,
		Color = WOOD,
		Mesh = SPHERE,
		Parent = model,
	})
	part({
		Name = "Cabin",
		Size = Vector3.new(4, 2, 6),
		CFrame = cf * CFrame.new(0, 2.8, 2),
		Material = M.SmoothPlastic,
		Color = Color3.fromRGB(235, 235, 235),
		Mesh = SPHERE,
		Parent = model,
	})
	part({
		Name = "Mast",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(20, 0.4, 0.4),
		CFrame = cf * CFrame.new(0, 12, -1) * CFrame.Angles(0, 0, math.rad(90)),
		Material = M.Metal,
		Color = Color3.fromRGB(200, 200, 205),
		Parent = model,
	})
	local sail = Instance.new("WedgePart")
	sail.Anchored = true
	sail.CanCollide = false
	sail.Size = Vector3.new(0.15, 17, 8)
	sail.CFrame = cf * CFrame.new(0, 11.5, 3.2) * CFrame.Angles(0, math.pi, 0)
	sail.Material = M.Fabric
	sail.Color = Color3.fromRGB(250, 248, 240)
	sail.Parent = model
	return model
end

local function buildHarbor(root)
	local dock = Instance.new("Folder")
	dock.Name = "Dock"
	dock.Parent = root

	-- Round boardwalk
	local N = 64
	local midR = (BOARD_IN + BOARD_OUT) / 2
	local width = BOARD_OUT - BOARD_IN
	for i = 0, N - 1 do
		local a = i / N * TAU
		local arc = TAU * BOARD_OUT / N + 0.4
		part({
			Name = "Boardwalk",
			Size = Vector3.new(width, 1.2, arc),
			CFrame = radial(midR, a, DOCK_TOP - 0.6),
			Material = M.WoodPlanks,
			Color = (i % 2 == 0) and WOOD or WOOD:Lerp(DARK_WOOD, 0.15),
			Parent = dock,
		})
		deco({
			Name = "EdgeBeam",
			Size = Vector3.new(0.8, 1.6, TAU * BOARD_IN / N + 0.3),
			CFrame = radial(BOARD_IN + 0.4, a, DOCK_TOP - 1),
			Material = M.Wood,
			Color = DARK_WOOD,
			Parent = dock,
		})
		if i % 2 == 0 then
			deco({
				Name = "Pylon",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(26, 1.6, 1.6),
				CFrame = radial(BOARD_IN + 1.2, a, DOCK_TOP - 13) * CFrame.Angles(0, 0, math.rad(90)),
				Material = M.Wood,
				Color = DARK_WOOD,
				Parent = dock,
			})
		end
	end

	-- Berths: piers pointing into the Well
	local berths = {}
	local pierLen = 26
	for i = 1, BERTH_COUNT do
		local a = (i - 1) / BERTH_COUNT * TAU + TAU / 16
		local pierMid = BOARD_IN - pierLen / 2 + 0.5
		local pier = part({
			Name = "Pier" .. i,
			Size = Vector3.new(pierLen, 1.2, 7),
			CFrame = radial(pierMid, a, DOCK_TOP - 0.6),
			Material = M.WoodPlanks,
			Color = WOOD,
			Parent = dock,
		})
		for _, off in ipairs({ -pierLen / 2 + 2, 0, pierLen / 2 - 2 }) do
			for _, side in ipairs({ -3.2, 3.2 }) do
				deco({
					Name = "PierPost",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(18, 1.2, 1.2),
					CFrame = radial(pierMid, a, DOCK_TOP - 1)
						* CFrame.new(off, -8, side)
						* CFrame.Angles(0, 0, math.rad(90)),
					Material = M.Wood,
					Color = DARK_WOOD,
					Parent = dock,
				})
			end
		end
		-- rope rails along the pier
		for _, side in ipairs({ -3.3, 3.3 }) do
			deco({
				Name = "Rope",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(pierLen - 1, 0.18, 0.18),
				CFrame = radial(pierMid, a, DOCK_TOP + 2.2) * CFrame.new(0, 0, side),
				Material = M.Fabric,
				Color = Color3.fromRGB(200, 180, 140),
				Parent = dock,
			})
			for _, off in ipairs({ -pierLen / 2 + 1, -pierLen / 4, 0, pierLen / 4, pierLen / 2 - 1 }) do
				part({
					Name = "RailPost",
					Size = Vector3.new(0.4, 2.6, 0.4),
					CFrame = radial(pierMid, a, DOCK_TOP + 1.3) * CFrame.new(off, 0, side),
					Material = M.Wood,
					Color = DARK_WOOD,
					Parent = dock,
				})
			end
		end
		-- bollards and a life ring
		for _, off in ipairs({ -pierLen / 2 + 3, pierLen / 2 - 6 }) do
			part({
				Name = "Bollard",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.4, 1.3, 1.3),
				CFrame = radial(pierMid, a, DOCK_TOP + 0.7)
					* CFrame.new(off, 0, 2.4)
					* CFrame.Angles(0, 0, math.rad(90)),
				Material = M.Metal,
				Color = IRON,
				Parent = dock,
			})
		end
		deco({
			Name = "LifeRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 2.2, 2.2),
			CFrame = radial(pierMid, a, DOCK_TOP + 1.6) * CFrame.new(2, 0, -3.5) * CFrame.Angles(0, math.rad(90), 0),
			Material = M.SmoothPlastic,
			Color = Color3.fromRGB(240, 110, 40),
			Parent = dock,
		})
		-- light at the end of the pier (gold when the berth is owned)
		local tip = lampPost(dock, radial(BOARD_IN - pierLen + 1.5, a, DOCK_TOP) * CFrame.new(0, 0, -3), 7)
		-- berth sign
		local board = part({
			Name = "BerthSign",
			Size = Vector3.new(0.4, 2.6, 8),
			CFrame = radial(BOARD_IN + 3, a, DOCK_TOP + 5.4) * CFrame.new(0, 0, 0),
			Material = M.SmoothPlastic,
			Color = Color3.fromRGB(22, 36, 64),
			Parent = dock,
		})
		for _, side in ipairs({ -3.5, 3.5 }) do
			part({
				Name = "SignPost",
				Size = Vector3.new(0.4, 5.5, 0.4),
				CFrame = radial(BOARD_IN + 3, a, DOCK_TOP + 2.75) * CFrame.new(0, 0, side),
				Material = M.Wood,
				Color = DARK_WOOD,
				Parent = dock,
			})
		end
		local l1 = surfaceText(board, Enum.NormalId.Left, "BERTH " .. i .. "\nfree", Color3.new(1, 1, 1), 30)
		local l2 = surfaceText(board, Enum.NormalId.Right, "BERTH " .. i .. "\nfree", Color3.new(1, 1, 1), 30)
		-- the sub floats beside the pier, nose pointing into the Well
		local subR = BOARD_IN - pierLen / 2 - 6
		local subPos = radial(subR, a, S + 0.5) * Vector3.new(0, 0, 12)
		local inward = -Vector3.new(math.cos(a), 0, math.sin(a))
		table.insert(berths, {
			Index = i,
			SubCFrame = CFrame.lookAt(subPos, subPos + inward),
			ExitCFrame = radial(BOARD_IN - 6, a, DOCK_TOP + 3),
			Labels = { l1, l2 },
			Marker = tip,
			Pier = pier,
		})
	end
	WorldBuilder.Berths = berths

	-- Lamp posts around the boardwalk
	for i = 0, 15 do
		local a = i / 16 * TAU
		lampPost(dock, radial(BOARD_OUT - 1, a, DOCK_TOP), 11)
	end

	-- Spawn plaza (in front of the shop)
	local spawnCF = radial(146, 0.18, DOCK_TOP - 0.5)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "DockSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = spawnCF
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = M.Cobblestone
	spawn.Color = Color3.fromRGB(120, 120, 125)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = dock
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	WorldBuilder.SpawnCFrame = spawnCF * CFrame.new(0, 3.5, 0)

	-- Salvage shop
	local shopCF = radial(160, 0, DOCK_TOP - 1)
	local shop = building(dock, shopCF, 26, 16, 12, Color3.fromRGB(70, 130, 160), Color3.fromRGB(170, 55, 45), nil)
	shop.Name = "ShopHut"
	local counter = part({
		Name = "Counter",
		Size = Vector3.new(3, 3.6, 14),
		CFrame = shopCF * CFrame.new(-10, 1.8, 0),
		Material = M.Wood,
		Color = DARK_WOOD,
		Parent = shop,
	})
	-- striped awning
	for i = -3, 3 do
		deco({
			Name = "Awning",
			Size = Vector3.new(6, 0.3, 3.6),
			CFrame = shopCF * CFrame.new(-10.5, 10.2, i * 3.6) * CFrame.Angles(0, 0, math.rad(-18)),
			Material = M.Fabric,
			Color = (i % 2 == 0) and Color3.fromRGB(240, 240, 235) or Color3.fromRGB(210, 60, 50),
			Parent = shop,
		})
	end
	local shopSign = part({
		Name = "ShopSign",
		Size = Vector3.new(0.4, 4, 20),
		CFrame = shopCF * CFrame.new(-8.3, 14.6, 0),
		Material = M.SmoothPlastic,
		Color = Color3.fromRGB(20, 30, 50),
		Parent = shop,
	})
	surfaceText(shopSign, Enum.NormalId.Left, "SALVAGE SHOP", Color3.fromRGB(255, 210, 80), 30)
	light(shopSign, 18, 1, Color3.fromRGB(255, 220, 150), false)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = "Salvage Shop"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	WorldBuilder.ShopPrompt = prompt
	task.defer(function()
		-- a real shop model replaces the built-in hut (the prompt stays at the counter)
		if useCustom("Shop", shopCF * CFrame.new(3, 0, 0), Config.CustomModels.Shop.Size, dock) then
			for _, p in ipairs(shop:GetDescendants()) do
				if p:IsA("BasePart") and p ~= counter then
					p:Destroy()
				end
			end
			counter.Transparency = 1
			counter.CanCollide = false
		end
	end)
	for _, z in ipairs({ -5, 0, 5 }) do
		deco({
			Name = "Goods",
			Size = Vector3.new(1.4, 1.2, 1.4),
			CFrame = shopCF * CFrame.new(-10, 4.2, z),
			Material = M.Foil,
			Color = Color3.fromRGB(255, 200, 70),
			Mesh = SPHERE,
			Parent = shop,
		})
	end

	-- Depth leaderboard
	local boardCF = radial(150, 0.55, DOCK_TOP - 1)
	local boardPart = part({
		Name = "DepthBoard",
		Size = Vector3.new(0.6, 12, 17),
		CFrame = boardCF * CFrame.new(0, 8, 0),
		Material = M.SmoothPlastic,
		Color = Color3.fromRGB(14, 20, 38),
		Parent = dock,
	})
	for _, z in ipairs({ -7.5, 7.5 }) do
		part({
			Name = "BoardLeg",
			Size = Vector3.new(0.6, 8, 0.6),
			CFrame = boardCF * CFrame.new(0, 2, z),
			Material = M.Metal,
			Color = IRON,
			Parent = dock,
		})
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = boardPart
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.16)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(110, 220, 255)
	title.Text = "DEEPEST DIVES"
	title.Parent = gui
	local list = Instance.new("TextLabel")
	list.Name = "List"
	list.Position = UDim2.fromScale(0.06, 0.18)
	list.Size = UDim2.fromScale(0.88, 0.78)
	list.BackgroundTransparency = 1
	list.Font = Enum.Font.GothamBold
	list.TextScaled = true
	list.TextXAlignment = Enum.TextXAlignment.Left
	list.TextYAlignment = Enum.TextYAlignment.Top
	list.TextColor3 = Color3.new(1, 1, 1)
	list.Text = "Loading..."
	list.Parent = gui
	WorldBuilder.LeaderboardLabel = list

	-- Welcome sign
	local welcomeCF = radial(150, -0.55, DOCK_TOP - 1)
	local welcome = part({
		Name = "WelcomeSign",
		Size = Vector3.new(0.6, 7, 18),
		CFrame = welcomeCF * CFrame.new(0, 7, 0),
		Material = M.SmoothPlastic,
		Color = Color3.fromRGB(14, 20, 38),
		Parent = dock,
	})
	for _, z in ipairs({ -8, 8 }) do
		part({
			Name = "SignLeg",
			Size = Vector3.new(0.6, 5, 0.6),
			CFrame = welcomeCF * CFrame.new(0, 2, z),
			Material = M.Metal,
			Color = IRON,
			Parent = dock,
		})
	end
	surfaceText(
		welcome,
		Enum.NormalId.Left,
		"THE WELL\n600 m straight down.\nBoard your sub - salvage - SURFACE to cash in!",
		Color3.fromRGB(255, 230, 140),
		30
	)

	-- Warehouses + containers
	local palette = {
		Color3.fromRGB(180, 60, 45),
		Color3.fromRGB(40, 100, 160),
		Color3.fromRGB(60, 140, 80),
		Color3.fromRGB(220, 160, 40),
	}
	for i, a in ipairs({ 1.6, 3.15, 4.7 }) do
		local cf = radial(178, a, DOCK_TOP - 1)
		if not useCustom("Warehouse", cf, Config.CustomModels.Warehouse.Size, dock) then
			building(dock, cf, 40, 22, 16, Color3.fromRGB(150, 150, 155), Color3.fromRGB(70, 80, 95), "WAREHOUSE " .. i)
		end
		for c = 0, 2 do
			local ccf = radial(150, a + 0.22 + c * 0.07, DOCK_TOP + 3.25) * CFrame.Angles(0, math.rad(90), 0)
			container(dock, ccf, palette[(i + c) % #palette + 1])
			if c == 1 then
				container(dock, ccf * CFrame.new(0, 8.5, 0), palette[(i + c + 1) % #palette + 1])
			end
		end
	end

	-- Dock crane leaning over the water
	local craneA = 2.35
	local craneModel = Instance.new("Model")
	craneModel.Name = "Crane"
	craneModel.Parent = dock
	local craneCF = radial(BOARD_IN + 8, craneA, DOCK_TOP)
	local yellow = Color3.fromRGB(240, 185, 30)
	for _, x in ipairs({ -2.5, 2.5 }) do
		for _, z in ipairs({ -2.5, 2.5 }) do
			part({
				Name = "CraneLeg",
				Size = Vector3.new(0.8, 30, 0.8),
				CFrame = craneCF * CFrame.new(x, 15, z),
				Material = M.Metal,
				Color = yellow,
				Parent = craneModel,
			})
		end
	end
	for h = 6, 28, 6 do
		part({
			Name = "CraneBrace",
			Size = Vector3.new(5.8, 0.5, 5.8),
			CFrame = craneCF * CFrame.new(0, h, 0),
			Material = M.Metal,
			Color = yellow,
			Parent = craneModel,
		})
	end
	part({
		Name = "CraneCab",
		Size = Vector3.new(6, 4, 6),
		CFrame = craneCF * CFrame.new(0, 32, 0),
		Material = M.Metal,
		Color = yellow,
		Parent = craneModel,
	})
	part({
		Name = "CraneBoom",
		Size = Vector3.new(34, 1.2, 1.6),
		CFrame = craneCF * CFrame.new(-15, 33.5, 0),
		Material = M.Metal,
		Color = yellow,
		Parent = craneModel,
	})
	deco({
		Name = "CraneCable",
		Size = Vector3.new(0.15, 18, 0.15),
		CFrame = craneCF * CFrame.new(-30, 24.5, 0),
		Material = M.Metal,
		Color = IRON,
		Parent = craneModel,
	})
	part({
		Name = "CraneHook",
		Size = Vector3.new(1.4, 1.6, 1.4),
		CFrame = craneCF * CFrame.new(-30, 15, 0),
		Material = M.Metal,
		Color = IRON,
		Mesh = SPHERE,
		Parent = craneModel,
	})

	if useCustom("Crane", craneCF, Config.CustomModels.Crane.Size, dock) then
		craneModel:Destroy()
	end

	-- Crates, barrels, benches scattered on the plaza
	for _ = 1, 30 do
		local a = rng:NextNumber(0, TAU)
		local r = rng:NextNumber(139, 146)
		if angleDiff(a, 0) > 0.3 and angleDiff(a, 0.55) > 0.15 and angleDiff(a, -0.55) > 0.15 then
			local cf = radial(r, a, DOCK_TOP - 1) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
			if rng:NextNumber() < 0.5 then
				local s = rng:NextNumber(2.4, 3.6)
				part({
					Name = "Crate",
					Size = Vector3.new(s, s, s),
					CFrame = cf * CFrame.new(0, s / 2, 0),
					Material = M.WoodPlanks,
					Color = Color3.fromRGB(165, 125, 75),
					Parent = dock,
				})
			else
				part({
					Name = "Barrel",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(3.2, 2.4, 2.4),
					CFrame = cf * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
					Material = M.Metal,
					Color = rng:NextNumber() < 0.5 and Color3.fromRGB(175, 60, 40) or Color3.fromRGB(45, 105, 155),
					Parent = dock,
				})
			end
		end
	end

	-- Palm trees on the grass
	for _ = 1, 22 do
		local a = rng:NextNumber(0, TAU)
		local r = rng:NextNumber(205, 285)
		local pos = Vector3.new(math.cos(a) * r, S + 3.1, math.sin(a) * r)
		local cf = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
		local size = Config.CustomModels.PalmTree.Size * rng:NextNumber(0.85, 1.2)
		local tree = Config.PlaceCustomModel("PalmTree", cf, size, { Ground = true, AllAxes = true })
		if tree then
			tree.Parent = dock
		else
			palmTree(dock, pos)
		end
	end

	-- Lighthouse
	local lhModel = Instance.new("Model")
	lhModel.Name = "Lighthouse"
	lhModel.Parent = dock
	local lhPos = Vector3.new(math.cos(3.9) * 255, S + 3, math.sin(3.9) * 255)
	for i = 0, 6 do
		part({
			Name = "Lighthouse",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(7, 10 - i * 0.7, 10 - i * 0.7),
			CFrame = CFrame.new(lhPos + Vector3.new(0, 3.5 + i * 7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = M.SmoothPlastic,
			Color = (i % 2 == 0) and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(200, 40, 40),
			CastShadow = true,
			Parent = lhModel,
		})
	end
	local beacon = deco({
		Name = "LighthouseLamp",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5, 5, 5),
		CFrame = CFrame.new(lhPos + Vector3.new(0, 52, 0)),
		Material = M.Neon,
		Color = Color3.fromRGB(255, 240, 170),
		Parent = lhModel,
	})
	light(beacon, 60, 2, Color3.fromRGB(255, 235, 170), false)
	part({
		Name = "LighthouseCap",
		Size = Vector3.new(6, 3, 6),
		CFrame = CFrame.new(lhPos + Vector3.new(0, 55.5, 0)),
		Material = M.Metal,
		Color = Color3.fromRGB(40, 40, 45),
		Mesh = SPHERE,
		Parent = lhModel,
	})

	if useCustom("Lighthouse", CFrame.new(lhPos), Config.CustomModels.Lighthouse.Size, dock) then
		lhModel:Destroy()
	end

	-- Cottages around the island
	for i, a in ipairs({ 0.45, 0.95, 2.05, 2.75, 3.45, 4.25, 5.25, 5.85 }) do
		local cf = radial(232 + (i % 2) * 18, a, S + 3)
		if not useCustom("House", cf, Config.CustomModels.House.Size, dock) then
			cottage(dock, cf)
		end
	end

	-- Boats anchored out at sea
	for i = 1, 7 do
		local a = i / 7 * TAU + rng:NextNumber(-0.2, 0.2)
		local r = rng:NextNumber(400, 680)
		local cf = CFrame.new(math.cos(a) * r, S, math.sin(a) * r) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
		local boat = Config.PlaceCustomModel("Boat", cf, Config.CustomModels.Boat.Size, { Ground = false })
		if boat then
			boat.Parent = dock
		else
			sailboat(dock, cf)
		end
	end

	-- Buoys floating in the Well
	for i = 1, 8 do
		local a = i / 8 * TAU
		local b = deco({
			Name = "Buoy",
			Size = Vector3.new(2.6, 3, 2.6),
			CFrame = radial(55, a, S + 0.6),
			Material = M.SmoothPlastic,
			Color = (i % 2 == 0) and Color3.fromRGB(240, 70, 50) or Color3.fromRGB(245, 245, 245),
			Mesh = SPHERE,
			Parent = dock,
		})
		deco({
			Name = "BuoyLight",
			Size = Vector3.new(0.6, 0.8, 0.6),
			CFrame = b.CFrame * CFrame.new(0, 1.9, 0),
			Material = M.Neon,
			Color = Color3.fromRGB(255, 220, 100),
			Mesh = SPHERE,
			Parent = dock,
		})
	end
end

------------------------------------------------------------------------
-- Inside the Well
------------------------------------------------------------------------
local CORAL_COLORS = {
	Color3.fromRGB(255, 100, 130),
	Color3.fromRGB(255, 150, 60),
	Color3.fromRGB(180, 90, 255),
	Color3.fromRGB(80, 220, 200),
	Color3.fromRGB(255, 220, 90),
	Color3.fromRGB(255, 80, 80),
}

local function coralOnWall(folder, pos, normal)
	local base = CFrame.lookAt(pos, pos + normal) -- -Z (LookVector) points out of the wall
	local color = CORAL_COLORS[rng:NextInteger(1, #CORAL_COLORS)]
	local kind = rng:NextInteger(1, 4)
	if kind == 1 then
		-- tube sponges sticking out of the rock
		for _ = 1, rng:NextInteger(3, 5) do
			local len = rng:NextNumber(2, 4.5)
			local off = CFrame.new(rng:NextNumber(-1.5, 1.5), rng:NextNumber(-1.5, 1.5), 0)
			deco({
				Name = "TubeSponge",
				Size = Vector3.new(0.9, 0.9, len),
				CFrame = base
					* off
					* CFrame.Angles(rng:NextNumber(-0.5, 0.2), rng:NextNumber(-0.4, 0.4), 0)
					* CFrame.new(0, 0, -len / 2),
				Material = M.SmoothPlastic,
				Color = color,
				Mesh = SPHERE,
				Parent = folder,
			})
		end
	elseif kind == 2 then
		-- brain coral dome
		local s = rng:NextNumber(2.5, 5)
		deco({
			Name = "BrainCoral",
			Size = Vector3.new(s, s, s * 0.6),
			CFrame = base * CFrame.new(0, 0, -s * 0.15),
			Material = M.Pebble,
			Color = color,
			Mesh = SPHERE,
			Parent = folder,
		})
	elseif kind == 3 then
		-- sea fan
		local h = rng:NextNumber(3, 6)
		deco({
			Name = "SeaFan",
			Size = Vector3.new(h, h * 0.9, 0.15),
			CFrame = base * CFrame.new(0, 0, -h * 0.4),
			Material = M.Fabric,
			Color = color,
			Transparency = 0.1,
			Mesh = SPHERE,
			Sway = h,
			Parent = folder,
		})
	else
		-- anemone with glowing tips
		deco({
			Name = "Anemone",
			Size = Vector3.new(1.6, 1.6, 1.2),
			CFrame = base * CFrame.new(0, 0, -0.4),
			Material = M.SmoothPlastic,
			Color = Color3.fromRGB(255, 160, 80),
			Mesh = SPHERE,
			Parent = folder,
		})
		for _ = 1, 6 do
			deco({
				Name = "AnemoneTip",
				Size = Vector3.new(0.25, 0.25, 1.3),
				CFrame = base
					* CFrame.new(rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.6, 0.6), -1.2)
					* CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.5, 0.5), 0),
				Material = M.Neon,
				Color = Color3.fromRGB(255, 120, 200),
				Mesh = SPHERE,
				Parent = folder,
			})
		end
	end
end

local function kelpOnLedge(folder, pos)
	for blade = 1, rng:NextInteger(2, 4) do
		local h = rng:NextNumber(8, 20)
		deco({
			Name = "Kelp",
			Size = Vector3.new(0.3, h, 1.6),
			CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1.2, 1.2), h / 2 - 0.5, rng:NextNumber(-1.2, 1.2)))
				* CFrame.Angles(rng:NextNumber(-0.1, 0.1), blade * 1.1, rng:NextNumber(-0.1, 0.1)),
			Material = M.SmoothPlastic,
			Color = Color3.fromRGB(rng:NextInteger(55, 95), rng:NextInteger(120, 155), 45),
			Mesh = SPHERE,
			Sway = h,
			Parent = folder,
		})
	end
end

local CRYSTAL_COLORS = { Color3.fromRGB(80, 240, 255), Color3.fromRGB(170, 100, 255), Color3.fromRGB(80, 255, 160) }

local function crystalCluster(folder, pos, normal, withLight)
	local base = CFrame.lookAt(pos, pos + normal)
	local color = CRYSTAL_COLORS[rng:NextInteger(1, #CRYSTAL_COLORS)]
	local first
	for _ = 1, rng:NextInteger(3, 5) do
		local len = rng:NextNumber(2, 6)
		local p = deco({
			Name = "Crystal",
			Size = Vector3.new(0.9, 0.9, len),
			CFrame = base
				* CFrame.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), 0)
				* CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.6, 0.6), 0)
				* CFrame.new(0, 0, -len / 2),
			Material = M.Neon,
			Color = color,
			Transparency = 0.15,
			Parent = folder,
		})
		first = first or p
	end
	if withLight and first then
		light(first, 16, 1.5, color, false)
	end
end

local function buildWell(root)
	local well = Instance.new("Folder")
	well.Name = "Reef" -- (clients look for swaying plants in here)
	well.Parent = root

	-- Sun rays shining down from the surface
	for i = 1, 8 do
		local a = rng:NextNumber(0, TAU)
		local r = rng:NextNumber(0, 70)
		local len = rng:NextNumber(110, 190)
		local w = rng:NextNumber(6, 14)
		deco({
			Name = "LightRay",
			Size = Vector3.new(w, len, w * 0.6),
			CFrame = CFrame.new(math.cos(a) * r, S - len / 2 - 2, math.sin(a) * r)
				* CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), a, math.rad(rng:NextNumber(-6, 6))),
			Material = M.Neon,
			Color = Color3.fromRGB(190, 235, 255),
			Transparency = 0.94,
			Parent = well,
		})
		_ = i
	end

	-- Depth marker lights every 50 m
	for depth = 50, 550, 50 do
		for k = 0, 3 do
			local a = k / 4 * TAU + depth / 70
			local pos, normal = wallHit(a, depth)
			if pos then
				local cf = CFrame.lookAt(pos, pos + normal)
				local plate = deco({
					Name = "DepthMarker",
					Size = Vector3.new(5, 2.4, 0.4),
					CFrame = cf * CFrame.new(0, 0, -0.3),
					Material = M.Metal,
					Color = Color3.fromRGB(40, 44, 52),
					Parent = well,
				})
				surfaceText(plate, Enum.NormalId.Front, depth .. " m", Color3.fromRGB(255, 200, 90), 30)
				local lamp = deco({
					Name = "MarkerLamp",
					Size = Vector3.new(0.8, 0.8, 0.8),
					CFrame = cf * CFrame.new(0, 1.8, -0.5),
					Material = M.Neon,
					Color = depth < 200 and Color3.fromRGB(255, 210, 120) or Color3.fromRGB(255, 80, 60),
					Mesh = SPHERE,
					Parent = well,
				})
				light(lamp, 26, 1.6, lamp.Color, false)
			end
		end
		task.wait()
	end

	-- Sunlit Reef: coral and sponges on the walls, kelp on the ledges
	for i = 1, 230 do
		local a = rng:NextNumber(0, TAU)
		local depth = rng:NextNumber(4, 198)
		local pos, normal = wallHit(a, depth)
		if pos then
			coralOnWall(well, pos, normal)
		end
		if i % 3 == 0 then
			local r = WorldBuilder.ShaftRadius(depth) - rng:NextNumber(4, 12)
			local ground = groundBelow(Vector3.new(math.cos(a) * r, S - depth, math.sin(a) * r), 40)
			if ground and S - ground.Y < 205 then
				kelpOnLedge(well, ground)
			end
		end
		if i % 40 == 0 then
			task.wait()
		end
	end

	-- Twilight Drop: glowing crystals on the walls and in the caves
	for i = 1, 140 do
		local a = rng:NextNumber(0, TAU)
		local depth = rng:NextNumber(215, 600)
		local pos, normal = wallHit(a, depth)
		if pos then
			crystalCluster(well, pos, normal, i % 4 == 0)
		end
		if i % 40 == 0 then
			task.wait()
		end
	end
	for _, cave in ipairs(CAVES) do
		for k = 1, 6 do
			local a = cave.Angle + rng:NextNumber(-0.2, 0.2)
			local pos, normal = wallHit(a, cave.Depth + rng:NextNumber(-8, 8))
			if pos then
				crystalCluster(well, pos, normal, k == 1)
			end
		end
	end

	-- The Lip at 200 m: wreck of the research sub "Meridian"
	do
		local a = 1.1
		local r = 92
		local ground = groundBelow(Vector3.new(math.cos(a) * r, S - 195, math.sin(a) * r), 40)
		local base = ground or Vector3.new(math.cos(a) * r, S - 214, math.sin(a) * r)
		local wreck = Instance.new("Model")
		wreck.Name = "MeridianWreck"
		wreck.Parent = well
		local cf = CFrame.new(base + Vector3.new(0, 3, 0)) * CFrame.Angles(0, a + 1.4, math.rad(20))
		local rust = Color3.fromRGB(130, 80, 55)
		part({
			Name = "Hull",
			Size = Vector3.new(7, 6.5, 22),
			CFrame = cf,
			Material = M.CorrodedMetal,
			Color = rust,
			Mesh = SPHERE,
			Parent = wreck,
		})
		part({
			Name = "Tower",
			Size = Vector3.new(2.5, 4, 6),
			CFrame = cf * CFrame.new(0, 3.6, 1),
			Material = M.CorrodedMetal,
			Color = rust,
			Mesh = SPHERE,
			Parent = wreck,
		})
		deco({
			Name = "BrokenGlass",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(5, 5, 5),
			CFrame = cf * CFrame.new(0, 0.4, -10),
			Material = M.Glass,
			Color = Color3.fromRGB(120, 160, 170),
			Transparency = 0.6,
			Parent = wreck,
		})
		local nameplate = deco({
			Name = "Nameplate",
			Size = Vector3.new(0.2, 1.4, 5),
			CFrame = cf * CFrame.new(3.4, 0.5, 2),
			Material = M.Metal,
			Color = Color3.fromRGB(90, 80, 60),
			Parent = wreck,
		})
		surfaceText(nameplate, Enum.NormalId.Right, "MERIDIAN", Color3.fromRGB(220, 200, 150), 30)
		local blink = deco({
			Name = "DeadBeacon",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.6, 0.6, 0.6),
			CFrame = cf * CFrame.new(0, 6, 1),
			Material = M.Neon,
			Color = Color3.fromRGB(255, 60, 40),
			Parent = wreck,
		})
		light(blink, 14, 1, Color3.fromRGB(255, 60, 40), false)
	end

	-- The bottom: whale skeleton, vents, the sealed door
	local bone = Color3.fromRGB(225, 220, 200)
	local skeleton = Instance.new("Model")
	skeleton.Name = "WhaleSkeleton"
	skeleton.Parent = well
	local sx, sz = -25, 20
	local sy = WorldBuilder.RealFloorY(sx, sz) + 2
	for i = 0, 13 do
		local z = sz - 30 + i * 4.5
		local s = 2.8 - i * 0.12
		deco({
			Name = "Spine",
			Size = Vector3.new(s, s, s * 1.3),
			CFrame = CFrame.new(sx, sy + 6 - math.abs(i - 5) * 0.35, z),
			Material = M.Limestone,
			Color = bone,
			Mesh = SPHERE,
			Parent = skeleton,
		})
		if i > 1 and i < 10 then
			for _, side in ipairs({ -1, 1 }) do
				deco({
					Name = "Rib",
					Size = Vector3.new(0.8, 11 - math.abs(i - 5), 0.8),
					CFrame = CFrame.new(sx + side * 3.5, sy + 2.2, z) * CFrame.Angles(0, 0, math.rad(side * 30)),
					Material = M.Limestone,
					Color = bone,
					Mesh = SPHERE,
					Parent = skeleton,
				})
			end
		end
	end
	deco({
		Name = "Skull",
		Size = Vector3.new(8, 4.5, 11),
		CFrame = CFrame.new(sx, sy + 3.5, sz - 37) * CFrame.Angles(0.2, 0, 0),
		Material = M.Limestone,
		Color = bone,
		Mesh = SPHERE,
		Parent = skeleton,
	})

	for i = 1, 5 do
		local a = i / 5 * TAU + 0.4
		local r = rng:NextNumber(30, 60)
		local x, z = math.cos(a) * r, math.sin(a) * r
		local y = WorldBuilder.RealFloorY(x, z)
		local vent = deco({
			Name = "Vent",
			Size = Vector3.new(4, 3, 4),
			CFrame = CFrame.new(x, y + 0.8, z),
			Material = M.Basalt,
			Color = Color3.fromRGB(40, 35, 35),
			Mesh = SPHERE,
			Parent = well,
		})
		local glow = deco({
			Name = "VentGlow",
			Size = Vector3.new(1.6, 0.6, 1.6),
			CFrame = CFrame.new(x, y + 2.2, z),
			Material = M.Neon,
			Color = Color3.fromRGB(255, 120, 40),
			Mesh = SPHERE,
			Parent = well,
		})
		light(glow, 18, 1.6, Color3.fromRGB(255, 120, 50), false)
		local att = Instance.new("Attachment")
		att.Position = Vector3.new(0, 1.5, 0)
		att.Parent = vent
		local bubbles = Instance.new("ParticleEmitter")
		bubbles.Texture = "rbxasset://textures/particles/smoke_main.dds"
		bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
		bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.4) })
		bubbles.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		bubbles.Speed = NumberRange.new(6, 10)
		bubbles.Lifetime = NumberRange.new(4, 6)
		bubbles.SpreadAngle = Vector2.new(8, 8)
		bubbles.Rate = 14
		bubbles.EmissionDirection = Enum.NormalId.Top
		bubbles.Parent = att
	end

	-- Sealed door set into the wall at the bottom
	local doorA = 4.7
	local doorPos, doorNormal = wallHit(doorA, FLOOR_DEPTH - 14)
	if doorPos then
		local cf = CFrame.lookAt(doorPos, doorPos + doorNormal) -- -Z faces into the Well
		local door = Instance.new("Model")
		door.Name = "SealedDoor"
		door.Parent = well
		local stone = Color3.fromRGB(70, 75, 90)
		part({
			Name = "Frame",
			Size = Vector3.new(36, 34, 6),
			CFrame = cf * CFrame.new(0, 2, 1),
			Material = M.Slate,
			Color = stone,
			Parent = door,
		})
		local slab = part({
			Name = "Door",
			Size = Vector3.new(26, 26, 2),
			CFrame = cf * CFrame.new(0, 1, -2.2),
			Material = M.CorrodedMetal,
			Color = Color3.fromRGB(55, 75, 85),
			Parent = door,
		})
		for i = 1, 3 do
			deco({
				Name = "Rune",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, 5 + i * 6, 5 + i * 6),
				CFrame = cf * CFrame.new(0, 1, -3.3) * CFrame.Angles(0, math.rad(90), 0),
				Material = M.Neon,
				Color = Color3.fromRGB(60, 150, 255),
				Transparency = 0.5 + i * 0.12,
				Parent = door,
			})
		end
		light(slab, 45, 2, Color3.fromRGB(70, 140, 255), false)
		surfaceText(
			slab,
			Enum.NormalId.Front,
			"SEALED\nThe Midnight Trench lies beyond...\n(coming in a future update)",
			Color3.fromRGB(150, 210, 255),
			20
		)
	end
end

------------------------------------------------------------------------
-- Lighting
------------------------------------------------------------------------
local function setupLighting(root)
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy() -- the client makes its own atmosphere that changes with depth
		end
	end
	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 8
	sky.Parent = Lighting
	Lighting.ClockTime = 15.2
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 2.6
	Lighting.GlobalShadows = true
	Lighting.Ambient = Color3.fromRGB(70, 80, 95)
	Lighting.OutdoorAmbient = Color3.fromRGB(130, 140, 155)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.FogEnd = 100000
	-- real volumetric clouds and swaying terrain grass
	pcall(function()
		local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.7
		clouds.Color = Color3.fromRGB(255, 255, 255)
		clouds.Parent = workspace.Terrain
	end)
	pcall(function()
		workspace.Terrain.Decoration = true
	end)

	_ = root
end

------------------------------------------------------------------------
-- Build everything
------------------------------------------------------------------------
function WorldBuilder.Build()
	for _, name in ipairs({ "Baseplate", "SpawnLocation" }) do
		local obj = workspace:FindFirstChild(name)
		if obj then
			obj:Destroy()
		end
	end

	local root = Instance.new("Folder")
	root.Name = "DeepDiveWorld"
	root.Parent = workspace

	setupLighting(root)
	buildTerrain()
	buildHarbor(root)
	buildWell(root)

	return WorldBuilder
end

return WorldBuilder
