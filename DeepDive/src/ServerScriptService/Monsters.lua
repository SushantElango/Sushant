--[[
	Monsters  (ModuleScript)
	LOCATION: ServerScriptService > Monsters

	Spawns and runs the sea monsters (all on the server).
	  Biter Fish  - fast little fish that RAM the hull (can cause leaks)
	  Jellyfish   - slow swarms that LATCH ON, drain health and slow you down
	  Eel         - packs that ram hard, then grab on and DRAG you off course

	To keep phones running smoothly, monsters only spawn near subs that are
	diving, and far-away ones are removed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("DeepDiveConfig"))

local S = Config.SURFACE_Y
local Monsters = {}

local ctx -- callbacks from GameServer
local folder
local active = {} -- list of monster objects
local rng = Random.new()
local nextId = 0

------------------------------------------------------------------------
-- Models
------------------------------------------------------------------------
local SPHERE = Enum.MeshType.Sphere

-- Makes one body part. Mesh = Sphere turns a box into a smooth ellipsoid.
local function mk(model, props)
	local p = Instance.new(props.Class or "Part")
	props.Class = nil
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local mesh = props.Mesh
	local pulse = props.Pulse
	props.Mesh = nil
	props.Pulse = nil
	for k, v in pairs(props) do
		p[k] = v
	end
	if mesh then
		local m = Instance.new("SpecialMesh")
		m.MeshType = mesh
		if pulse then
			m:SetAttribute("Pulse", true)
		end
		m.Parent = p
	end
	p.Parent = model
	return p
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- A moving joint. Clients read Amp/Freq/Phase/Axis and animate it
-- (tails swish, tentacles sway, eels slither).
local function joint(part0, part1, c0, c1, wave)
	local j = Instance.new("Motor6D")
	j.Part0 = part0
	j.Part1 = part1
	j.C0 = c0
	j.C1 = c1 or CFrame.new()
	if wave then
		j:SetAttribute("Amp", wave[1])
		j:SetAttribute("Freq", wave[2])
		j:SetAttribute("Phase", wave[3] or 0)
		j:SetAttribute("Axis", wave[4] or "Y")
	end
	part1.CFrame = part0.CFrame * j.C0 * j.C1:Inverse()
	j.Parent = part0
	return j
end

local function makeRoot(model, size)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false -- harpoons use Monsters.FindTarget instead
	root.Transparency = 1
	root.Size = size
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	return root
end

local function eyePair(model, body, x, y, z, size, irisColor, glow)
	for _, side in ipairs({ -1, 1 }) do
		local white = mk(model, {
			Name = "Eye",
			Size = Vector3.new(size * 0.7, size, size),
			CFrame = body.CFrame * CFrame.new(side * x, y, z),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(240, 235, 220),
			Mesh = SPHERE,
		})
		weld(body, white)
		local iris = mk(model, {
			Name = "Iris",
			Size = Vector3.new(size * 0.4, size * 0.62, size * 0.62),
			CFrame = body.CFrame * CFrame.new(side * (x + size * 0.2), y, z - size * 0.05),
			Material = glow and Enum.Material.Neon or Enum.Material.SmoothPlastic,
			Color = irisColor,
			Mesh = SPHERE,
		})
		weld(body, iris)
		local pupil = mk(model, {
			Name = "Pupil",
			Size = Vector3.new(size * 0.25, size * 0.45, size * 0.18),
			CFrame = body.CFrame * CFrame.new(side * (x + size * 0.32), y, z - size * 0.05),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(10, 10, 12),
			Mesh = SPHERE,
		})
		weld(body, pupil)
	end
end

local Builders = {}

-- Piranha-like biter: chunky body, big underbite full of teeth, swishing tail
function Builders.BiterFish()
	local model = Instance.new("Model")
	model.Name = "BiterFish"
	local root = makeRoot(model, Vector3.new(3, 3, 4))
	local body = mk(model, {
		Name = "Body",
		Size = Vector3.new(2.2, 2.9, 4),
		CFrame = CFrame.new(),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(200, 85, 45),
		Mesh = SPHERE,
	})
	weld(root, body)
	local back = mk(model, {
		Name = "Back",
		Size = Vector3.new(1.8, 1.6, 3.6),
		CFrame = CFrame.new(0, 0.72, 0.1),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(95, 60, 55),
		Mesh = SPHERE,
	})
	weld(body, back)
	local belly = mk(model, {
		Name = "Belly",
		Size = Vector3.new(1.9, 1.5, 3.2),
		CFrame = CFrame.new(0, -0.7, -0.15),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(255, 170, 110),
		Mesh = SPHERE,
	})
	weld(body, belly)
	-- jaw (underbite) + dark mouth
	local jaw = mk(model, {
		Name = "Jaw",
		Size = Vector3.new(1.7, 0.75, 1.6),
		CFrame = CFrame.new(0, -0.95, -1.45) * CFrame.Angles(0.3, 0, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(230, 120, 70),
		Mesh = SPHERE,
	})
	weld(body, jaw)
	local mouth = mk(model, {
		Name = "Mouth",
		Size = Vector3.new(1.2, 0.5, 0.5),
		CFrame = CFrame.new(0, -0.6, -1.85),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(60, 10, 15),
		Mesh = SPHERE,
	})
	weld(body, mouth)
	for i = -2, 2 do
		local up = mk(model, {
			Name = "Tooth",
			Size = Vector3.new(0.14, 0.38, 0.14),
			CFrame = CFrame.new(i * 0.22, -0.48, -1.98 + math.abs(i) * 0.08),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(250, 250, 240),
			Mesh = SPHERE,
		})
		weld(body, up)
		if i ~= 0 then
			local down = mk(model, {
				Name = "Tooth",
				Size = Vector3.new(0.14, 0.34, 0.14),
				CFrame = CFrame.new(i * 0.25, -0.82, -2.02 + math.abs(i) * 0.08),
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(250, 250, 240),
				Mesh = SPHERE,
			})
			weld(body, down)
		end
	end
	eyePair(model, body, 0.9, 0.45, -1.1, 0.7, Color3.fromRGB(255, 40, 30), true)
	-- fins
	for _, side in ipairs({ -1, 1 }) do
		local pec = mk(model, {
			Name = "PectoralFin",
			Size = Vector3.new(0.1, 0.8, 1.3),
			CFrame = CFrame.new(side * 1.15, -0.45, -0.1) * CFrame.Angles(0, side * 0.5, side * 0.7),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(255, 140, 70),
			Transparency = 0.25,
			Mesh = SPHERE,
		})
		weld(body, pec)
	end
	local dorsal = mk(model, {
		Name = "DorsalFin",
		Size = Vector3.new(0.12, 1.3, 2),
		CFrame = CFrame.new(0, 1.55, 0.5) * CFrame.Angles(-0.35, 0, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(150, 70, 50),
		Transparency = 0.15,
		Mesh = SPHERE,
	})
	weld(body, dorsal)
	-- tail on a joint so it swishes
	local stem = mk(model, {
		Name = "TailStem",
		Size = Vector3.new(0.8, 1.1, 1.3),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(190, 80, 45),
		Mesh = SPHERE,
	})
	joint(body, stem, CFrame.new(0, 0, 1.75), CFrame.new(0, 0, -0.4), { 0.45, 12, 0, "Y" })
	for _, side in ipairs({ -1, 1 }) do
		local lobe = mk(model, {
			Name = "TailFin",
			Size = Vector3.new(0.12, 1.6, 1.3),
			CFrame = stem.CFrame * CFrame.new(0, side * 0.55, 0.9) * CFrame.Angles(side * 0.6, 0, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(255, 130, 60),
			Transparency = 0.15,
			Mesh = SPHERE,
		})
		weld(stem, lobe)
	end
	return model, root
end

-- Jellyfish: see-through pulsing bell, glowing core, swaying tentacles
function Builders.Jellyfish()
	local model = Instance.new("Model")
	model.Name = "Jellyfish"
	local root = makeRoot(model, Vector3.new(3.6, 5, 3.6))
	local bell = mk(model, {
		Name = "Bell",
		Size = Vector3.new(3.6, 2.4, 3.6),
		CFrame = CFrame.new(0, 0.8, 0),
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(215, 140, 255),
		Transparency = 0.45,
		Mesh = SPHERE,
		Pulse = true,
	})
	weld(root, bell)
	local core = mk(model, {
		Name = "Core",
		Size = Vector3.new(1.6, 1, 1.6),
		CFrame = CFrame.new(0, 0.7, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 150, 230),
		Transparency = 0.25,
		Mesh = SPHERE,
		Pulse = true,
	})
	weld(bell, core)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local frill = mk(model, {
			Name = "Frill",
			Size = Vector3.new(0.6, 0.35, 0.6),
			CFrame = CFrame.new(math.cos(a) * 1.65, -0.25, math.sin(a) * 1.65),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 120, 210),
			Transparency = 0.35,
			Mesh = SPHERE,
		})
		weld(bell, frill)
	end
	local light = Instance.new("PointLight")
	light.Range = 11
	light.Brightness = 1.3
	light.Color = Color3.fromRGB(230, 140, 255)
	light.Parent = core
	-- tentacles: chains of 3 segments each
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + 0.3
		local prev = bell
		local c0 = CFrame.new(math.cos(a) * 1.2, -1.2, math.sin(a) * 1.2) * CFrame.new(0, 0, 0)
		for s = 1, 3 do
			local seg = mk(model, {
				Name = "Tentacle",
				Size = Vector3.new(0.16, 1.3, 0.16),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 170, 235),
				Transparency = 0.3 + s * 0.12,
				Mesh = SPHERE,
			})
			joint(prev, seg, c0, CFrame.new(0, 0.6, 0), { 0.28, 2.2, i * 1.1 + s * 0.7, (i % 2 == 0) and "X" or "Z" })
			prev = seg
			c0 = CFrame.new(0, -0.6, 0)
		end
	end
	-- two frilly oral arms in the middle
	for i = 0, 1 do
		local arm = mk(model, {
			Name = "OralArm",
			Size = Vector3.new(0.5, 2.6, 0.3),
			Material = Enum.Material.Glass,
			Color = Color3.fromRGB(255, 190, 240),
			Transparency = 0.3,
			Mesh = SPHERE,
		})
		joint(bell, arm, CFrame.new(i * 0.4 - 0.2, -1, 0), CFrame.new(0, 1.2, 0), { 0.18, 1.5, i * 2, "Z" })
	end
	return model, root
end

-- Moray eel: long slithering body made of jointed segments, open jaws
function Builders.Eel()
	local model = Instance.new("Model")
	model.Name = "Eel"
	local root = makeRoot(model, Vector3.new(2.4, 2.4, 4))
	local skin1 = Color3.fromRGB(70, 92, 48)
	local skin2 = Color3.fromRGB(110, 120, 55)
	local head = mk(model, {
		Name = "Head",
		Size = Vector3.new(1.5, 1.7, 2.8),
		CFrame = CFrame.new(),
		Material = Enum.Material.SmoothPlastic,
		Color = skin1,
		Mesh = SPHERE,
	})
	weld(root, head)
	local jaw = mk(model, {
		Name = "Jaw",
		Size = Vector3.new(1.2, 0.55, 2),
		CFrame = CFrame.new(0, -0.65, -0.55) * CFrame.Angles(0.35, 0, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(160, 160, 90),
		Mesh = SPHERE,
	})
	weld(head, jaw)
	local mouth = mk(model, {
		Name = "Mouth",
		Size = Vector3.new(0.95, 0.45, 1.6),
		CFrame = CFrame.new(0, -0.42, -0.75),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(90, 15, 20),
		Mesh = SPHERE,
	})
	weld(head, mouth)
	for i = 1, 4 do
		for _, side in ipairs({ -1, 1 }) do
			local tooth = mk(model, {
				Name = "Tooth",
				Size = Vector3.new(0.1, 0.32, 0.1),
				CFrame = CFrame.new(side * (0.42 - i * 0.04), -0.5, -1.4 + i * 0.28),
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(250, 250, 235),
				Mesh = SPHERE,
			})
			weld(head, tooth)
		end
	end
	eyePair(model, head, 0.55, 0.45, -0.75, 0.45, Color3.fromRGB(255, 230, 50), true)
	-- body segments, each on a joint, getting thinner towards the tail
	local prev = head
	local prevHalf = 1.2
	for i = 1, 8 do
		local w = 1.5 - i * 0.12
		local h = 1.7 - i * 0.14
		local seg = mk(model, {
			Name = "Segment",
			Size = Vector3.new(w, h, 2.3),
			Material = Enum.Material.SmoothPlastic,
			Color = (i % 2 == 0) and skin1 or skin2,
			Mesh = SPHERE,
		})
		joint(prev, seg, CFrame.new(0, 0, prevHalf), CFrame.new(0, 0, -0.95), { 0.32, 7, -i * 0.75, "Y" })
		local fin = mk(model, {
			Name = "Fin",
			Size = Vector3.new(0.1, h * 0.55, 2.2),
			CFrame = seg.CFrame * CFrame.new(0, h * 0.48, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(150, 160, 80),
			Transparency = 0.2,
			Mesh = SPHERE,
		})
		weld(seg, fin)
		-- a few glowing spots so eels show up in the dark
		if i % 3 == 1 then
			for _, side in ipairs({ -1, 1 }) do
				local spot = mk(model, {
					Name = "GlowSpot",
					Size = Vector3.new(0.15, 0.3, 0.3),
					CFrame = seg.CFrame * CFrame.new(side * w * 0.48, 0, 0),
					Material = Enum.Material.Neon,
					Color = Color3.fromRGB(120, 255, 200),
					Mesh = SPHERE,
				})
				weld(seg, spot)
			end
		end
		prev = seg
		prevHalf = 0.95
	end
	return model, root
end

local function addHealthBar(model, root)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromOffset(60, 8)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.Enabled = false
	gui.LightInfluence = 0
	gui.Adornee = root
	gui.Parent = model
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(30, 10, 10)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
	fill.BorderSizePixel = 0
	fill.Parent = back
	return fill
end

------------------------------------------------------------------------
-- Geometry helpers
------------------------------------------------------------------------
-- Closest point on the sub's centre line (it's a long capsule, not a ball).
local function closestOnSub(sub, point)
	local cf = sub.Root.CFrame
	local half = sub.HalfLength
	local a = cf.Position + cf.LookVector * half
	local b = cf.Position - cf.LookVector * half
	local ab = b - a
	local t = math.clamp((point - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return a + ab * t
end
Monsters.ClosestOnSub = closestOnSub

local function clampToWater(pos)
	local o = Config.Ocean
	local x = math.clamp(pos.X, o.MinX, o.MaxX)
	local z = math.clamp(pos.Z, o.MinZ, o.MaxZ)
	local floorY = ctx.FloorY(x, z) + 4
	local y = math.clamp(pos.Y, floorY, S - 8)
	return Vector3.new(x, y, z)
end

local function safeUnit(v)
	local mag = v.Magnitude
	if mag < 1e-4 then
		return Vector3.new(0, 1, 0)
	end
	return v / mag
end

local function zoneMult(depth)
	local zone = Config.GetZone(depth)
	local within = math.clamp((depth - zone.Min) / (zone.Max - zone.Min), 0, 1)
	return zone.MonsterMult * (1 + within * 0.25)
end

------------------------------------------------------------------------
-- Spawning / removal
------------------------------------------------------------------------
local function spawnMonster(kind, position, packId)
	local def = Config.Monsters[kind]
	local builder = Builders[kind]
	if not def or not builder then
		return
	end
	local model, root = builder()
	local depth = S - position.Y
	local mult = zoneMult(depth)
	nextId += 1
	local m = {
		Id = nextId,
		Kind = kind,
		Def = def,
		Model = model,
		Root = root,
		Pos = position,
		Vel = Vector3.zero,
		HP = math.floor(def.HP * mult),
		MaxHP = math.floor(def.HP * mult),
		Mult = mult,
		State = "Wander",
		Timer = 0,
		Home = position,
		Goal = position,
		PackId = packId,
		PackOffset = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-4, 4), rng:NextNumber(-6, 6)),
		Phase = rng:NextNumber(0, 10),
		FarTime = 0,
		DrainAcc = 0,
	}
	m.HealthFill = addHealthBar(model, root)
	model:SetAttribute("MonsterId", m.Id)
	model:SetAttribute("Kind", kind)
	model:PivotTo(CFrame.new(position))
	model:SetAttribute("CF", CFrame.new(position))
	model.Parent = folder
	table.insert(active, m)
	return m
end

local function removeMonster(m, popped)
	m.Dead = true
	if popped and m.Model.Parent then
		local fx = Instance.new("Part")
		fx.Anchored = true
		fx.CanCollide = false
		fx.CanQuery = false
		fx.Transparency = 1
		fx.Size = Vector3.new(1, 1, 1)
		fx.CFrame = CFrame.new(m.Pos)
		fx.Parent = folder
		local burst = Instance.new("ParticleEmitter")
		burst.Texture = "rbxasset://textures/particles/smoke_main.dds"
		burst.Color = ColorSequence.new(Color3.fromRGB(230, 245, 255))
		burst.Size = NumberSequence.new(0.6, 0)
		burst.Speed = NumberRange.new(6, 14)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Lifetime = NumberRange.new(0.6, 1.1)
		burst.Rate = 0
		burst.Parent = fx
		burst:Emit(30)
		Debris:AddItem(fx, 2)
	end
	m.Model:Destroy()
end

local function weightedPick(tbl)
	local total = 0
	for _, w in pairs(tbl) do
		total += w
	end
	local r = rng:NextNumber(0, total)
	for k, w in pairs(tbl) do
		r -= w
		if r <= 0 then
			return k
		end
	end
	return next(tbl)
end

local packCounter = 0
local function trySpawnNear(sub)
	local depth = sub.Depth
	if depth < Config.Spawning.MinDepth then
		return
	end
	local zone = Config.GetZone(depth)
	local zoneSpawn = Config.Spawning.Zones[zone.Name]
	if not zoneSpawn then
		return
	end
	local subPos = sub.Root.Position
	local nearby = 0
	for _, m in ipairs(active) do
		if not m.Dead and (m.Pos - subPos).Magnitude < 170 then
			nearby += 1
		end
	end
	local maxHere = zoneSpawn.MaxPerSub + math.max(0, sub.CrewCount - 1)
	if nearby >= maxHere or #active >= Config.Spawning.GlobalCap then
		return
	end
	local kind = weightedPick(zoneSpawn.Table)
	local def = Config.Monsters[kind]
	local count = rng:NextInteger(def.Group[1], def.Group[2])
	count = math.min(count, maxHere - nearby)
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist = rng:NextNumber(Config.Spawning.SpawnDistance[1], Config.Spawning.SpawnDistance[2])
	local center =
		clampToWater(subPos + Vector3.new(math.cos(angle) * dist, rng:NextNumber(-25, 25), math.sin(angle) * dist))
	-- don't spawn shallow monsters right under the dock
	if S - center.Y < Config.Spawning.MinDepth - 8 then
		return
	end
	packCounter += 1
	for _ = 1, count do
		local offset = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-4, 4), rng:NextNumber(-6, 6))
		spawnMonster(kind, clampToWater(center + offset), packCounter)
	end
end

------------------------------------------------------------------------
-- AI
------------------------------------------------------------------------
local function nearestSub(pos, subs, range)
	local best, bestDist
	for _, sub in ipairs(subs) do
		local d = (closestOnSub(sub, pos) - pos).Magnitude
		if d < range and (not bestDist or d < bestDist) then
			best, bestDist = sub, d
		end
	end
	return best, bestDist
end

local function startLatch(m, sub)
	local subCF = sub.Root.CFrame
	local onLine = closestOnSub(sub, m.Pos)
	local out = (m.Pos - onLine)
	if out.Magnitude < 0.1 then
		out = subCF.UpVector
	end
	local contact = onLine + out.Unit * (sub.Radius + m.Def.Radius * 0.6)
	m.LatchOffset = subCF:ToObjectSpace(CFrame.new(contact))
	m.LatchSub = sub
	m.State = "Latched"
	m.Timer = m.Def.LatchTime or 3
	if m.Def.Attack == "RamDrag" then
		local side = subCF.RightVector * (rng:NextNumber() < 0.5 and -1 or 1)
		m.DragVec = (side + Vector3.new(0, -0.3, 0)).Unit * (m.Def.DragSpeed or 8)
	end
end

local function stepMonster(m, dt, subs, now)
	local def = m.Def
	local speed = def.Speed
	local desired = Vector3.zero

	if m.State == "Latched" then
		local sub = m.LatchSub
		if not sub or sub.Destroyed or not sub.Root.Parent then
			m.State = "Wander"
			m.LatchSub = nil
			return
		end
		local cf = sub.Root.CFrame * m.LatchOffset
		m.Pos = cf.Position
		local center = closestOnSub(sub, m.Pos)
		m.CF = CFrame.lookAt(m.Pos, center) * CFrame.Angles(0, 0, math.sin(now * 8 + m.Phase) * 0.2)
		if def.Attack == "Latch" then
			m.DrainAcc += def.Drain * m.Mult * dt
			if m.DrainAcc >= 1 then
				local amount = math.floor(m.DrainAcc)
				m.DrainAcc -= amount
				ctx.DamageSub(sub, amount, 0, def.Name, true)
			end
		end
		m.Timer -= dt
		if m.Timer <= 0 then
			m.LatchSub = nil
			m.DragVec = nil
			m.State = "Retreat"
			m.Timer = def.Attack == "Latch" and 5 or 2.5
			m.Vel = safeUnit(m.Pos - center) * speed
		end
		return
	end

	local target, dist = nearestSub(m.Pos, subs, def.Aggro)
	if m.State == "Retreat" then
		m.Timer -= dt
		desired = m.Vel.Magnitude > 0 and m.Vel.Unit or Vector3.new(0, 1, 0)
		if m.Timer <= 0 then
			m.State = target and "Chase" or "Wander"
		end
	elseif target then
		m.State = "Chase"
		local aim = closestOnSub(target, m.Pos)
		if m.PackId and dist > 12 then
			aim += m.PackOffset
		end
		local toTarget = aim - m.Pos
		desired = toTarget.Magnitude > 0 and toTarget.Unit or Vector3.zero
		local hitDist = target.Radius + def.Radius
		if dist <= hitDist then
			if def.Attack == "Ram" then
				ctx.DamageSub(target, def.Damage * m.Mult, def.LeakChance, def.Name, false)
				m.State = "Retreat"
				m.Timer = 1.8
				m.Vel = safeUnit(m.Pos - aim) * speed + Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(2, 6), 0)
				return
			elseif def.Attack == "RamDrag" then
				ctx.DamageSub(target, def.Damage * m.Mult, def.LeakChance, def.Name, false)
				startLatch(m, target)
				return
			elseif def.Attack == "Latch" then
				startLatch(m, target)
				return
			end
		end
	else
		m.State = "Wander"
		speed = def.Speed * 0.35
		if (m.Goal - m.Pos).Magnitude < 4 or rng:NextNumber() < dt * 0.2 then
			m.Goal = clampToWater(
				m.Home + Vector3.new(rng:NextNumber(-30, 30), rng:NextNumber(-10, 10), rng:NextNumber(-30, 30))
			)
		end
		local to = m.Goal - m.Pos
		desired = to.Magnitude > 0 and to.Unit or Vector3.zero
	end

	-- Jellyfish just drift and bob
	if def.Attack == "Latch" and m.State ~= "Retreat" then
		desired += Vector3.new(0, math.sin(now * 1.5 + m.Phase) * 0.6, 0)
	end

	local targetVel = desired * speed
	m.Vel = m.Vel:Lerp(targetVel, math.clamp(dt * 3, 0, 1))
	m.Pos = clampToWater(m.Pos + m.Vel * dt)
	local look = m.Vel.Magnitude > 0.5 and m.Vel.Unit or Vector3.new(0, 0, -1)
	local wiggle = (def.Attack == "Latch") and 0 or math.sin(now * 3 + m.Phase) * 0.06
	if math.abs(look.Y) > 0.98 then
		m.CF = CFrame.new(m.Pos)
	else
		m.CF = CFrame.lookAt(m.Pos, m.Pos + look) * CFrame.Angles(0, wiggle, 0)
	end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
-- Called by the harpoon. Returns true if the monster died.
function Monsters.Damage(m, amount, player, sub)
	if m.Dead then
		return false
	end
	m.HP -= amount
	m.HealthFill.Size = UDim2.fromScale(math.clamp(m.HP / m.MaxHP, 0, 1), 1)
	m.HealthFill.Parent.Parent.Enabled = true
	-- a hit knocks latched monsters off and makes others angry
	if m.State == "Latched" and m.Def.Attack ~= "Latch" then
		m.State = "Retreat"
		m.Timer = 1.5
		m.LatchSub = nil
		m.DragVec = nil
	end
	if m.HP <= 0 then
		removeMonster(m, true)
		ctx.OnMonsterKilled(m, player, sub)
		return true
	end
	return false
end

-- Finds the best monster for a harpoon shot: inside a narrow cone first
-- (aim assist for phones), otherwise nil.
function Monsters.FindTarget(origin, direction, range, coneDegrees)
	local best, bestScore
	local cosLimit = math.cos(math.rad(coneDegrees))
	for _, m in ipairs(active) do
		if not m.Dead then
			local to = m.Pos - origin
			local dist = to.Magnitude
			if dist > 0.1 and dist <= range then
				local dot = to.Unit:Dot(direction)
				if dot >= cosLimit then
					local score = dot * 2 - dist / range
					if not bestScore or score > bestScore then
						best, bestScore = m, score
					end
				end
			end
		end
	end
	return best
end

function Monsters.FromModel(model)
	for _, m in ipairs(active) do
		if m.Model == model then
			return m
		end
	end
	return nil
end

-- Release everything latched onto a sub (used when it sinks or surfaces).
function Monsters.ReleaseSub(sub)
	for _, m in ipairs(active) do
		if m.LatchSub == sub then
			m.LatchSub = nil
			m.DragVec = nil
			m.State = "Retreat"
			m.Timer = 3
		end
	end
end

function Monsters.Folder()
	return folder
end

function Monsters.Init(context)
	ctx = context
	folder = Instance.new("Folder")
	folder.Name = "Monsters"
	folder.Parent = context.RootFolder

	local accumulator = 0
	local spawnTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		spawnTimer += dt
		if accumulator < 1 / 20 then
			return
		end
		local step = math.min(accumulator, 0.2)
		accumulator = 0
		local now = os.clock()
		local subs = ctx.GetDivingSubs()

		-- AI
		for _, m in ipairs(active) do
			if not m.Dead then
				local ok, err = pcall(stepMonster, m, step, subs, now)
				if not ok then
					warn("[DeepDive] monster error:", err)
					removeMonster(m, false)
				end
			end
		end

		-- Send positions to clients as attributes. The server never moves the
		-- parts itself; each client glides them smoothly (no choppy teleporting).
		for _, m in ipairs(active) do
			if not m.Dead then
				local model = m.Model
				if m.CF then
					model:SetAttribute("CF", m.CF)
				end
				if m.LatchSub and m.LatchSub.Owner then
					model:SetAttribute("LatchOwner", m.LatchSub.Owner.UserId)
					model:SetAttribute("LatchOffset", m.LatchOffset)
				else
					model:SetAttribute("LatchOwner", nil)
				end
			end
		end

		-- Sub effects from latched monsters (slow + drag), shown as attributes
		local effects = {}
		for _, m in ipairs(active) do
			if not m.Dead and m.LatchSub then
				local e = effects[m.LatchSub] or { Slow = 0, Drag = Vector3.zero }
				if m.Def.Slow then
					e.Slow = math.min(0.7, e.Slow + m.Def.Slow)
				end
				if m.DragVec then
					e.Drag += m.DragVec
				end
				effects[m.LatchSub] = e
			end
		end
		for _, sub in ipairs(ctx.GetAllSubs()) do
			local e = effects[sub]
			if sub.Model and sub.Model.Parent then
				sub.Model:SetAttribute("Slow", e and e.Slow or 0)
				sub.Model:SetAttribute("Drag", e and e.Drag or Vector3.zero)
			end
		end

		-- Despawn far monsters
		for i = #active, 1, -1 do
			local m = active[i]
			if m.Dead then
				table.remove(active, i)
			else
				local _, d = nearestSub(m.Pos, subs, Config.Spawning.DespawnDistance)
				if d then
					m.FarTime = 0
				else
					m.FarTime += step
					if m.FarTime > 8 then
						removeMonster(m, false)
						table.remove(active, i)
					end
				end
			end
		end

		-- Spawn near diving subs
		if spawnTimer >= Config.Spawning.CheckEvery then
			spawnTimer = 0
			for _, sub in ipairs(subs) do
				trySpawnNear(sub)
			end
		end
	end)
end

return Monsters
