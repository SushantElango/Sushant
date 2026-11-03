--[[
	WorldBuilder  (ModuleScript)
	LOCATION: ServerScriptService > WorldBuilder

	Builds the whole map with code when the server starts:
	  * the sea floor (Terrain): Sunlit Reef shelf, the Twilight Drop cliff,
	    the trench and the sealed door at the bottom
	  * the floating home dock with 8 berths, the shop hut, the depth
	    leaderboard and a lighthouse
	  * reef decorations: coral, kelp, a shipwreck, glowing crystals and a
	    whale skeleton

	You don't need to build anything by hand.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("DeepDiveConfig"))

local S = Config.SURFACE_Y
local WorldBuilder = {}

local rng = Random.new(1337) -- fixed seed = same map every server

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
		if k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

-- Decorations: no collisions, no raycasts, no shadows (cheap for phones).
local function deco(props)
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.CastShadow = false
	return part(props)
end

local function surfaceText(parent, face, text, textColor, bgColor, size)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = size or 40
	gui.LightInfluence = 0
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bgColor or Color3.fromRGB(20, 30, 50)
	label.BackgroundTransparency = bgColor and 0 or 1
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

------------------------------------------------------------------------
-- Sea floor shape. Returns depth in metres at (x, z).
-- Negative = above the water (land).
------------------------------------------------------------------------
function WorldBuilder.FloorDepth(x, z)
	local d
	if z < -190 then
		d = -4 -- the shore behind the dock
	elseif z < -150 then
		d = lerp(-4, 24, smooth((z + 190) / 40))
	elseif z < 300 then
		-- Sunlit Reef: gentle slope with bumpy reef hills
		d = lerp(24, 178, smooth((z + 150) / 450)) + math.noise(x / 85, z / 85, 1.7) * 16
		d = math.min(d, 194) -- always reachable by the starter Tin Can (210 m)
	elseif z < 400 then
		-- The Twilight Drop: a steep underwater cliff
		d = lerp(182, 512, smooth((z - 300) / 100))
	else
		-- Twilight floor + the trench that leads to the sealed door
		d = 522 + math.noise(x / 130, z / 130, 4.2) * 18
		local tx = x / 95
		local tz = (z - 720) / 140
		local r = tx * tx + tz * tz
		if r < 1 then
			d = d + 78 * (1 - r)
		end
		-- V1 stays inside the Twilight Drop; the sealed door leads deeper later
		d = math.min(d, 598)
	end
	-- Rock walls around the edge of the ocean
	local ex = 500 - math.abs(x)
	if ex < 70 then
		d = lerp(-14, d, smooth(ex / 70))
	end
	local ez = 910 - z
	if ez < 70 then
		d = lerp(-14, d, smooth(ez / 70))
	end
	return d
end

function WorldBuilder.FloorY(x, z)
	return S - WorldBuilder.FloorDepth(x, z)
end

-- Exact floor height by raycasting the terrain (use after the terrain is built).
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { workspace.Terrain }
function WorldBuilder.RealFloorY(x, z)
	local guess = WorldBuilder.FloorY(x, z)
	local result = workspace:Raycast(Vector3.new(x, guess + 40, z), Vector3.new(0, -90, 0), terrainParams)
	if result then
		return result.Position.Y
	end
	return guess
end

local function floorMaterial(d)
	if d < -1 then
		return Enum.Material.Grass
	elseif d < 4 then
		return Enum.Material.Sand
	elseif d < 196 then
		return Enum.Material.Sand
	elseif d < 480 then
		return Enum.Material.Rock
	elseif d < 560 then
		return Enum.Material.Slate
	else
		return Enum.Material.Basalt
	end
end

------------------------------------------------------------------------
-- Terrain
------------------------------------------------------------------------
local function buildTerrain()
	local terrain = workspace.Terrain
	terrain:Clear()
	local CELL = 20
	local count = 0
	for gx = -520, 520, CELL do
		for gz = -280, 940, CELL do
			local d = WorldBuilder.FloorDepth(gx, gz)
			-- fill each column down past its deepest neighbour so cliffs have no holes
			local deepest = d
			for _, off in ipairs({ { CELL, 0 }, { -CELL, 0 }, { 0, CELL }, { 0, -CELL } }) do
				deepest = math.max(deepest, WorldBuilder.FloorDepth(gx + off[1], gz + off[2]))
			end
			local top = S - d
			local bottom = S - deepest - 16
			local h = top - bottom
			terrain:FillBlock(
				CFrame.new(gx, bottom + h / 2, gz),
				Vector3.new(CELL, h, CELL),
				floorMaterial(math.max(d, (d + deepest) / 2))
			)
			-- round off the top so the floor looks natural
			terrain:FillBall(
				Vector3.new(gx + rng:NextNumber(-3, 3), top - 9, gz + rng:NextNumber(-3, 3)),
				rng:NextNumber(10.5, 12),
				floorMaterial(d)
			)
			count += 1
			if count % 150 == 0 then
				task.wait()
			end
		end
	end

	-- Boulders on the reef and in the twilight zone
	for _ = 1, 140 do
		local x = rng:NextNumber(-420, 420)
		local z = rng:NextNumber(-60, 290)
		local d = WorldBuilder.FloorDepth(x, z)
		terrain:FillBall(Vector3.new(x, S - d, z), rng:NextNumber(5, 12), Enum.Material.Rock)
	end
	for _ = 1, 90 do
		local x = rng:NextNumber(-420, 420)
		local z = rng:NextNumber(420, 840)
		local d = WorldBuilder.FloorDepth(x, z)
		terrain:FillBall(Vector3.new(x, S - d, z), rng:NextNumber(7, 18), Enum.Material.Basalt)
	end
	task.wait()
end

------------------------------------------------------------------------
-- Dock / home base
------------------------------------------------------------------------
local DOCK_TOP = S + 4
local BERTH_COUNT = 8

local function buildDock(root)
	local dock = Instance.new("Folder")
	dock.Name = "Dock"
	dock.Parent = root

	local wood = Color3.fromRGB(120, 85, 55)
	local darkWood = Color3.fromRGB(85, 58, 38)

	-- Main deck
	part({
		Name = "Deck",
		Size = Vector3.new(520, 2, 64),
		CFrame = CFrame.new(0, DOCK_TOP - 1, -162),
		Material = Enum.Material.WoodPlanks,
		Color = wood,
		Parent = dock,
	})
	-- Deck edge trim
	part({
		Name = "Trim",
		Size = Vector3.new(520, 1, 1),
		CFrame = CFrame.new(0, DOCK_TOP - 1.5, -130),
		Material = Enum.Material.Wood,
		Color = darkWood,
		Parent = dock,
	})
	-- Support pylons
	for x = -250, 250, 25 do
		for _, z in ipairs({ -132, -192 }) do
			local floorY = WorldBuilder.FloorY(x, z)
			local len = DOCK_TOP - floorY + 4
			deco({
				Name = "Pylon",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(len, 2.4, 2.4),
				CFrame = CFrame.new(x, DOCK_TOP - len / 2 - 1, z) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Wood,
				Color = darkWood,
				Parent = dock,
			})
		end
	end

	-- Spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "DockSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(0, DOCK_TOP + 0.5, -150)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Color = Color3.fromRGB(40, 180, 200)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = dock
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end

	-- Berths (one per player)
	local berths = {}
	for i = 1, BERTH_COUNT do
		local x = -245 + (i - 1) * 70
		local pier = part({
			Name = "Pier" .. i,
			Size = Vector3.new(7, 1.6, 40),
			CFrame = CFrame.new(x, DOCK_TOP - 0.8, -112),
			Material = Enum.Material.WoodPlanks,
			Color = wood,
			Parent = dock,
		})
		for _, z in ipairs({ -98, -112 }) do
			local floorY = WorldBuilder.FloorY(x, z)
			local len = DOCK_TOP - floorY + 3
			deco({
				Name = "PierPost",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(len, 1.6, 1.6),
				CFrame = CFrame.new(x + 3.2, DOCK_TOP - len / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Wood,
				Color = darkWood,
				Parent = dock,
			})
		end
		-- Bollard
		part({
			Name = "Bollard",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.6, 1.4, 1.4),
			CFrame = CFrame.new(x + 2.4, DOCK_TOP + 0.8, -96) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(60, 60, 70),
			Parent = dock,
		})
		-- Sign
		local post = part({
			Name = "SignPost",
			Size = Vector3.new(0.6, 6, 0.6),
			CFrame = CFrame.new(x - 3, DOCK_TOP + 3, -128),
			Material = Enum.Material.Wood,
			Color = darkWood,
			Parent = dock,
		})
		local board = part({
			Name = "BerthSign",
			Size = Vector3.new(8, 2.6, 0.4),
			CFrame = CFrame.new(x - 3, DOCK_TOP + 6.4, -128) * CFrame.Angles(0, math.pi, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(25, 40, 70),
			Parent = dock,
		})
		local label = surfaceText(board, Enum.NormalId.Front, "BERTH " .. i .. "\nfree", Color3.new(1, 1, 1), nil, 30)
		local label2 = surfaceText(board, Enum.NormalId.Back, "BERTH " .. i .. "\nfree", Color3.new(1, 1, 1), nil, 30)
		_ = post
		-- Glowing berth marker in the water
		local marker = deco({
			Name = "BerthGlow",
			Size = Vector3.new(14, 0.2, 30),
			CFrame = CFrame.new(x + 12, S + 0.15, -102),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(60, 200, 255),
			Transparency = 0.75,
			Parent = dock,
		})
		table.insert(berths, {
			Index = i,
			-- sub floats half in the water, nose pointing out to sea (+Z)
			SubCFrame = CFrame.new(x + 12, S + 0.5, -102) * CFrame.Angles(0, math.pi, 0),
			ExitCFrame = CFrame.new(x, DOCK_TOP + 3, -118),
			Labels = { label, label2 },
			Marker = marker,
			Pier = pier,
		})
	end
	WorldBuilder.Berths = berths

	-- Lamp posts
	for x = -240, 240, 40 do
		part({
			Name = "LampPost",
			Size = Vector3.new(0.5, 9, 0.5),
			CFrame = CFrame.new(x, DOCK_TOP + 4.5, -133),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(40, 40, 45),
			Parent = dock,
		})
		local bulb = deco({
			Name = "Lamp",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.4, 1.4, 1.4),
			CFrame = CFrame.new(x, DOCK_TOP + 9.4, -133),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 220, 150),
			Parent = dock,
		})
		local light = Instance.new("PointLight")
		light.Range = 18
		light.Brightness = 1.2
		light.Color = Color3.fromRGB(255, 220, 160)
		light.Parent = bulb
	end

	-- Crates and barrels
	for _ = 1, 26 do
		local x = rng:NextNumber(-250, 250)
		local z = rng:NextNumber(-188, -176)
		if math.abs(x) > 30 then
			if rng:NextNumber() < 0.5 then
				local s = rng:NextNumber(2.5, 4)
				part({
					Name = "Crate",
					Size = Vector3.new(s, s, s),
					CFrame = CFrame.new(x, DOCK_TOP + s / 2, z) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
					Material = Enum.Material.WoodPlanks,
					Color = Color3.fromRGB(160, 120, 70),
					Parent = dock,
				})
			else
				part({
					Name = "Barrel",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(3.2, 2.4, 2.4),
					CFrame = CFrame.new(x, DOCK_TOP + 1.6, z) * CFrame.Angles(0, 0, math.rad(90)),
					Material = Enum.Material.Metal,
					Color = rng:NextNumber() < 0.5 and Color3.fromRGB(180, 60, 40) or Color3.fromRGB(50, 110, 160),
					Parent = dock,
				})
			end
		end
	end

	-- Shop hut
	local hut = Instance.new("Model")
	hut.Name = "ShopHut"
	hut.Parent = dock
	local hx, hz = 0, -178
	part({
		Name = "Floor",
		Size = Vector3.new(26, 0.4, 18),
		CFrame = CFrame.new(hx, DOCK_TOP + 0.2, hz),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 110, 70),
		Parent = hut,
	})
	part({
		Name = "BackWall",
		Size = Vector3.new(26, 12, 1),
		CFrame = CFrame.new(hx, DOCK_TOP + 6, hz - 9),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(70, 130, 160),
		Parent = hut,
	})
	for _, side in ipairs({ -1, 1 }) do
		part({
			Name = "SideWall",
			Size = Vector3.new(1, 12, 18),
			CFrame = CFrame.new(hx + side * 13, DOCK_TOP + 6, hz),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(70, 130, 160),
			Parent = hut,
		})
	end
	part({
		Name = "Roof",
		Size = Vector3.new(30, 1, 22),
		CFrame = CFrame.new(hx, DOCK_TOP + 12.5, hz + 1) * CFrame.Angles(math.rad(-8), 0, 0),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(180, 60, 50),
		Parent = hut,
	})
	local counter = part({
		Name = "Counter",
		Size = Vector3.new(16, 3.5, 3),
		CFrame = CFrame.new(hx, DOCK_TOP + 1.75, hz + 4),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(110, 75, 45),
		Parent = hut,
	})
	local sign = part({
		Name = "ShopSign",
		Size = Vector3.new(22, 4, 0.5),
		CFrame = CFrame.new(hx, DOCK_TOP + 14.5, hz + 9.5),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(20, 30, 50),
		Parent = hut,
	})
	surfaceText(sign, Enum.NormalId.Back, "SALVAGE SHOP", Color3.fromRGB(255, 210, 80), nil, 30)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = "Salvage Shop"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	WorldBuilder.ShopPrompt = prompt
	-- Shopkeeper's lantern
	local lantern = deco({
		Name = "Lantern",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.5, 1.5, 1.5),
		CFrame = CFrame.new(hx, DOCK_TOP + 10, hz + 6),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 200, 120),
		Parent = hut,
	})
	local ll = Instance.new("PointLight")
	ll.Range = 20
	ll.Color = Color3.fromRGB(255, 210, 150)
	ll.Parent = lantern

	-- Depth leaderboard
	local boardPart = part({
		Name = "DepthBoard",
		Size = Vector3.new(18, 13, 0.6),
		CFrame = CFrame.new(-45, DOCK_TOP + 8, -186),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(15, 22, 40),
		Parent = dock,
	})
	for _, side in ipairs({ -1, 1 }) do
		part({
			Name = "BoardLeg",
			Size = Vector3.new(0.6, 8, 0.6),
			CFrame = CFrame.new(-45 + side * 8, DOCK_TOP + 1, -186),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(50, 50, 60),
			Parent = dock,
		})
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = boardPart
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.16, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(110, 220, 255)
	title.Text = "DEEPEST DIVES"
	title.Parent = gui
	local list = Instance.new("TextLabel")
	list.Name = "List"
	list.Position = UDim2.new(0.06, 0, 0.18, 0)
	list.Size = UDim2.new(0.88, 0, 0.78, 0)
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
	local welcome = part({
		Name = "WelcomeSign",
		Size = Vector3.new(18, 6, 0.5),
		CFrame = CFrame.new(45, DOCK_TOP + 8, -186),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(15, 22, 40),
		Parent = dock,
	})
	surfaceText(
		welcome,
		Enum.NormalId.Back,
		"DEEP DIVE\nBoard your sub - dive - salvage - SURFACE to cash in!",
		Color3.fromRGB(255, 230, 140),
		nil,
		30
	)

	-- Lighthouse on the shore
	local lx, lz = 300, -220
	local baseY = WorldBuilder.FloorY(lx, lz)
	for i = 0, 5 do
		part({
			Name = "Lighthouse",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(7, 9 - i * 0.6, 9 - i * 0.6),
			CFrame = CFrame.new(lx, baseY + 3.5 + i * 7, lz) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.SmoothPlastic,
			Color = (i % 2 == 0) and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(200, 40, 40),
			Parent = dock,
		})
	end
	local beacon = deco({
		Name = "LighthouseLamp",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5, 5, 5),
		CFrame = CFrame.new(lx, baseY + 45, lz),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 240, 170),
		Parent = dock,
	})
	local bl = Instance.new("PointLight")
	bl.Range = 50
	bl.Brightness = 2
	bl.Color = Color3.fromRGB(255, 235, 170)
	bl.Parent = beacon

	-- Buoys marking the dive area
	for i = 1, 10 do
		local x = -300 + (i - 1) * 66
		local b = deco({
			Name = "Buoy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3, 3, 3),
			CFrame = CFrame.new(x, S + 0.6, 40 + (i % 2) * 30),
			Material = Enum.Material.SmoothPlastic,
			Color = (i % 2 == 0) and Color3.fromRGB(255, 80, 60) or Color3.fromRGB(255, 255, 255),
			Parent = dock,
		})
		local top = deco({
			Name = "BuoyLight",
			Size = Vector3.new(0.6, 1.6, 0.6),
			CFrame = b.CFrame * CFrame.new(0, 2, 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 220, 100),
			Parent = dock,
		})
		_ = top
	end

	WorldBuilder.SpawnCFrame = CFrame.new(0, DOCK_TOP + 3, -150)
end

------------------------------------------------------------------------
-- Ocean decorations
------------------------------------------------------------------------
local CORAL_COLORS = {
	Color3.fromRGB(255, 100, 130),
	Color3.fromRGB(255, 150, 60),
	Color3.fromRGB(180, 90, 255),
	Color3.fromRGB(80, 220, 200),
	Color3.fromRGB(255, 220, 90),
	Color3.fromRGB(255, 80, 80),
}

local function buildReef(root)
	local reef = Instance.new("Folder")
	reef.Name = "Reef"
	reef.Parent = root

	-- Coral clusters
	for _ = 1, 150 do
		local x = rng:NextNumber(-420, 420)
		local z = rng:NextNumber(-90, 295)
		local fy = WorldBuilder.RealFloorY(x, z)
		local color = CORAL_COLORS[rng:NextInteger(1, #CORAL_COLORS)]
		local kind = rng:NextInteger(1, 3)
		if kind == 1 then
			-- branching coral
			for b = 1, rng:NextInteger(3, 5) do
				local h = rng:NextNumber(3, 7)
				deco({
					Name = "Coral",
					Size = Vector3.new(0.8, h, 0.8),
					CFrame = CFrame.new(x, fy + h / 2 - 0.5, z)
						* CFrame.Angles(rng:NextNumber(-0.5, 0.5), b * 1.3, rng:NextNumber(-0.5, 0.5)),
					Material = Enum.Material.SmoothPlastic,
					Color = color,
					Parent = reef,
				})
			end
		elseif kind == 2 then
			-- brain coral
			local s = rng:NextNumber(3, 6)
			deco({
				Name = "BrainCoral",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(s, s, s),
				CFrame = CFrame.new(x, fy + s * 0.25, z),
				Material = Enum.Material.Pebble,
				Color = color,
				Parent = reef,
			})
		else
			-- tube coral (some glow a little)
			for b = 1, rng:NextInteger(3, 6) do
				local h = rng:NextNumber(2, 5)
				deco({
					Name = "TubeCoral",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(h, 1.2, 1.2),
					CFrame = CFrame.new(x + rng:NextNumber(-2, 2), fy + h / 2 - 0.3, z + rng:NextNumber(-2, 2))
						* CFrame.Angles(0, 0, math.rad(90)),
					Material = (b == 1) and Enum.Material.Neon or Enum.Material.SmoothPlastic,
					Color = color,
					Parent = reef,
				})
			end
		end
	end

	-- Kelp forest
	for _ = 1, 90 do
		local x = rng:NextNumber(-420, 420)
		local z = rng:NextNumber(-60, 280)
		local fy = WorldBuilder.RealFloorY(x, z)
		local h = rng:NextNumber(14, 32)
		deco({
			Name = "Kelp",
			Size = Vector3.new(0.5, h, 1.6),
			CFrame = CFrame.new(x, fy + h / 2, z) * CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(0, 3), 0),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(60, rng:NextInteger(120, 160), 60),
			Transparency = 0.1,
			Parent = reef,
		})
	end

	-- Shipwreck on the reef
	local wx, wz = -190, 210
	local wy = WorldBuilder.RealFloorY(wx, wz)
	local ship = Instance.new("Model")
	ship.Name = "OldShipwreck"
	ship.Parent = reef
	local shipCF = CFrame.new(wx, wy + 4, wz) * CFrame.Angles(0, math.rad(30), math.rad(14))
	local shipWood = Color3.fromRGB(90, 65, 45)
	part({
		Name = "Keel",
		Size = Vector3.new(10, 3, 46),
		CFrame = shipCF,
		Material = Enum.Material.WoodPlanks,
		Color = shipWood,
		Parent = ship,
	})
	for _, side in ipairs({ -1, 1 }) do
		part({
			Name = "Side",
			Size = Vector3.new(1, 9, 44),
			CFrame = shipCF * CFrame.new(side * 6, 4, 0) * CFrame.Angles(0, 0, math.rad(side * 12)),
			Material = Enum.Material.WoodPlanks,
			Color = shipWood,
			Parent = ship,
		})
	end
	part({
		Name = "BrokenMast",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(26, 1.6, 1.6),
		CFrame = shipCF * CFrame.new(0, 12, -4) * CFrame.Angles(0.3, 0, math.rad(80)),
		Material = Enum.Material.Wood,
		Color = shipWood,
		Parent = ship,
	})
	part({
		Name = "Sail",
		Size = Vector3.new(0.3, 12, 14),
		CFrame = shipCF * CFrame.new(3, 14, -4) * CFrame.Angles(0.3, 0, math.rad(-10)),
		Material = Enum.Material.Fabric,
		Color = Color3.fromRGB(200, 190, 160),
		Transparency = 0.2,
		CanCollide = false,
		Parent = ship,
	})

	-- Twilight: glowing crystals (light sources in the dark)
	local crystalColors = { Color3.fromRGB(80, 240, 255), Color3.fromRGB(170, 100, 255), Color3.fromRGB(80, 255, 160) }
	for i = 1, 90 do
		local x = rng:NextNumber(-420, 420)
		local z = rng:NextNumber(380, 840)
		local fy = WorldBuilder.RealFloorY(x, z)
		local color = crystalColors[rng:NextInteger(1, #crystalColors)]
		local base
		for c = 1, rng:NextInteger(2, 4) do
			local h = rng:NextNumber(2, 6)
			local p = deco({
				Name = "Crystal",
				Size = Vector3.new(0.9, h, 0.9),
				CFrame = CFrame.new(x + rng:NextNumber(-1.5, 1.5), fy + h / 2 - 0.4, z + rng:NextNumber(-1.5, 1.5))
					* CFrame.Angles(rng:NextNumber(-0.5, 0.5), c, rng:NextNumber(-0.5, 0.5)),
				Material = Enum.Material.Neon,
				Color = color,
				Transparency = 0.15,
				Parent = reef,
			})
			base = base or p
		end
		if i % 3 == 0 and base then
			local l = Instance.new("PointLight")
			l.Range = 14
			l.Brightness = 1.4
			l.Color = color
			l.Parent = base
		end
	end

	-- Twilight: anemones that glow
	for _ = 1, 60 do
		local x = rng:NextNumber(-420, 420)
		local z = rng:NextNumber(410, 840)
		local fy = WorldBuilder.RealFloorY(x, z)
		deco({
			Name = "GlowAnemone",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.2, 2.2, 2.2),
			CFrame = CFrame.new(x, fy + 0.6, z),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 90, 200),
			Transparency = 0.3,
			Parent = reef,
		})
	end

	-- Twilight: giant whale skeleton
	local sx, sz = 170, 560
	local sy = WorldBuilder.RealFloorY(sx, sz) + 3
	local bone = Color3.fromRGB(225, 220, 200)
	local skeleton = Instance.new("Model")
	skeleton.Name = "WhaleSkeleton"
	skeleton.Parent = reef
	for i = 0, 13 do
		local z = sz - 35 + i * 5
		part({
			Name = "Spine",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3.2 - i * 0.12, 3.2 - i * 0.12, 3.2 - i * 0.12),
			CFrame = CFrame.new(sx, sy + 8 - math.abs(i - 5) * 0.4, z),
			Material = Enum.Material.Limestone,
			Color = bone,
			CanCollide = false,
			Parent = skeleton,
		})
		if i > 1 and i < 10 then
			for _, side in ipairs({ -1, 1 }) do
				part({
					Name = "Rib",
					Size = Vector3.new(0.9, 13 - math.abs(i - 5), 0.9),
					CFrame = CFrame.new(sx + side * 4, sy + 3, z) * CFrame.Angles(0, 0, math.rad(side * 28)),
					Material = Enum.Material.Limestone,
					Color = bone,
					CanCollide = false,
					Parent = skeleton,
				})
			end
		end
	end
	part({
		Name = "Skull",
		Size = Vector3.new(9, 5, 12),
		CFrame = CFrame.new(sx, sy + 5, sz - 44) * CFrame.Angles(0.2, 0, 0),
		Material = Enum.Material.Limestone,
		Color = bone,
		Parent = skeleton,
	})

	-- The sealed door at the bottom of the trench (future update teaser)
	local dx, dz = 0, 770
	local dy = WorldBuilder.RealFloorY(dx, dz)
	local door = Instance.new("Model")
	door.Name = "SealedDoor"
	door.Parent = reef
	local stone = Color3.fromRGB(70, 75, 90)
	part({
		Name = "FrameTop",
		Size = Vector3.new(46, 8, 8),
		CFrame = CFrame.new(dx, dy + 44, dz),
		Material = Enum.Material.Slate,
		Color = stone,
		Parent = door,
	})
	for _, side in ipairs({ -1, 1 }) do
		part({
			Name = "Pillar",
			Size = Vector3.new(8, 48, 8),
			CFrame = CFrame.new(dx + side * 19, dy + 20, dz),
			Material = Enum.Material.Slate,
			Color = stone,
			Parent = door,
		})
	end
	local slab = part({
		Name = "Door",
		Size = Vector3.new(30, 40, 3),
		CFrame = CFrame.new(dx, dy + 20, dz),
		Material = Enum.Material.CorrodedMetal,
		Color = Color3.fromRGB(60, 80, 90),
		Parent = door,
	})
	for i = 1, 3 do
		deco({
			Name = "Rune",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 6 + i * 6, 6 + i * 6),
			CFrame = CFrame.new(dx, dy + 22, dz - 1.6) * CFrame.Angles(0, math.rad(90), 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(60, 150, 255),
			Transparency = 0.55 + i * 0.1,
			Parent = door,
		})
	end
	local glow = Instance.new("PointLight")
	glow.Range = 45
	glow.Brightness = 2
	glow.Color = Color3.fromRGB(70, 140, 255)
	glow.Parent = slab
	surfaceText(
		slab,
		Enum.NormalId.Front,
		"SEALED\nThe Midnight Trench lies beyond...\n(coming in a future update)",
		Color3.fromRGB(150, 210, 255),
		nil,
		20
	)
end

------------------------------------------------------------------------
-- Water + lighting
------------------------------------------------------------------------
local function buildWater(root)
	local water = deco({
		Name = "WaterSurface",
		Size = Vector3.new(2048, 1, 2048),
		CFrame = CFrame.new(0, S, 340),
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(30, 130, 180),
		Transparency = 0.35,
		Reflectance = 0.05,
		Parent = root,
	})
	_ = water

	-- Invisible safety walls around the ocean (terrain walls are the real ones)
	local walls = {
		{ Vector3.new(20, 900, 1300), Vector3.new(-505, S - 400, 340) },
		{ Vector3.new(20, 900, 1300), Vector3.new(505, S - 400, 340) },
		{ Vector3.new(1050, 900, 20), Vector3.new(0, S - 400, 920) },
	}
	for _, w in ipairs(walls) do
		part({
			Name = "OceanWall",
			Size = w[1],
			CFrame = CFrame.new(w[2]),
			Transparency = 1,
			CanQuery = false,
			CastShadow = false,
			Parent = root,
		})
	end

	-- Lighting defaults (the client darkens this as you dive)
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere") then
			child:Destroy() -- Atmosphere overrides fog, which we use for the deep
		end
	end
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2
	Lighting.GlobalShadows = true
	Lighting.Ambient = Color3.fromRGB(70, 80, 95)
	Lighting.OutdoorAmbient = Color3.fromRGB(130, 140, 150)
	Lighting.FogEnd = 100000
end

------------------------------------------------------------------------
-- Build everything
------------------------------------------------------------------------
function WorldBuilder.Build()
	-- Remove the default baseplate / spawn from the template place
	for _, name in ipairs({ "Baseplate", "SpawnLocation" }) do
		local obj = workspace:FindFirstChild(name)
		if obj then
			obj:Destroy()
		end
	end

	local root = Instance.new("Folder")
	root.Name = "DeepDiveWorld"
	root.Parent = workspace

	buildWater(root)
	buildDock(root)
	buildTerrain()
	buildReef(root)

	return WorldBuilder
end

return WorldBuilder
