--[[
	DEEP DIVE - SERVER SCRIPT
	=========================
	WHERE: Explorer > ServerScriptService > (+) Script   (a normal Script)
	Paste this WHOLE file into it. Also make the LocalScript from
	DeepDive_Client.lua (StarterPlayer > StarterPlayerScripts).

	All game settings (prices, health, speeds, loot...) are in the
	"CONFIG" section right below. Search for "Config." to find a setting.
]]

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local DeepDiveConfig = (function()
--[[
	DeepDiveConfig  (ModuleScript)
	LOCATION: ReplicatedStorage > DeepDiveConfig

	This is the ONE file for balancing the game. Prices, part stats, zones,
	monsters and loot all live here. Both the server and the client read it.
	Change a number here and it changes everywhere.
]]

local Config = {}

Config.GameName = "Deep Dive"
Config.Version = "1.0"

------------------------------------------------------------------------
-- WORLD
------------------------------------------------------------------------
-- The sea surface sits high in the sky so the deep ocean never reaches
-- Roblox's "fallen parts" kill height. 1 stud = 1 metre of depth.
Config.SURFACE_Y = 1000
Config.SurfaceDepth = 6 -- shallower than this counts as "surfaced"

Config.Zones = {
	{
		Name = "Sunlit Reef",
		Min = 0,
		Max = 200,
		Color = Color3.fromRGB(95, 215, 255),
		MonsterMult = 1.0,
	},
	{
		Name = "Twilight Drop",
		Min = 200,
		Max = 600,
		Color = Color3.fromRGB(110, 120, 255),
		MonsterMult = 1.5,
	},
	{
		Name = "Midnight Trench",
		Min = 600,
		Max = 1500,
		Color = Color3.fromRGB(150, 70, 200),
		MonsterMult = 2.2,
		Locked = true,
	},
}

function Config.GetZone(depth)
	for i, zone in ipairs(Config.Zones) do
		if depth < zone.Max then
			return zone, i
		end
	end
	return Config.Zones[#Config.Zones], #Config.Zones
end

------------------------------------------------------------------------
-- SUB PARTS / UPGRADES  (level 1 is what every new player starts with)
------------------------------------------------------------------------
Config.Upgrades = {}

Config.Upgrades.Hull = {
	DisplayName = "Hull",
	Description = "Health and how deep you can dive.",
	Levels = {
		{
			Name = "Tin Can",
			Cost = 0,
			MaxHP = 100,
			MaxDepth = 210,
			Oxygen = 150,
			Length = 12,
			Diameter = 7,
			Seats = { "Helm", "Turret" },
			Material = Enum.Material.SmoothPlastic,
		},
		{
			Name = "Steel",
			Cost = 1200,
			MaxHP = 220,
			MaxDepth = 620,
			Oxygen = 240,
			Length = 16,
			Diameter = 8.5,
			Seats = { "Helm", "Turret", "Sonar", "Repair" },
			Material = Enum.Material.Metal,
		},
		{
			Name = "Titanium",
			Cost = 8000,
			MaxHP = 420,
			MaxDepth = 1500,
			Oxygen = 360,
			Length = 19,
			Diameter = 9.5,
			Seats = { "Helm", "Turret", "Sonar", "Repair" },
			Material = Enum.Material.DiamondPlate,
		},
		{
			Name = "Abyssal Alloy",
			Cost = 0,
			ComingSoon = true,
		},
	},
}

Config.Upgrades.Engine = {
	DisplayName = "Engine",
	Description = "Speed and turning.",
	Levels = {
		{ Name = "1 Star", Cost = 0, Speed = 16, Turn = 0.9 },
		{ Name = "2 Stars", Cost = 120, Speed = 20, Turn = 1.05 },
		{ Name = "3 Stars", Cost = 380, Speed = 24, Turn = 1.2 },
		{ Name = "4 Stars", Cost = 850, Speed = 28, Turn = 1.35 },
		{ Name = "5 Stars", Cost = 1800, Speed = 33, Turn = 1.5 },
	},
}

Config.Upgrades.Lights = {
	DisplayName = "Lights",
	Description = "How far you can see in the dark.",
	Levels = {
		-- SpotLight range is capped at 60 by Roblox. FogBonus = extra view distance.
		{ Name = "Lamp", Cost = 0, Range = 32, Angle = 50, Brightness = 3, FogBonus = 0 },
		{ Name = "Floodlight", Cost = 300, Range = 46, Angle = 65, Brightness = 4, FogBonus = 25 },
		{ Name = "Sonar Beam", Cost = 950, Range = 60, Angle = 80, Brightness = 5, FogBonus = 55 },
	},
}

Config.Upgrades.Cargo = {
	DisplayName = "Cargo Hold",
	Description = "How much loot you can carry home.",
	Levels = {
		{ Name = "Crate", Cost = 0, Slots = 8 },
		{ Name = "Small Hold", Cost = 100, Slots = 12 },
		{ Name = "Hold", Cost = 320, Slots = 16 },
		{ Name = "Big Hold", Cost = 750, Slots = 22 },
		{ Name = "Mega Hold", Cost = 1600, Slots = 30 },
	},
}

Config.Upgrades.Plating = {
	DisplayName = "Hull Plating",
	Description = "Armor: less damage, more health, fewer leaks.",
	Levels = {
		{ Name = "None", Cost = 0, Armor = 0, BonusHP = 0, LeakResist = 0 },
		{ Name = "Bolted Plates", Cost = 150, Armor = 0.15, BonusHP = 20, LeakResist = 0.15 },
		{ Name = "Riveted Armor", Cost = 520, Armor = 0.28, BonusHP = 45, LeakResist = 0.3 },
		{ Name = "Reinforced Shell", Cost = 1250, Armor = 0.4, BonusHP = 80, LeakResist = 0.45 },
	},
}

Config.Upgrades.Harpoon = {
	DisplayName = "Harpoon Turret",
	Description = "Shoot monsters. Click (or tap FIRE) to shoot.",
	Levels = {
		{ Name = "No Turret", Cost = 0, Damage = 0, Cooldown = 1 },
		{ Name = "Harpoon Mk I", Cost = 100, Damage = 14, Cooldown = 0.9, Range = 110 },
		{ Name = "Harpoon Mk II", Cost = 420, Damage = 22, Cooldown = 0.7, Range = 125 },
		{ Name = "Harpoon Mk III", Cost = 1050, Damage = 34, Cooldown = 0.5, Range = 140 },
	},
}

Config.UpgradeOrder = { "Hull", "Engine", "Lights", "Cargo", "Plating", "Harpoon" }

------------------------------------------------------------------------
-- SUPPLIES (consumables)
------------------------------------------------------------------------
Config.Supplies = {
	RepairKit = {
		DisplayName = "Repair Kit",
		Description = "Restores 40% hull and patches 2 leaks. Press 1.",
		Cost = 40,
		Max = 10,
		Heal = 0.4,
		Key = "One",
	},
	OxygenTank = {
		DisplayName = "Oxygen Tank",
		Description = "Adds 60 seconds of air. Press 2.",
		Cost = 30,
		Max = 10,
		Seconds = 60,
		Key = "Two",
	},
}
Config.SupplyOrder = { "RepairKit", "OxygenTank" }

------------------------------------------------------------------------
-- COSMETICS (earnable with coins)
------------------------------------------------------------------------
Config.Paints = {
	{ Id = "Sunshine", Name = "Sunshine", Color = Color3.fromRGB(255, 200, 40), Cost = 0 },
	{ Id = "Navy", Name = "Navy", Color = Color3.fromRGB(40, 60, 120), Cost = 0 },
	{ Id = "Crimson", Name = "Crimson", Color = Color3.fromRGB(190, 35, 45), Cost = 60 },
	{ Id = "Mint", Name = "Mint", Color = Color3.fromRGB(110, 230, 170), Cost = 60 },
	{ Id = "Coral", Name = "Coral", Color = Color3.fromRGB(255, 120, 100), Cost = 150 },
	{ Id = "Orca", Name = "Orca", Color = Color3.fromRGB(25, 25, 30), Cost = 250 },
	{ Id = "Bubblegum", Name = "Bubblegum", Color = Color3.fromRGB(255, 130, 200), Cost = 300 },
	{ Id = "Gold", Name = "Gold Rush", Color = Color3.fromRGB(240, 180, 30), Cost = 1500, Shiny = true },
}

Config.LightColors = {
	{ Id = "Warm", Name = "Warm White", Color = Color3.fromRGB(255, 240, 210), Cost = 0 },
	{ Id = "Aqua", Name = "Aqua", Color = Color3.fromRGB(120, 255, 240), Cost = 80 },
	{ Id = "Amber", Name = "Amber", Color = Color3.fromRGB(255, 180, 80), Cost = 80 },
	{ Id = "Violet", Name = "Violet", Color = Color3.fromRGB(190, 130, 255), Cost = 200 },
	{ Id = "Lime", Name = "Toxic Lime", Color = Color3.fromRGB(170, 255, 90), Cost = 200 },
}

function Config.FindPaint(id)
	for _, p in ipairs(Config.Paints) do
		if p.Id == id then
			return p
		end
	end
	return Config.Paints[1]
end

function Config.FindLightColor(id)
	for _, p in ipairs(Config.LightColors) do
		if p.Id == id then
			return p
		end
	end
	return Config.LightColors[1]
end

------------------------------------------------------------------------
-- DAMAGE, LEAKS, OXYGEN
------------------------------------------------------------------------
Config.Damage = {
	LeakDPS = 1.2, -- hull damage per second for each open leak
	MaxLeaks = 6,
	CrushBaseDPS = 4, -- damage per second when deeper than your hull rating
	CrushPerMetre = 0.15, -- extra damage per metre past the rating
	NoOxygenDPS = 8,
	SoloDamageMult = 0.7, -- solo subs take less damage so solo stays fair
	SoloAutoRepairEvery = 7, -- solo auto-repair kit patches a leak every N seconds
	SurfaceRepairPerSecond = 25, -- free repairs while floating at the surface
	PatchTimeRepairStation = 1.2, -- seconds to patch a leak from the Repair seat
	PatchTimeOtherStation = 3.0, -- seconds to patch from any other seat
}

Config.Sink = {
	InsurancePercent = 0.1, -- if your sub is destroyed you keep 10% of the haul
	RespawnTime = 4,
}

Config.Crew = {
	BonusPerExtraMember = 0.15, -- +15% loot for each extra crew member
	MaxBonus = 0.45,
}

------------------------------------------------------------------------
-- SONAR
------------------------------------------------------------------------
Config.Sonar = {
	Radius = 150,
	CooldownSonarStation = 6,
	CooldownOtherStation = 15,
	MarkerTime = 6,
}

------------------------------------------------------------------------
-- LOOT
------------------------------------------------------------------------
Config.Loot = {
	PickupRange = 4, -- studs beyond the hull
	RespawnMin = 20,
	RespawnMax = 45,
	SpawnCount = {
		["Sunlit Reef"] = 42,
		["Twilight Drop"] = 45,
	},
	Types = {
		Scrap = {
			Name = "Scrap Metal",
			Value = 6,
			Zone = "Sunlit Reef",
			Weight = 50,
			Look = "Scrap",
			Color = Color3.fromRGB(150, 150, 160),
		},
		Shell = {
			Name = "Pretty Shell",
			Value = 10,
			Zone = "Sunlit Reef",
			Weight = 36,
			Look = "Shell",
			Color = Color3.fromRGB(255, 170, 200),
		},
		SunkenChest = {
			Name = "Sunken Chest",
			Value = 90,
			Zone = "Sunlit Reef",
			Weight = 4,
			Look = "Chest",
			Color = Color3.fromRGB(255, 210, 70),
		},
		Pearl = {
			Name = "Pearl",
			Value = 30,
			Zone = "Twilight Drop",
			Weight = 46,
			Look = "Pearl",
			Color = Color3.fromRGB(235, 245, 255),
		},
		OldCoins = {
			Name = "Old Coins",
			Value = 45,
			Zone = "Twilight Drop",
			Weight = 34,
			Look = "Coins",
			Color = Color3.fromRGB(255, 200, 60),
		},
		GoldenIdol = {
			Name = "Golden Idol",
			Value = 220,
			Zone = "Twilight Drop",
			Weight = 4,
			Look = "Idol",
			Color = Color3.fromRGB(255, 215, 0),
		},
		SignalCrate = {
			Name = "Expedition Crate",
			Value = 0, -- set when the distress signal spawns
			Zone = nil,
			Weight = 0,
			Look = "Crate",
			Color = Color3.fromRGB(80, 255, 230),
		},
	},
}

------------------------------------------------------------------------
-- MYSTERY SIGNALS (random wrecks with rare loot)
------------------------------------------------------------------------
Config.Signals = {
	MinInterval = 120,
	MaxInterval = 210,
	MaxActive = 2,
	Lifetime = 240,
	Value = {
		["Sunlit Reef"] = { 140, 260 },
		["Twilight Drop"] = { 400, 750 },
	},
}

------------------------------------------------------------------------
-- MONSTERS
------------------------------------------------------------------------
Config.Monsters = {
	BiterFish = {
		Name = "Biter Fish",
		HP = 20,
		Speed = 22,
		Damage = 5,
		LeakChance = 0.25,
		Attack = "Ram",
		Aggro = 60,
		Radius = 1.6,
		Bounty = 6,
		Group = { 1, 3 },
	},
	Jellyfish = {
		Name = "Jellyfish",
		HP = 12,
		Speed = 7,
		Drain = 3, -- damage per second while latched on
		Slow = 0.3, -- slows the sub while latched
		LatchTime = 6,
		LeakChance = 0,
		Attack = "Latch",
		Aggro = 40,
		Radius = 1.8,
		Bounty = 4,
		Group = { 3, 6 },
	},
	Eel = {
		Name = "Eel",
		HP = 36,
		Speed = 30,
		Damage = 10,
		LeakChance = 0.6,
		Attack = "RamDrag",
		DragSpeed = 9, -- drags the sub off course
		LatchTime = 2.5,
		Aggro = 95,
		Radius = 2,
		Bounty = 14,
		Group = { 2, 3 },
	},
}

-- Which monsters appear in each zone, and how often (weights).
Config.Spawning = {
	CheckEvery = 2.5,
	GlobalCap = 40,
	MinDepth = 40, -- no monsters this close to the surface
	SpawnDistance = { 45, 75 }, -- above/below the sub, inside the Well
	DespawnDistance = 260,
	Zones = {
		["Sunlit Reef"] = {
			MaxPerSub = 4,
			Table = { BiterFish = 70, Jellyfish = 30 },
		},
		["Twilight Drop"] = {
			MaxPerSub = 6,
			Table = { BiterFish = 25, Jellyfish = 30, Eel = 45 },
		},
		["Midnight Trench"] = {
			MaxPerSub = 7,
			Table = { Eel = 60, Jellyfish = 40 },
		},
	},
}

------------------------------------------------------------------------
-- DAILY CHEST
------------------------------------------------------------------------
Config.Daily = {
	BaseCoins = 25,
	PerStreakDay = 25,
	MaxCoins = 250,
	RepairKitEvery = 3, -- bonus repair kit every 3rd day of a streak
}

------------------------------------------------------------------------
-- MONETIZATION
-- Make the passes / products on the Roblox Creator Dashboard, then paste
-- their IDs here. Anything left at 0 is hidden in the shop.
-- Golden rule: Robux saves time or adds style, never buys power free
-- players can't reach.
------------------------------------------------------------------------
Config.Monetization = {
	VIPPassId = 0, -- "VIP Captain": +3 cargo slots, gold name, [VIP] chat tag
	Products = {
		{ Key = "Coins500", Id = 0, Name = "500 Coins", Coins = 500 },
		{ Key = "Coins2000", Id = 0, Name = "2,000 Coins", Coins = 2000 },
		{ Key = "Coins6000", Id = 0, Name = "6,000 Coins", Coins = 6000 },
		{ Key = "LootBoost", Id = 0, Name = "2x Loot (30 min)", BoostMinutes = 30 },
		{ Key = "EmergencySurface", Id = 0, Name = "Emergency Surface", Emergency = true },
	},
	VIPCargoBonus = 3,
}

------------------------------------------------------------------------
-- LORE (logs from the lost expedition, found in distress-signal wrecks)
------------------------------------------------------------------------
Config.Lore = {
	{
		Title = "Log 1 - The Meridian",
		Text = "Day 1. The research sub Meridian launched at dawn. Captain Ines says the sonar picked up something under the Twilight Drop. Something big. We're going to find out what.",
	},
	{
		Title = "Log 2 - Lights",
		Text = "Day 4. We saw lights below us tonight. Not ours. They blinked in a pattern, like they were talking. Rafi thinks it was anglerfish. Rafi is wrong.",
	},
	{
		Title = "Log 3 - The Door",
		Text = "Day 9. At the bottom of the trench there is a door. A real door, carved stone and metal. Who builds a door 600 metres under the sea?",
	},
	{
		Title = "Log 4 - Scratches",
		Text = "Day 12. Something has been scratching the hull at night. The eels are getting bolder. We patched three leaks today. Ines won't turn back.",
	},
	{
		Title = "Log 5 - The Song",
		Text = "Day 15. The hydrophone picked up a sound from behind the door. Low and slow, like a whale but... bigger. The crew calls it the Leviathan's song.",
	},
	{
		Title = "Log 6 - Last Entry",
		Text = "Day 16. The door is opening. Whatever is down there knows we're here. If anyone finds this: build a stronger hull. Bring friends. Don't come alone.",
	},
}

------------------------------------------------------------------------
-- SOUNDS  (built-in Roblox sounds; swap for Creator Store IDs anytime)
------------------------------------------------------------------------
Config.Sounds = {
	Ping = "rbxasset://sounds/electronicpingshort.wav", -- sonar
	Harpoon = "rbxasset://sounds/swoosh.wav",
	Hit = "rbxasset://sounds/collide.wav",
	Coin = "rbxasset://sounds/electronicpingshort.wav",
	Click = "rbxasset://sounds/electronicpingshort.wav",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Engine = "rbxasset://sounds/Rocket whoosh 01.wav", -- looped low = engine hum
	Alarm = "rbxasset://sounds/electronicpingshort.wav",
	Creak = "rbxasset://sounds/collide.wav",
}

------------------------------------------------------------------------
-- MUSIC
-- Paste audio IDs here (Toolbox > Audio, or Creator Store > Audio, pick a
-- track, copy the number in its link). Example: "rbxassetid://1234567890"
-- OR put Sound objects named "SurfaceMusic" and "DeepMusic" inside the
-- ReplicatedStorage > DeepDiveModels folder. Leave "" for no music.
------------------------------------------------------------------------
Config.Music = {
	Surface = "", -- calm theme on the dock / at the surface
	Deep = "", -- intense track while diving
	Volume = 0.4,
	FadeTime = 2,
}

------------------------------------------------------------------------
-- CUSTOM 3D MODELS
-- Drop real models (Toolbox / Creator Store, or your own from Blender)
-- into a folder:  ReplicatedStorage > DeepDiveModels
-- and name them exactly like the keys below. The game swaps them in for
-- the built-in shapes automatically and scales them to fit.
-- If a model faces the wrong way, change its Yaw (degrees: 90, 180, -90).
------------------------------------------------------------------------
Config.CustomModels = {
	Submarine = { Yaw = 0 }, -- your sub (its front should point the way the sub drives)
	BiterFish = { Yaw = 0, Length = 4.5 },
	Jellyfish = { Yaw = 0, Length = 4 },
	Eel = { Yaw = 0, Length = 16 },
	Shop = { Yaw = 0, Size = 28 },
	Warehouse = { Yaw = 0, Size = 40 },
	House = { Yaw = 0, Size = 22 }, -- placed around the island
	Lighthouse = { Yaw = 0, Size = 14 },
	PalmTree = { Yaw = 0, Size = 16 },
	Crane = { Yaw = 0, Size = 34 },
	Boat = { Yaw = 0, Size = 40 }, -- boats anchored out at sea
}

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
-- Computes the live sub stats from a player's saved upgrades.
function Config.ComputeStats(upgrades, isVIP)
	local hull = Config.Upgrades.Hull.Levels[upgrades.Hull] or Config.Upgrades.Hull.Levels[1]
	local engine = Config.Upgrades.Engine.Levels[upgrades.Engine] or Config.Upgrades.Engine.Levels[1]
	local lights = Config.Upgrades.Lights.Levels[upgrades.Lights] or Config.Upgrades.Lights.Levels[1]
	local cargo = Config.Upgrades.Cargo.Levels[upgrades.Cargo] or Config.Upgrades.Cargo.Levels[1]
	local plating = Config.Upgrades.Plating.Levels[upgrades.Plating] or Config.Upgrades.Plating.Levels[1]
	local harpoon = Config.Upgrades.Harpoon.Levels[upgrades.Harpoon] or Config.Upgrades.Harpoon.Levels[1]
	return {
		HullName = hull.Name,
		MaxHP = hull.MaxHP + plating.BonusHP,
		MaxDepth = hull.MaxDepth,
		MaxOxygen = hull.Oxygen,
		Speed = engine.Speed,
		Turn = engine.Turn,
		LightRange = lights.Range,
		LightAngle = lights.Angle,
		LightBrightness = lights.Brightness,
		FogBonus = lights.FogBonus,
		CargoMax = cargo.Slots + (isVIP and Config.Monetization.VIPCargoBonus or 0),
		Armor = plating.Armor,
		LeakResist = plating.LeakResist,
		HarpoonLevel = upgrades.Harpoon,
		HarpoonDamage = harpoon.Damage,
		HarpoonCooldown = harpoon.Cooldown,
		HarpoonRange = harpoon.Range or 0,
	}
end

function Config.FormatNumber(n)
	n = math.floor(n + 0.5)
	local s = tostring(math.abs(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return (n < 0 and "-" or "") .. formatted
end

-- Finds a custom model in ReplicatedStorage > DeepDiveModels (or nil).
function Config.GetCustomModel(name)
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("DeepDiveModels")
	local m = folder and folder:FindFirstChild(name)
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

-- Clones a custom model, removes its scripts, scales it to `targetSize`
-- studs and centres it on `cf`. Server only.
--   opts.Ground  = put the bottom of the model at cf's height (buildings)
--   opts.AllAxes = measure length/height too, not just the footprint (creatures, subs)
--   opts.WeldTo  = weld it to this part instead of anchoring (moving things)
function Config.PlaceCustomModel(name, cf, targetSize, opts)
	local template = Config.GetCustomModel(name)
	if not template then
		return nil
	end
	opts = opts or {}
	local settings = Config.CustomModels[name] or {}
	local m = template:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") or d:IsA("Humanoid") or d:IsA("AnimationController") then
			d:Destroy()
		elseif d:IsA("Seat") or d:IsA("VehicleSeat") then
			d.Disabled = true
		end
	end
	local _, size = m:GetBoundingBox()
	local biggest = math.max(size.X, size.Z)
	if opts.AllAxes then
		biggest = math.max(biggest, size.Y)
	end
	if biggest > 0 and targetSize then
		pcall(function()
			m:ScaleTo(m:GetScale() * targetSize / biggest)
		end)
	end
	local boxCF, box = m:GetBoundingBox()
	local offset = boxCF:ToObjectSpace(m:GetPivot())
	local placeCF = cf * CFrame.Angles(0, math.rad(settings.Yaw or 0), 0)
	if opts.Ground then
		placeCF = placeCF * CFrame.new(0, box.Y / 2, 0)
	end
	m:PivotTo(placeCF * offset)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			if opts.WeldTo then
				d.Anchored = false
				d.Massless = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				local w = Instance.new("WeldConstraint")
				w.Part0 = opts.WeldTo
				w.Part1 = d
				w.Parent = d
			else
				d.Anchored = true
			end
		end
	end
	return m
end

return Config
end)()

local WorldBuilderModule = (function()
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

local Config = DeepDiveConfig

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
end)()

local SubBuilderModule = (function()
--[[
	SubBuilder  (ModuleScript)
	LOCATION: ServerScriptService > SubBuilder

	Builds a research submarine out of rounded parts (SpecialMesh spheres
	make smooth, curved shapes - no blocky boxes). Bigger hull tier = longer
	sub with more crew seats.

	Every sub has:
	  Root        invisible centre part (PrimaryPart) that physics moves
	  Drive       LinearVelocity   -> how fast the sub moves
	  Steer       AlignOrientation -> which way the sub faces
	  Seats       one per crew station (Helm is a VehicleSeat)
	  Barrel      harpoon turret barrel on a Motor6D so it can aim
	  PropMotor   Motor6D the clients spin to animate the propeller
	  Lamps       two headlights with SpotLights named "Beam"
	  BoardPrompt "Board Sub" ProximityPrompt
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = DeepDiveConfig

local SubBuilder = {}

local SEAT_LAYOUTS = {
	-- {station, x, z as a fraction of hull length}
	[2] = { { "Helm", 0, -0.26 }, { "Turret", 0, 0.08 } },
	[4] = { { "Helm", 0, -0.3 }, { "Turret", 0, -0.06 }, { "Sonar", -1.5, 0.16 }, { "Repair", 1.5, 0.16 } },
}

local function newPart(model, root, props, collide, attachTo)
	local p = Instance.new("Part")
	p.Anchored = false
	p.Massless = true
	p.CanCollide = collide == true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	local mesh = props.Mesh
	props.Mesh = nil
	for k, v in pairs(props) do
		p[k] = v
	end
	if mesh then
		local m = Instance.new("SpecialMesh")
		m.MeshType = mesh
		m.Parent = p
	end
	p.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachTo or root
	weld.Part1 = p
	weld.Parent = p
	return p
end

local SPHERE = Enum.MeshType.Sphere

-- Builds the sub at the world origin; call model:PivotTo() afterwards.
function SubBuilder.Build(hullLevel, paintColor, lightColor, ownerName, isVIP)
	local hull = Config.Upgrades.Hull.Levels[hullLevel] or Config.Upgrades.Hull.Levels[1]
	local L = hull.Length
	local D = hull.Diameter
	local R = D / 2
	local HL = L + D -- full nose-to-tail length
	local mat = hull.Material or Enum.Material.SmoothPlastic
	local accent = Color3.fromRGB(230, 232, 238)
	local dark = Color3.fromRGB(40, 44, 52)
	local brass = Color3.fromRGB(205, 170, 85)

	local model = Instance.new("Model")
	model.Name = ownerName .. "'s Sub"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Anchored = false
	root.RootPriority = 127
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local rootAtt = Instance.new("Attachment")
	rootAtt.Name = "RootAttachment"
	rootAtt.Parent = root

	local drive = Instance.new("LinearVelocity")
	drive.Name = "Drive"
	drive.Attachment0 = rootAtt
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	drive.MaxForce = 90000
	drive.VectorVelocity = Vector3.zero
	drive.Parent = root

	local steer = Instance.new("AlignOrientation")
	steer.Name = "Steer"
	steer.Mode = Enum.OrientationAlignmentMode.OneAttachment
	steer.Attachment0 = rootAtt
	steer.MaxTorque = 1e7
	steer.Responsiveness = 25
	steer.CFrame = CFrame.new()
	steer.Parent = root

	-- Main hull: one smooth teardrop-ish ellipsoid
	local body = newPart(model, root, {
		Name = "Body",
		Size = Vector3.new(D, D * 0.92, HL),
		CFrame = CFrame.new(),
		Material = mat,
		Color = paintColor,
		Mesh = SPHERE,
	}, true)
	body:SetAttribute("Paint", true)

	-- Dark belly (keel) so the hull has two-tone shading
	newPart(model, root, {
		Name = "Belly",
		Size = Vector3.new(D * 0.97, D * 0.62, HL * 0.95),
		CFrame = CFrame.new(0, -D * 0.17, 0.05),
		Material = Enum.Material.SmoothPlastic,
		Color = dark,
		Mesh = SPHERE,
	})
	-- Waterline stripe
	newPart(model, root, {
		Name = "Stripe",
		Size = Vector3.new(D * 1.005, D * 0.08, HL * 0.9),
		CFrame = CFrame.new(0, -D * 0.06, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = accent,
		Mesh = SPHERE,
	})

	-- Glass cockpit bubble at the front
	local bubbleZ = -HL / 2 + D * 0.3
	newPart(model, root, {
		Name = "Cockpit",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(D * 0.8, D * 0.8, D * 0.8),
		CFrame = CFrame.new(0, D * 0.06, bubbleZ),
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(170, 225, 255),
		Transparency = 0.35,
		Reflectance = 0.15,
	}, true)
	newPart(model, root, {
		Name = "CockpitRim",
		Size = Vector3.new(D * 0.86, D * 0.86, D * 0.12),
		CFrame = CFrame.new(0, D * 0.06, bubbleZ + D * 0.22),
		Material = Enum.Material.Metal,
		Color = dark,
		Mesh = SPHERE,
	})

	-- Conning tower (sail)
	local sailZ = HL * 0.04
	local sail = newPart(model, root, {
		Name = "Sail",
		Size = Vector3.new(D * 0.32, D * 0.62, HL * 0.3),
		CFrame = CFrame.new(0, D * 0.5, sailZ),
		Material = mat,
		Color = paintColor,
		Mesh = SPHERE,
	}, true)
	sail:SetAttribute("Paint", true)
	newPart(model, root, {
		Name = "SailPlanes",
		Size = Vector3.new(D * 0.85, 0.16, D * 0.26),
		CFrame = CFrame.new(0, D * 0.56, sailZ - HL * 0.04),
		Material = mat,
		Color = accent,
		Mesh = SPHERE,
	})
	newPart(model, root, {
		Name = "Periscope",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(D * 0.32, 0.22, 0.22),
		CFrame = CFrame.new(0, D * 0.86, sailZ - 0.3) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Metal,
		Color = dark,
	})
	newPart(model, root, {
		Name = "Antenna",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(D * 0.45, 0.08, 0.08),
		CFrame = CFrame.new(0, D * 0.92, sailZ + 0.6) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Metal,
		Color = dark,
	})
	newPart(model, root, {
		Name = "Beacon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.35, 0.35, 0.35),
		CFrame = CFrame.new(0, D * 0.92 + D * 0.23, sailZ + 0.6),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 50, 50),
	})

	-- Side ballast tanks
	for _, side in ipairs({ -1, 1 }) do
		newPart(model, root, {
			Name = "BallastTank",
			Size = Vector3.new(D * 0.26, D * 0.26, HL * 0.6),
			CFrame = CFrame.new(side * D * 0.45, -D * 0.22, HL * 0.06),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(245, 190, 40),
			Mesh = SPHERE,
		})
	end

	-- Bow dive planes
	newPart(model, root, {
		Name = "BowPlanes",
		Size = Vector3.new(D * 1.45, 0.16, D * 0.32),
		CFrame = CFrame.new(0, -D * 0.02, -HL * 0.2),
		Material = mat,
		Color = accent,
		Mesh = SPHERE,
	})

	-- Cross-shaped stern fins
	local sternZ = HL / 2 - D * 0.2
	newPart(model, root, {
		Name = "FinV",
		Size = Vector3.new(0.2, D * 1.05, D * 0.55),
		CFrame = CFrame.new(0, 0, sternZ),
		Material = mat,
		Color = accent,
		Mesh = SPHERE,
	})
	newPart(model, root, {
		Name = "FinH",
		Size = Vector3.new(D * 1.2, 0.2, D * 0.55),
		CFrame = CFrame.new(0, 0, sternZ),
		Material = mat,
		Color = accent,
		Mesh = SPHERE,
	})

	-- Ducted propeller (the duct is a ring of small curved pieces)
	local propZ = HL / 2 + D * 0.08
	local ductR = D * 0.3
	local segs = 12
	for i = 0, segs - 1 do
		local a = i / segs * math.pi * 2
		newPart(model, root, {
			Name = "Duct",
			Size = Vector3.new(0.22, (2 * math.pi * ductR / segs) * 1.15, D * 0.22),
			CFrame = CFrame.new(math.cos(a) * ductR, math.sin(a) * ductR, propZ) * CFrame.Angles(0, 0, a),
			Material = Enum.Material.Metal,
			Color = dark,
		})
	end
	local hub = Instance.new("Part")
	hub.Name = "PropHub"
	hub.Shape = Enum.PartType.Ball
	hub.Size = Vector3.new(D * 0.16, D * 0.16, D * 0.16)
	hub.Material = Enum.Material.Metal
	hub.Color = brass
	hub.Massless = true
	hub.CanCollide = false
	hub.CanTouch = false
	hub.CastShadow = false
	hub.CFrame = CFrame.new(0, 0, propZ)
	hub.Parent = model
	local propMotor = Instance.new("Motor6D")
	propMotor.Name = "PropMotor"
	propMotor.Part0 = root
	propMotor.Part1 = hub
	propMotor.C0 = CFrame.new(0, 0, propZ)
	propMotor.Parent = root
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2
		newPart(model, root, {
			Name = "PropBlade",
			Size = Vector3.new(0.1, ductR * 0.9, D * 0.13),
			CFrame = CFrame.new(0, 0, propZ)
				* CFrame.Angles(0, 0, a)
				* CFrame.new(0, ductR * 0.5, 0)
				* CFrame.Angles(0, 0.5, 0),
			Material = Enum.Material.Metal,
			Color = brass,
			Mesh = SPHERE,
		}, false, hub)
	end
	local propAtt = Instance.new("Attachment")
	propAtt.Name = "PropAttachment"
	propAtt.Position = Vector3.new(0, 0, propZ + 0.8)
	propAtt.Parent = root
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "PropBubbles"
	bubbles.Texture = "rbxasset://textures/particles/smoke_main.dds"
	bubbles.Color = ColorSequence.new(Color3.fromRGB(225, 245, 255))
	bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1.1) })
	bubbles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	bubbles.Lifetime = NumberRange.new(1.2, 2.2)
	bubbles.Speed = NumberRange.new(2, 5)
	bubbles.Acceleration = Vector3.new(0, 3, 0)
	bubbles.SpreadAngle = Vector2.new(20, 20)
	bubbles.EmissionDirection = Enum.NormalId.Back
	bubbles.Rate = 0
	bubbles.LightEmission = 0.15
	bubbles.Parent = propAtt

	-- Portholes (warm glow from inside), placed on the curved hull surface
	for _, f in ipairs({ -0.08, 0.12 }) do
		local z = HL * f
		local x = R * math.sqrt(math.max(0, 1 - (2 * z / HL) ^ 2)) * 0.98
		for _, side in ipairs({ -1, 1 }) do
			newPart(model, root, {
				Name = "Porthole",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.2, D * 0.16, D * 0.16),
				CFrame = CFrame.new(side * x, D * 0.08, z),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 215, 140),
			})
		end
	end

	-- Twin headlights
	for i, side in ipairs({ -1, 1 }) do
		local lampPos = Vector3.new(side * D * 0.3, -D * 0.2, -HL / 2 + D * 0.12)
		newPart(model, root, {
			Name = "LampHousing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(D * 0.12, D * 0.14, D * 0.14),
			CFrame = CFrame.new(lampPos + Vector3.new(0, 0, D * 0.05)) * CFrame.Angles(0, math.rad(90), 0),
			Material = Enum.Material.Metal,
			Color = dark,
		})
		local lamp = newPart(model, root, {
			Name = i == 1 and "Headlight" or "Headlight2",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, D * 0.12, D * 0.12),
			CFrame = CFrame.new(lampPos) * CFrame.Angles(0, math.rad(90), 0),
			Material = Enum.Material.Neon,
			Color = lightColor,
		})
		lamp:SetAttribute("Lamp", true)
		local spot = Instance.new("SpotLight")
		spot.Name = "Beam"
		-- the lamp is turned 90 degrees, so its Right (+X) face points forward
		spot.Face = Enum.NormalId.Right
		spot.Range = 32
		spot.Angle = 50
		spot.Brightness = 3
		spot.Color = lightColor
		spot.Shadows = i == 1
		spot.Parent = lamp
	end
	local glow = Instance.new("PointLight")
	glow.Name = "HullGlow"
	glow.Range = 14
	glow.Brightness = 0.6
	glow.Color = Color3.fromRGB(255, 225, 180)
	glow.Parent = body

	-- Harpoon turret on the bow
	local turretZ = -HL * 0.22
	local turretY = D * 0.44
	newPart(model, root, {
		Name = "TurretBase",
		Size = Vector3.new(D * 0.28, D * 0.16, D * 0.28),
		CFrame = CFrame.new(0, turretY, turretZ),
		Material = Enum.Material.Metal,
		Color = dark,
		Mesh = SPHERE,
	})
	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(0.45, 0.45, 3.2)
	barrel.Material = Enum.Material.Metal
	barrel.Color = Color3.fromRGB(80, 85, 95)
	barrel.Massless = true
	barrel.CanCollide = false
	barrel.CanTouch = false
	barrel.CastShadow = false
	barrel.CFrame = CFrame.new(0, turretY + 0.35, turretZ - 1.4)
	barrel.Parent = model
	local barrelMesh = Instance.new("SpecialMesh")
	barrelMesh.MeshType = Enum.MeshType.Sphere
	barrelMesh.Parent = barrel
	local motor = Instance.new("Motor6D")
	motor.Name = "TurretMotor"
	motor.Part0 = root
	motor.Part1 = barrel
	motor.C0 = CFrame.new(0, turretY + 0.35, turretZ)
	motor.C1 = CFrame.new(0, 0, 1.4)
	motor.Parent = root
	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Position = Vector3.new(0, 0, -1.7)
	tip.Parent = barrel
	model:SetAttribute("TurretPivot", Vector3.new(0, turretY + 0.35, turretZ))

	-- Seats (inside the hull)
	local layout = SEAT_LAYOUTS[#hull.Seats] or SEAT_LAYOUTS[2]
	local seatY = -R + 1.1
	for _, info in ipairs(layout) do
		local station = info[1]
		local seat
		if station == "Helm" then
			seat = Instance.new("VehicleSeat")
			seat.MaxSpeed = 0
			seat.Torque = 0
			seat.TurnSpeed = 0
			seat.HeadsUpDisplay = false
		else
			seat = Instance.new("Seat")
		end
		seat.Name = station .. "Seat"
		seat.Size = Vector3.new(2, 0.6, 2)
		seat.Transparency = 1
		seat.CanCollide = false
		seat.CanTouch = true -- (seats are hidden inside the hull; boarding uses the prompt)
		seat.Massless = true
		seat.Anchored = false
		seat.CFrame = CFrame.new(info[2], seatY, HL * info[3])
		seat:SetAttribute("Station", station)
		seat.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = seat
		weld.Parent = seat
	end

	-- Name tag
	local tagAtt = Instance.new("Attachment")
	tagAtt.Name = "TagAttachment"
	tagAtt.Position = Vector3.new(0, D * 1.3, 0)
	tagAtt.Parent = root
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(220, 40)
	tag.MaxDistance = 140
	tag.LightInfluence = 0
	tag.Parent = tagAtt
	local tagLabel = Instance.new("TextLabel")
	tagLabel.Size = UDim2.fromScale(1, 1)
	tagLabel.BackgroundTransparency = 1
	tagLabel.Font = Enum.Font.FredokaOne
	tagLabel.TextScaled = true
	tagLabel.TextColor3 = isVIP and Color3.fromRGB(255, 215, 60) or Color3.new(1, 1, 1)
	tagLabel.TextStrokeTransparency = 0.3
	tagLabel.Text = (isVIP and "VIP " or "") .. ownerName .. "'s " .. hull.Name
	tagLabel.Parent = tag

	-- Board prompt
	local promptAtt = Instance.new("Attachment")
	promptAtt.Name = "PromptAttachment"
	promptAtt.Position = Vector3.new(0, R + 1, 0)
	promptAtt.Parent = root
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ActionText = "Board Sub"
	prompt.ObjectText = ownerName .. "'s Sub"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = math.max(16, HL * 0.7)
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = promptAtt

	-- Custom 3D model? (ReplicatedStorage > DeepDiveModels > Submarine)
	local custom = Config.PlaceCustomModel("Submarine", root.CFrame, HL * 1.05, { WeldTo = root, AllAxes = true })
	if custom then
		custom.Name = "CustomLook"
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and p ~= root and p.Name ~= "Barrel" then
				p.Transparency = 1 -- keep the invisible hull for collisions, show the real model
			end
		end
		custom.Parent = model
		model:SetAttribute("CustomLook", true)
	end

	model:SetAttribute("IsSub", true)
	model:SetAttribute("HullLength", L)
	model:SetAttribute("HullRadius", R)
	return model
end

-- Applies paint + light colour to an existing sub (no rebuild needed).
function SubBuilder.ApplyLook(model, paintColor, lightColor, shiny)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			if p:GetAttribute("Paint") then
				p.Color = paintColor
				p.Reflectance = shiny and 0.25 or 0
			elseif p:GetAttribute("Lamp") then
				p.Color = lightColor
				local beam = p:FindFirstChild("Beam")
				if beam then
					beam.Color = lightColor
				end
			end
		end
	end
end

-- Sets headlight range/brightness on every lamp.
function SubBuilder.ApplyLights(model, range, angle, brightness)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("Lamp") then
			local beam = p:FindFirstChild("Beam")
			if beam then
				beam.Range = range
				beam.Angle = angle
				beam.Brightness = brightness
			end
		end
	end
end

return SubBuilder
end)()

local PlayerDataModule = (function()
--[[
	PlayerData  (ModuleScript)
	LOCATION: ServerScriptService > PlayerData

	Loads and saves every player's progress with DataStoreService.
	  * retries with back-off when Roblox's servers are busy
	  * autosaves every few minutes, on leave, and when the server shuts down
	  * if loading FAILS, that session is never saved, so nobody's progress
	    gets wiped by accident

	In Studio: Game Settings > Security > "Enable Studio Access to API
	Services" must be ON for saving to work while testing.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerData = {}

local STORE_NAME = "DeepDive_PlayerData_v1"
local AUTOSAVE_INTERVAL = 150
local MAX_RETRIES = 5

local DEFAULT_DATA = {
	Coins = 0,
	BestDepth = 0,
	TotalSalvage = 0,
	Kills = 0,
	Dives = 0,
	Upgrades = {
		Hull = 1,
		Engine = 1,
		Lights = 1,
		Cargo = 1,
		Plating = 1,
		Harpoon = 1,
	},
	Supplies = {
		RepairKit = 1,
		OxygenTank = 1,
	},
	Paint = "Sunshine",
	LightColor = "Warm",
	OwnedPaints = { Sunshine = true, Navy = true },
	OwnedLights = { Warm = true },
	Lore = {},
	Daily = { LastDay = 0, Streak = 0 },
	TutorialDone = false,
	BoostUntil = 0,
	Receipts = {},
	ReceiptCount = 0,
}

local store
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(STORE_NAME)
	end)
	if not ok then
		warn("[DeepDive] DataStores unavailable (turn on API access in Game Settings to save):", err)
	end
end

local sessions = {} -- [player] = { Data = table, CanSave = bool, Dirty = bool }

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = deepCopy(v)
	end
	return out
end

-- Adds any keys that are missing (so old saves get new features).
local function reconcile(data, template)
	for k, v in pairs(template) do
		if data[k] == nil then
			data[k] = deepCopy(v)
		elseif type(v) == "table" and type(data[k]) == "table" then
			reconcile(data[k], v)
		end
	end
	return data
end

local function retry(fn)
	local delay = 1
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(("[DeepDive] DataStore attempt %d failed: %s"):format(attempt, tostring(result)))
		local msg = tostring(result)
		if msg:find("Studio") or msg:find("publish") or msg:find("403") then
			break -- not allowed here (e.g. Studio without API access): don't keep retrying
		end
		if attempt < MAX_RETRIES then
			task.wait(delay)
			delay *= 2
		end
	end
	return false, nil
end

local function keyFor(player)
	return "player_" .. player.UserId
end

function PlayerData.Load(player)
	local data, canSave
	if store then
		local ok, saved = retry(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			data = type(saved) == "table" and saved or deepCopy(DEFAULT_DATA)
			canSave = true
		else
			data = deepCopy(DEFAULT_DATA)
			canSave = false
		end
	else
		data = deepCopy(DEFAULT_DATA)
		canSave = false
	end
	reconcile(data, DEFAULT_DATA)
	sessions[player] = { Data = data, CanSave = canSave, Dirty = false }
	return data, canSave
end

function PlayerData.Get(player)
	local s = sessions[player]
	return s and s.Data
end

function PlayerData.CanSave(player)
	local s = sessions[player]
	return s ~= nil and s.CanSave
end

function PlayerData.MarkDirty(player)
	local s = sessions[player]
	if s then
		s.Dirty = true
	end
end

function PlayerData.Save(player)
	local s = sessions[player]
	if not s or not s.CanSave or not store then
		return false
	end
	local snapshot = deepCopy(s.Data)
	local ok = retry(function()
		store:UpdateAsync(keyFor(player), function()
			return snapshot
		end)
	end)
	if ok then
		s.Dirty = false
	end
	return ok
end

function PlayerData.Release(player)
	PlayerData.Save(player)
	sessions[player] = nil
end

function PlayerData.StartAutosave()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, s in pairs(sessions) do
				if s.Dirty and player.Parent then
					task.spawn(PlayerData.Save, player)
				end
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			pending += 1
			task.spawn(function()
				PlayerData.Save(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.2)
		end
	end)
end

return PlayerData
end)()

local MonstersModule = (function()
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

local Config = DeepDiveConfig

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
	return ctx.ClampToWater(pos)
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
	local model, root
	local custom = Config.GetCustomModel(kind)
	if custom then
		-- ReplicatedStorage > DeepDiveModels > BiterFish / Jellyfish / Eel
		model = Instance.new("Model")
		model.Name = kind
		root = makeRoot(model, Vector3.new(3, 3, 4))
		local length = (Config.CustomModels[kind] or {}).Length or 4
		local look = Config.PlaceCustomModel(kind, CFrame.new(), length, { WeldTo = root, AllAxes = true })
		look.Parent = model
	else
		model, root = builder()
	end
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
	-- monsters come out of the dark above or below you, somewhere in the Well
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist = rng:NextNumber(Config.Spawning.SpawnDistance[1], Config.Spawning.SpawnDistance[2])
	local vertical = (rng:NextNumber() < 0.6 and 1 or -1) * dist
	local flat = Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(10, 60)
	local center = clampToWater(Vector3.new(flat.X, subPos.Y + vertical, flat.Z))
	if (center - subPos).Magnitude < 35 then
		return -- too close to pop in without being seen
	end
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
end)()

--[[
	GameServer  (Script)
	LOCATION: ServerScriptService > GameServer

	The brain of Deep Dive. Everything important happens here on the
	server so exploiters can't give themselves coins:
	  * spawns each player's sub at their berth
	  * boarding, crew stations, invites
	  * depth, oxygen, crush damage, leaks, repairs, sinking
	  * loot spawning, salvage, cashing out when you surface
	  * harpoon turret, sonar, supplies
	  * the shop, daily chest, distress signals, lore, leaderboard
	  * Robux products / VIP pass (only if you set IDs in DeepDiveConfig)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Debris = game:GetService("Debris")

local Config = DeepDiveConfig
local WorldBuilder = WorldBuilderModule
local SubBuilder = SubBuilderModule
local PlayerData = PlayerDataModule
local Monsters = MonstersModule

local S = Config.SURFACE_Y
local rng = Random.new()

Players.CharacterAutoLoads = false

------------------------------------------------------------------------
-- Remotes (client <-> server messages)
------------------------------------------------------------------------
local REMOTE_NAMES = {
	"RequestData",
	"DataUpdate",
	"Notify",
	"Fire",
	"HarpoonFX",
	"Sonar",
	"SonarPing",
	"Patch",
	"UseSupply",
	"Buy",
	"LeaveSub",
	"SwitchStation",
	"CrewInvite",
	"CrewInvitePrompt",
	"CrewRespond",
	"CrewKick",
	"SetCrewOpen",
	"Lore",
	"Daily",
	"TutorialDone",
	"OpenShop",
	"LootFX",
	"SubHit",
	"Surfaced",
	"Sunk",
}
local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "DeepDiveRemotes"
local R = {}
for _, name in ipairs(REMOTE_NAMES) do
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = remotesFolder
	R[name] = ev
end
-- Clients ask for the config once (functions can't be sent, so strip them)
local function plainCopy(t)
	local out = {}
	for k, v in pairs(t) do
		if type(v) == "table" then
			out[k] = plainCopy(v)
		elseif type(v) ~= "function" then
			out[k] = v
		end
	end
	return out
end
local configForClients = plainCopy(Config)
local getConfig = Instance.new("RemoteFunction")
getConfig.Name = "GetConfig"
getConfig.OnServerInvoke = function()
	return configForClients
end
getConfig.Parent = remotesFolder
remotesFolder.Parent = ReplicatedStorage

------------------------------------------------------------------------
-- Build the world
------------------------------------------------------------------------
WorldBuilder.Build()

local rootFolder = Instance.new("Folder")
rootFolder.Name = "DeepDive"
rootFolder.Parent = workspace
local function makeFolder(name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = rootFolder
	return f
end
local subsFolder = makeFolder("Subs")
local lootFolder = makeFolder("Loot")
local signalsFolder = makeFolder("Signals")
local fxFolder = makeFolder("FX")

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local subs = {} -- [owner player] = sub
local seatedIn = {} -- [player] = sub they are sitting in
local berthOf = {} -- [player] = berth
local crewSettings = {} -- [owner] = { Invited = {[userId] = true}, Open = bool }
local vipPlayers = {} -- [player] = true
local friendCache = {}
local lastAction = {}
local ready = {} -- [player] = true once data is loaded

local lootById = {}
local nextLootId = 0
local activeSignals = {}

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------
local function notify(player, text, kind)
	if player and player.Parent then
		R.Notify:FireClient(player, text, kind or "info")
	end
end

local function notifyCrew(sub, text, kind)
	for plr in pairs(sub.Crew) do
		notify(plr, text, kind)
	end
end

local function rateOk(player, key, interval)
	local t = lastAction[player]
	if not t then
		t = {}
		lastAction[player] = t
	end
	local now = os.clock()
	if t[key] and now - t[key] < interval then
		return false
	end
	t[key] = now
	return true
end

local function getHumanoid(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum, char
end

local function crewCount(sub)
	local n = 0
	for _ in pairs(sub.Crew) do
		n += 1
	end
	return n
end

local function isVIP(player)
	return vipPlayers[player] == true
end

local function isNaNVector(v)
	return v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z
end

local function sendData(player)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local copy = {}
	for k, v in pairs(data) do
		if k ~= "Receipts" then
			copy[k] = v
		end
	end
	R.DataUpdate:FireClient(player, copy, {
		VIP = isVIP(player),
		CanSave = PlayerData.CanSave(player),
		ServerTime = os.time(),
	})
end

local function setupLeaderstats(player, data)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = data.Coins
	coins.Parent = stats
	local depth = Instance.new("IntValue")
	depth.Name = "Best Depth"
	depth.Value = data.BestDepth
	depth.Parent = stats
	stats.Parent = player
end

local function refreshLeaderstats(player)
	local data = PlayerData.Get(player)
	local stats = player:FindFirstChild("leaderstats")
	if data and stats then
		stats.Coins.Value = data.Coins
		stats["Best Depth"].Value = data.BestDepth
	end
end

local function changed(player)
	PlayerData.MarkDirty(player)
	refreshLeaderstats(player)
	sendData(player)
end

local function teleportToDock(player)
	local _, char = getHumanoid(player)
	if not char then
		return
	end
	local berth = berthOf[player]
	local cf = berth and berth.ExitCFrame or WorldBuilder.SpawnCFrame
	char:PivotTo(cf)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
end

local function areFriends(a, b)
	local key = math.min(a.UserId, b.UserId) .. "_" .. math.max(a.UserId, b.UserId)
	if friendCache[key] == nil then
		local ok, result = pcall(function()
			return a:IsFriendsWith(b.UserId)
		end)
		friendCache[key] = ok and result or false
	end
	return friendCache[key]
end

------------------------------------------------------------------------
-- Sub stats & attributes
------------------------------------------------------------------------
local function pushSubAttributes(sub)
	local m = sub.Model
	if not m or not m.Parent then
		return
	end
	m:SetAttribute("HP", math.ceil(sub.HP))
	m:SetAttribute("MaxHP", sub.MaxHP)
	m:SetAttribute("Oxygen", math.ceil(sub.Oxygen))
	m:SetAttribute("MaxOxygen", sub.MaxOxygen)
	m:SetAttribute("Leaks", #sub.Leaks)
	m:SetAttribute("CargoCount", sub.CargoCount)
	m:SetAttribute("CargoValue", sub.CargoValue)
	m:SetAttribute("CrewCount", crewCount(sub))
	m:SetAttribute("Diving", sub.Diving)
end

local function applyStats(sub)
	local data = PlayerData.Get(sub.Owner)
	if not data then
		return
	end
	local st = Config.ComputeStats(data.Upgrades, isVIP(sub.Owner))
	local oldMax = sub.MaxHP or st.MaxHP
	sub.Stats = st
	sub.MaxHP = st.MaxHP
	if sub.HP == nil then
		sub.HP = st.MaxHP
	else
		sub.HP = math.min(sub.HP + math.max(0, st.MaxHP - oldMax), st.MaxHP)
	end
	sub.MaxOxygen = st.MaxOxygen
	sub.Oxygen = sub.Oxygen and math.min(sub.Oxygen, st.MaxOxygen) or st.MaxOxygen

	local m = sub.Model
	m:SetAttribute("HullName", st.HullName)
	m:SetAttribute("Speed", st.Speed)
	m:SetAttribute("Turn", st.Turn)
	m:SetAttribute("MaxDepth", st.MaxDepth)
	m:SetAttribute("CargoMax", st.CargoMax)
	m:SetAttribute("FogBonus", st.FogBonus)
	m:SetAttribute("HarpoonLevel", st.HarpoonLevel)
	m:SetAttribute("HarpoonCooldown", st.HarpoonCooldown)

	SubBuilder.ApplyLights(m, st.LightRange, st.LightAngle, st.LightBrightness)
	local barrel = m:FindFirstChild("Barrel")
	if barrel then
		barrel.Transparency = st.HarpoonLevel > 1 and 0 or 1
	end
	local paint = Config.FindPaint(data.Paint)
	local light = Config.FindLightColor(data.LightColor)
	SubBuilder.ApplyLook(m, paint.Color, light.Color, paint.Shiny)
	local tagAtt = sub.Root:FindFirstChild("TagAttachment")
	local tag = tagAtt and tagAtt:FindFirstChild("NameTag")
	local label = tag and tag:FindFirstChildOfClass("TextLabel")
	if label then
		label.TextColor3 = isVIP(sub.Owner) and Color3.fromRGB(255, 215, 60) or Color3.new(1, 1, 1)
		label.Text = (isVIP(sub.Owner) and "VIP " or "") .. sub.Owner.DisplayName .. "'s " .. st.HullName
	end
	pushSubAttributes(sub)
end

------------------------------------------------------------------------
-- Pilot / crew
------------------------------------------------------------------------
local function yawOf(cf)
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function setPilot(sub, player)
	sub.Pilot = player
	local root = sub.Root
	if not root or not root.Parent then
		return
	end
	if not player then
		-- hold still and face the way we're pointing now
		root.Drive.VectorVelocity = Vector3.zero
		root.Steer.CFrame = CFrame.Angles(0, yawOf(root.CFrame), 0)
	end
	pcall(function()
		root:SetNetworkOwner(player)
	end)
end

local function setJump(player, enabled)
	local hum = getHumanoid(player)
	if hum then
		hum.JumpPower = enabled and 50 or 0
		hum.JumpHeight = enabled and 7.2 or 0
	end
end

local function removeFromCrew(sub, player)
	if not sub.Crew[player] then
		return
	end
	local station = sub.Crew[player]
	sub.Crew[player] = nil
	sub.SeatOf[player] = nil
	sub.Switching[player] = nil
	if seatedIn[player] == sub then
		seatedIn[player] = nil
	end
	if player.Parent then
		player:SetAttribute("Station", nil)
		player:SetAttribute("SubOwnerId", nil)
		setJump(player, true)
	end
	if station == "Helm" or sub.Pilot == player then
		setPilot(sub, nil)
	end
	pushSubAttributes(sub)
end

local function unseatPlayer(player, toDock)
	local sub = seatedIn[player]
	if sub then
		sub.Leaving[player] = true
	end
	local hum = getHumanoid(player)
	if hum and hum.SeatPart then
		local weld = hum.SeatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		hum.Sit = false
	end
	if sub then
		removeFromCrew(sub, player)
	end
	if toDock then
		task.defer(teleportToDock, player)
	end
end

local function canBoard(sub, player)
	if player == sub.Owner then
		return true
	end
	local settings = crewSettings[sub.Owner]
	if settings and (settings.Open or settings.Invited[player.UserId]) then
		return true
	end
	return areFriends(sub.Owner, player)
end

local function onEnteredSeat(sub, player, seat)
	local station = seat:GetAttribute("Station")
	local wasAboard = sub.Crew[player] ~= nil
	sub.Crew[player] = station
	sub.SeatOf[player] = seat
	sub.Switching[player] = nil
	sub.Leaving[player] = nil
	seatedIn[player] = sub
	sub.EmptyTime = 0
	player:SetAttribute("Station", station)
	player:SetAttribute("SubOwnerId", sub.Owner.UserId)
	setJump(player, false)
	if station == "Helm" then
		setPilot(sub, player)
	elseif sub.Pilot then
		pcall(function()
			sub.Root:SetNetworkOwner(sub.Pilot)
		end)
	end
	if not wasAboard and player ~= sub.Owner then
		notify(sub.Owner, player.DisplayName .. " joined your crew!", "good")
	end
	pushSubAttributes(sub)
end

local function onLeftSeat(sub, player, seat)
	if sub.Destroyed then
		removeFromCrew(sub, player)
		return
	end
	if sub.Switching[player] then
		if sub.Pilot == player then
			setPilot(sub, nil)
		end
		return
	end
	if sub.Leaving[player] then
		sub.Leaving[player] = nil
		removeFromCrew(sub, player)
		return
	end
	local hum = getHumanoid(player)
	local alive = hum and hum.Health > 0 and player.Parent ~= nil
	-- Nobody leaves a sub by accident (water, physics hiccups, jump key).
	-- The only way out is the LEAVE SUB button. Put them straight back.
	local now = os.clock()
	sub.Reseats = sub.Reseats or {}
	local log = sub.Reseats[player] or { Count = 0, Since = now }
	if now - log.Since > 10 then
		log.Count, log.Since = 0, now
	end
	log.Count += 1
	sub.Reseats[player] = log
	if alive and log.Count <= 6 then
		task.delay(0.05, function()
			if not sub.Destroyed and seat.Parent and not seat.Occupant and hum.Parent and hum.Health > 0 then
				hum.Sit = false
				seat:Sit(hum)
			else
				removeFromCrew(sub, player)
				teleportToDock(player)
			end
		end)
		return
	end
	removeFromCrew(sub, player)
	if alive then
		task.defer(teleportToDock, player)
	end
end

local function hookSeat(sub, seat)
	local current = nil
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local hum = seat.Occupant
		local plr = hum and Players:GetPlayerFromCharacter(hum.Parent)
		if current and current ~= plr then
			local leaver = current
			current = nil
			onLeftSeat(sub, leaver, seat)
		end
		if hum and not plr then
			task.defer(function()
				local w = seat:FindFirstChild("SeatWeld")
				if w then
					w:Destroy()
				end
			end)
			return
		end
		if plr and plr ~= current then
			local other = seatedIn[plr]
			if sub.Destroyed or not canBoard(sub, plr) or (other and other ~= sub) then
				task.defer(function()
					local w = seat:FindFirstChild("SeatWeld")
					if w then
						w:Destroy()
					end
					hum.Sit = false
				end)
				return
			end
			current = plr
			onEnteredSeat(sub, plr, seat)
		end
	end)
end

local function pickSeat(sub, player)
	local helm, free
	for _, seat in ipairs(sub.Seats) do
		if not seat.Occupant then
			if seat:GetAttribute("Station") == "Helm" then
				helm = seat
			elseif not free then
				free = seat
			end
		end
	end
	if player == sub.Owner then
		return helm or free
	end
	return free or helm
end

local function tryBoard(sub, player)
	if sub.Destroyed or sub.Sinking then
		return
	end
	if seatedIn[player] then
		notify(player, "You're already in a sub.", "bad")
		return
	end
	if sub.Depth > Config.SurfaceDepth + 1 then
		notify(player, "That sub is diving right now.", "bad")
		return
	end
	if not canBoard(sub, player) then
		notify(player, "Ask " .. sub.Owner.DisplayName .. " to invite you (Crew button).", "bad")
		return
	end
	local hum = getHumanoid(player)
	if not hum or hum.Health <= 0 then
		return
	end
	local seat = pickSeat(sub, player)
	if not seat then
		notify(player, "This sub is full!", "bad")
		return
	end
	if hum.SeatPart then
		local w = hum.SeatPart:FindFirstChild("SeatWeld")
		if w then
			w:Destroy()
		end
	end
	seat:Sit(hum)
end

------------------------------------------------------------------------
-- Subs: spawn / destroy / reset
------------------------------------------------------------------------
local destroySub -- forward declaration

local function updateBerthSign(berth)
	local text = berth.Owner and ("BERTH " .. berth.Index .. "\n" .. berth.Owner.DisplayName)
		or ("BERTH " .. berth.Index .. "\nfree")
	for _, label in ipairs(berth.Labels) do
		label.Text = text
		label.TextColor3 = berth.Owner and Color3.fromRGB(255, 220, 120) or Color3.new(1, 1, 1)
	end
	berth.Marker.Color = berth.Owner and Color3.fromRGB(255, 200, 80) or Color3.fromRGB(140, 200, 255)
end

local function spawnSub(owner)
	if not owner.Parent then
		return nil
	end
	local data = PlayerData.Get(owner)
	local berth = berthOf[owner]
	if not data or not berth then
		return nil
	end
	local old = subs[owner]
	if old then
		destroySub(old)
	end
	local paint = Config.FindPaint(data.Paint)
	local light = Config.FindLightColor(data.LightColor)
	local model = SubBuilder.Build(data.Upgrades.Hull, paint.Color, light.Color, owner.DisplayName, isVIP(owner))
	model:SetAttribute("OwnerId", owner.UserId)
	model:SetAttribute("OwnerName", owner.DisplayName)
	model:PivotTo(berth.SubCFrame)
	model.PrimaryPart.Steer.CFrame = berth.SubCFrame.Rotation
	model.Parent = subsFolder

	local sub = {
		Owner = owner,
		Model = model,
		Root = model.PrimaryPart,
		Berth = berth,
		HalfLength = model:GetAttribute("HullLength") / 2,
		Radius = model:GetAttribute("HullRadius"),
		Crew = {},
		SeatOf = {},
		Seats = {},
		Leaving = {},
		Switching = {},
		LastPatch = {},
		Leaks = {},
		CargoCount = 0,
		CargoValue = 0,
		CargoItems = {},
		Depth = 0,
		CrewCount = 0,
		Diving = false,
		MaxDiveDepth = 0,
		Destroyed = false,
		Sinking = false,
		EmptyTime = 0,
		AutoRepairTimer = 0,
		LastFire = 0,
		LastSonar = 0,
		LastWarn = {},
		LastCause = "the deep",
	}
	subs[owner] = sub
	pcall(function()
		sub.Root:SetNetworkOwner(nil)
	end)

	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Seat") or child:IsA("VehicleSeat") then
			table.insert(sub.Seats, child)
			hookSeat(sub, child)
		end
	end
	local prompt = model:FindFirstChild("BoardPrompt", true)
	sub.Prompt = prompt
	prompt.Triggered:Connect(function(player)
		tryBoard(sub, player)
	end)
	applyStats(sub)
	return sub
end

function destroySub(sub)
	if sub.Destroyed then
		return
	end
	sub.Destroyed = true
	local crew = {}
	for plr in pairs(sub.Crew) do
		table.insert(crew, plr)
	end
	for _, plr in ipairs(crew) do
		unseatPlayer(plr, true)
	end
	Monsters.ReleaseSub(sub)
	if sub.Model then
		sub.Model:Destroy()
	end
	if subs[sub.Owner] == sub then
		subs[sub.Owner] = nil
	end
end

local function resetToBerth(sub)
	local root = sub.Root
	if not root or not root.Parent then
		return
	end
	setPilot(sub, sub.Pilot) -- keep the pilot if there is one
	local cf = sub.Berth.SubCFrame
	root.CFrame = cf -- moves the whole sub (and anyone seated inside)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Steer.CFrame = cf.Rotation
	root.Drive.VectorVelocity = Vector3.zero
end

------------------------------------------------------------------------
-- Leaks & damage
------------------------------------------------------------------------
local sinkSub -- forward declaration

local function addLeak(sub)
	if #sub.Leaks >= Config.Damage.MaxLeaks then
		return
	end
	local angle = rng:NextNumber(0, math.pi * 2)
	local z = rng:NextNumber(-sub.HalfLength * 0.9, sub.HalfLength * 0.9)
	local outward = Vector3.new(math.cos(angle), math.sin(angle), 0)
	local pos = outward * sub.Radius + Vector3.new(0, 0, z)
	local att = Instance.new("Attachment")
	att.Name = "Leak"
	att.CFrame = CFrame.lookAt(pos, pos + outward)
	att.Parent = sub.Root
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(230, 245, 255))
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.2) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	pe.Speed = NumberRange.new(4, 8)
	pe.Lifetime = NumberRange.new(0.8, 1.4)
	pe.SpreadAngle = Vector2.new(20, 20)
	pe.EmissionDirection = Enum.NormalId.Front
	pe.Rate = 30
	pe.Acceleration = Vector3.new(0, 6, 0)
	pe.Parent = att
	table.insert(sub.Leaks, att)
	if os.clock() - (sub.LastWarn.Leak or 0) > 2 then
		sub.LastWarn.Leak = os.clock()
		notifyCrew(sub, "HULL BREACH! Hold R (or tap PATCH) to fix the leak.", "bad")
	end
end

local function patchLeak(sub)
	local att = table.remove(sub.Leaks)
	if att then
		att:Destroy()
		return true
	end
	return false
end

local function damageSub(sub, amount, leakChance, source, silent)
	if sub.Destroyed or sub.Sinking or not sub.Diving then
		return
	end
	local st = sub.Stats
	if crewCount(sub) <= 1 then
		amount *= Config.Damage.SoloDamageMult
	end
	amount *= (1 - st.Armor)
	sub.HP = math.max(0, sub.HP - amount)
	sub.LastCause = source or "a monster"
	if leakChance and leakChance > 0 and rng:NextNumber() < leakChance * (1 - st.LeakResist) then
		addLeak(sub)
	end
	if not silent then
		for plr in pairs(sub.Crew) do
			R.SubHit:FireClient(plr, amount, source)
		end
	end
	pushSubAttributes(sub)
	if sub.HP <= 0 then
		sinkSub(sub, sub.LastCause)
	end
end

------------------------------------------------------------------------
-- Leaderboard (deepest dives, all servers)
------------------------------------------------------------------------
local depthStore
pcall(function()
	depthStore = DataStoreService:GetOrderedDataStore("DeepDive_BestDepth_v1")
end)
local pendingBoard = {}
local nameCache = {}

local function queueLeaderboard(player, depth)
	pendingBoard[player.UserId] = depth
	nameCache[player.UserId] = player.DisplayName
end

local function refreshBoard()
	local lines = {}
	if depthStore then
		for userId, depth in pairs(pendingBoard) do
			pendingBoard[userId] = nil
			pcall(function()
				depthStore:SetAsync(tostring(userId), depth)
			end)
		end
		local ok, pages = pcall(function()
			return depthStore:GetSortedAsync(false, 10)
		end)
		if ok and pages then
			for rank, entry in ipairs(pages:GetCurrentPage()) do
				local uid = tonumber(entry.key)
				local name = uid and nameCache[uid]
				if not name and uid then
					local okName, result = pcall(function()
						return Players:GetNameFromUserIdAsync(uid)
					end)
					name = okName and result or "???"
					nameCache[uid] = name
				end
				table.insert(lines, ("%d. %s  -  %s m"):format(rank, name or "???", Config.FormatNumber(entry.value)))
			end
		end
	end
	if #lines == 0 then
		-- No DataStore (e.g. Studio without API access): show this server
		local list = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			local data = PlayerData.Get(plr)
			if data then
				table.insert(list, { plr.DisplayName, data.BestDepth })
			end
		end
		table.sort(list, function(a, b)
			return a[2] > b[2]
		end)
		for i, row in ipairs(list) do
			if i > 10 then
				break
			end
			table.insert(lines, ("%d. %s  -  %s m"):format(i, row[1], Config.FormatNumber(row[2])))
		end
	end
	WorldBuilder.LeaderboardLabel.Text = #lines > 0 and table.concat(lines, "\n") or "No dives yet.\nBe the first!"
end

------------------------------------------------------------------------
-- Diving, surfacing, sinking
------------------------------------------------------------------------
local function startDive(sub)
	sub.Diving = true
	sub.MaxDiveDepth = sub.Depth
	if sub.Prompt then
		sub.Prompt.Enabled = false
	end
	notifyCrew(sub, "Diving! Loot only counts once you SURFACE again.", "info")
	pushSubAttributes(sub)
end

local function onSurfaced(sub)
	sub.Diving = false
	if sub.Prompt then
		sub.Prompt.Enabled = true
	end
	Monsters.ReleaseSub(sub)
	local depth = math.floor(sub.MaxDiveDepth)
	local value = sub.CargoValue
	local n = crewCount(sub)
	local bonus = math.min(Config.Crew.MaxBonus, Config.Crew.BonusPerExtraMember * math.max(0, n - 1))
	for plr in pairs(sub.Crew) do
		local data = PlayerData.Get(plr)
		if data then
			local boost = (data.BoostUntil or 0) > os.time()
			local payout = math.floor(value * (1 + bonus) * (boost and 2 or 1) + 0.5)
			data.Coins += payout
			data.TotalSalvage += payout
			if depth >= 15 then
				data.Dives += 1
			end
			local record = depth > data.BestDepth
			if record then
				data.BestDepth = depth
				queueLeaderboard(plr, depth)
			end
			changed(plr)
			if value > 0 or record then
				R.Surfaced:FireClient(plr, {
					Items = sub.CargoItems,
					Value = value,
					Bonus = bonus,
					Boost = boost,
					Payout = payout,
					Depth = depth,
					Record = record,
				})
			end
		end
	end
	sub.CargoCount = 0
	sub.CargoValue = 0
	sub.CargoItems = {}
	sub.MaxDiveDepth = 0
	if sub.PendingRebuild then
		sub.PendingRebuild = false
		task.defer(spawnSub, sub.Owner)
	end
	pushSubAttributes(sub)
end

function sinkSub(sub, cause)
	if sub.Sinking or sub.Destroyed then
		return
	end
	sub.Sinking = true
	local pos = sub.Root.Position
	local boom = Instance.new("Explosion")
	boom.Position = pos
	boom.BlastRadius = 10
	boom.BlastPressure = 0
	boom.DestroyJointRadiusPercent = 0
	boom.ExplosionType = Enum.ExplosionType.NoCraters
	boom.Parent = fxFolder

	local lost = sub.CargoValue
	local insurance = math.floor(lost * Config.Sink.InsurancePercent)
	for plr in pairs(sub.Crew) do
		local data = PlayerData.Get(plr)
		if data then
			data.Coins += insurance
			changed(plr)
		end
		R.Sunk:FireClient(plr, { Lost = lost, Insurance = insurance, Cause = cause or "the deep" })
	end
	local owner = sub.Owner
	destroySub(sub)
	task.delay(Config.Sink.RespawnTime, function()
		if owner.Parent and not subs[owner] then
			spawnSub(owner)
		end
	end)
end

local function emergencySurface(sub)
	if sub.Destroyed or sub.Sinking then
		return false
	end
	resetToBerth(sub)
	sub.HP = math.max(sub.HP, sub.MaxHP * 0.25)
	notifyCrew(sub, "EMERGENCY SURFACE! Your haul is safe.", "good")
	return true
end

------------------------------------------------------------------------
-- Loot
------------------------------------------------------------------------
local function lootPart(model, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local mesh = props.Mesh
	props.Mesh = nil
	for k, v in pairs(props) do
		p[k] = v
	end
	if mesh then
		local m = Instance.new("SpecialMesh")
		m.MeshType = mesh
		m.Parent = p
	end
	p.Parent = model
	return p
end

local SPHERE = Enum.MeshType.Sphere

local function buildLootModel(def, pos)
	local model = Instance.new("Model")
	model.Name = def.Name
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local main
	local look = def.Look
	if look == "Scrap" then
		-- rusty pipe + bent plate
		main = lootPart(model, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.6, 0.7, 0.7),
			CFrame = base * CFrame.new(0, -0.5, 0) * CFrame.Angles(0, 0.4, 0),
			Material = Enum.Material.CorrodedMetal,
			Color = Color3.fromRGB(150, 95, 60),
		})
		lootPart(model, {
			Size = Vector3.new(1.8, 0.15, 1.4),
			CFrame = base * CFrame.new(0.3, -0.3, 0.5) * CFrame.Angles(0.3, 1.2, 0.25),
			Material = Enum.Material.DiamondPlate,
			Color = def.Color,
		})
		lootPart(model, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 0.9, 0.9),
			CFrame = base * CFrame.new(1.3, -0.5, -0.5) * CFrame.Angles(0, 0.4, 0),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(110, 110, 120),
		})
	elseif look == "Shell" then
		-- scallop shell with ridges
		main = lootPart(model, {
			Size = Vector3.new(2, 0.6, 1.8),
			CFrame = base * CFrame.new(0, -0.6, 0) * CFrame.Angles(0.2, 0, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = def.Color,
			Mesh = SPHERE,
		})
		for i = -2, 2 do
			lootPart(model, {
				Size = Vector3.new(0.15, 0.25, 1.7),
				CFrame = main.CFrame * CFrame.new(i * 0.36, 0.22, 0) * CFrame.Angles(0, i * 0.18, 0),
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(255, 225, 235),
				Mesh = SPHERE,
			})
		end
		lootPart(model, {
			Size = Vector3.new(0.7, 0.35, 0.5),
			CFrame = main.CFrame * CFrame.new(0, 0, 0.95),
			Material = Enum.Material.SmoothPlastic,
			Color = def.Color,
			Mesh = SPHERE,
		})
	elseif look == "Chest" then
		main = lootPart(model, {
			Size = Vector3.new(3, 1.6, 2),
			CFrame = base * CFrame.new(0, -0.4, 0) * CFrame.Angles(0, 0, 0.12),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(110, 72, 40),
		})
		lootPart(model, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, 2, 2),
			CFrame = main.CFrame * CFrame.new(0, 0.55, -0.35) * CFrame.Angles(-0.5, 0, 0),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(95, 62, 35),
		})
		for _, x in ipairs({ -1.1, 1.1 }) do
			lootPart(model, {
				Size = Vector3.new(0.2, 1.7, 2.1),
				CFrame = main.CFrame * CFrame.new(x, 0, 0),
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(200, 160, 60),
			})
		end
		lootPart(model, {
			Size = Vector3.new(2.6, 0.5, 1.4),
			CFrame = main.CFrame * CFrame.new(0, 0.85, 0.1),
			Material = Enum.Material.Neon,
			Color = def.Color,
			Mesh = SPHERE,
		})
	elseif look == "Pearl" then
		-- open clam with a glowing pearl inside
		local clamCF = base * CFrame.new(0, -0.7, 0)
		lootPart(model, {
			Size = Vector3.new(2.6, 0.6, 2.2),
			CFrame = clamCF,
			Material = Enum.Material.Pebble,
			Color = Color3.fromRGB(110, 90, 140),
			Mesh = SPHERE,
		})
		lootPart(model, {
			Size = Vector3.new(2.6, 0.6, 2.2),
			CFrame = clamCF * CFrame.new(0, 0.6, 0.9) * CFrame.Angles(-0.9, 0, 0),
			Material = Enum.Material.Pebble,
			Color = Color3.fromRGB(125, 100, 155),
			Mesh = SPHERE,
		})
		main = lootPart(model, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.9, 0.9, 0.9),
			CFrame = clamCF * CFrame.new(0, 0.45, -0.1),
			Material = Enum.Material.Neon,
			Color = def.Color,
		})
	elseif look == "Coins" then
		-- a spilled pile of old gold coins
		for i = 1, 7 do
			local c = lootPart(model, {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.18, 0.9, 0.9),
				CFrame = base
					* CFrame.new(rng:NextNumber(-0.8, 0.8), -0.8 + (i % 3) * 0.15, rng:NextNumber(-0.8, 0.8))
					* CFrame.Angles(
						rng:NextNumber(-0.4, 0.4),
						rng:NextNumber(0, 3),
						math.rad(90) + rng:NextNumber(-0.4, 0.4)
					),
				Material = Enum.Material.Foil,
				Color = def.Color,
			})
			main = main or c
		end
		lootPart(model, {
			Size = Vector3.new(1.4, 0.7, 1.4),
			CFrame = base * CFrame.new(0, -0.6, 0),
			Material = Enum.Material.Foil,
			Color = Color3.fromRGB(230, 180, 50),
			Mesh = SPHERE,
		})
	elseif look == "Idol" then
		main = lootPart(model, {
			Size = Vector3.new(1, 1.8, 0.8),
			CFrame = base,
			Material = Enum.Material.Foil,
			Color = def.Color,
			Mesh = SPHERE,
		})
		lootPart(model, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.9, 0.9, 0.9),
			CFrame = base * CFrame.new(0, 1.2, 0),
			Material = Enum.Material.Foil,
			Color = def.Color,
		})
		for _, x in ipairs({ -0.2, 0.2 }) do
			lootPart(model, {
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.2, 0.2, 0.2),
				CFrame = base * CFrame.new(x, 1.25, -0.4),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(80, 255, 120),
			})
		end
		lootPart(model, {
			Size = Vector3.new(1.4, 0.4, 1.2),
			CFrame = base * CFrame.new(0, -1, 0),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(80, 80, 90),
		})
	else -- Crate (distress signal)
		main = lootPart(model, {
			Size = Vector3.new(3, 2.4, 2.4),
			CFrame = base,
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(40, 90, 100),
		})
		for _, y in ipairs({ -0.9, 0.9 }) do
			lootPart(model, {
				Size = Vector3.new(3.1, 0.25, 2.5),
				CFrame = base * CFrame.new(0, y, 0),
				Material = Enum.Material.Neon,
				Color = def.Color,
			})
		end
	end
	local light = Instance.new("PointLight")
	light.Range = 10
	light.Brightness = 1.4
	light.Color = def.Color
	light.Parent = main
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 3
	sparkle.Lifetime = NumberRange.new(1, 1.6)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.Size = NumberSequence.new(0.35, 0)
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new(def.Color)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Parent = main
	model.PrimaryPart = main
	return model
end

local function createLoot(def, pos, value, zoneName, signal)
	nextLootId += 1
	local model = buildLootModel(def, pos)
	model:SetAttribute("LootValue", value)
	model:SetAttribute("LootName", def.Name)
	model.Parent = lootFolder
	local entry = {
		Id = nextLootId,
		Name = def.Name,
		Value = value,
		Pos = pos,
		Model = model,
		Zone = zoneName,
		Color = def.Color,
		Signal = signal,
	}
	lootById[entry.Id] = entry
	return entry
end

local function randomFloorPoint(zoneName)
	if zoneName == "Sunlit Reef" then
		return WorldBuilder.LootSpot(25, 198)
	end
	return WorldBuilder.LootSpot(215, 620)
end

local function pickLootType(zoneName)
	local total = 0
	for _, def in pairs(Config.Loot.Types) do
		if def.Zone == zoneName then
			total += def.Weight
		end
	end
	local r = rng:NextNumber(0, total)
	for _, def in pairs(Config.Loot.Types) do
		if def.Zone == zoneName then
			r -= def.Weight
			if r <= 0 then
				return def
			end
		end
	end
	return nil
end

local function spawnLoot(zoneName)
	local def = pickLootType(zoneName)
	local pos = randomFloorPoint(zoneName)
	if def and pos then
		createLoot(def, pos, def.Value, zoneName, nil)
	end
end

local onSignalLooted -- forward declaration

local function collectLoot(sub, loot)
	lootById[loot.Id] = nil
	sub.CargoCount += 1
	sub.CargoValue += loot.Value
	sub.CargoItems[loot.Name] = (sub.CargoItems[loot.Name] or 0) + 1
	for plr in pairs(sub.Crew) do
		R.LootFX:FireClient(plr, loot.Name, loot.Value, loot.Pos, loot.Color)
	end
	if loot.Model then
		loot.Model:Destroy()
	end
	if loot.Signal then
		onSignalLooted(sub, loot.Signal)
	else
		task.delay(rng:NextNumber(Config.Loot.RespawnMin, Config.Loot.RespawnMax), spawnLoot, loot.Zone)
	end
	pushSubAttributes(sub)
end

local function checkLoot(sub)
	local center = sub.Root.Position
	local reach = sub.Radius + Config.Loot.PickupRange
	local rough = sub.HalfLength + reach + 3
	for _, loot in pairs(lootById) do
		if (loot.Pos - center).Magnitude < rough then
			local onLine = Monsters.ClosestOnSub(sub, loot.Pos)
			if (loot.Pos - onLine).Magnitude <= reach + 1.5 then
				if sub.CargoCount >= sub.Stats.CargoMax then
					if os.clock() - (sub.LastWarn.Full or 0) > 5 then
						sub.LastWarn.Full = os.clock()
						notifyCrew(sub, "Cargo hold FULL! Surface to cash in your haul.", "bad")
					end
					return
				end
				collectLoot(sub, loot)
			end
		end
	end
end

------------------------------------------------------------------------
-- Distress signals (random wrecks with rare loot + lore)
------------------------------------------------------------------------
local function buildWreck(pos)
	local model = Instance.new("Model")
	model.Name = "DistressSignal"
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local rust = Color3.fromRGB(140, 80, 50)
	local hull = lootPart(model, {
		Name = "WreckHull",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(14, 6, 6),
		CFrame = base * CFrame.new(5, 2, 0) * CFrame.Angles(0, 0, math.rad(18)),
		Material = Enum.Material.CorrodedMetal,
		Color = rust,
	})
	hull.CanCollide = true
	lootPart(model, {
		Name = "WreckTower",
		Size = Vector3.new(2, 3, 3),
		CFrame = base * CFrame.new(5, 5.5, 0) * CFrame.Angles(0, 0, math.rad(18)),
		Material = Enum.Material.CorrodedMetal,
		Color = rust,
	})
	local beacon = lootPart(model, {
		Name = "Beacon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.4, 1.4, 1.4),
		CFrame = base * CFrame.new(0, 6, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 60, 60),
	})
	lootPart(model, {
		Name = "Antenna",
		Size = Vector3.new(0.25, 5, 0.25),
		CFrame = base * CFrame.new(0, 3, 0),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(80, 80, 90),
	})
	local light = Instance.new("PointLight")
	light.Range = 22
	light.Brightness = 2
	light.Color = Color3.fromRGB(255, 70, 70)
	light.Parent = beacon
	local gui = Instance.new("BillboardGui")
	gui.Name = "SignalGui"
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 2000
	gui.Adornee = beacon
	gui.Parent = model
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 120, 120)
	label.TextStrokeTransparency = 0.2
	label.Text = "DISTRESS SIGNAL"
	label.Parent = gui
	model.PrimaryPart = beacon
	return model
end

local function removeSignal(signal)
	for i, s in ipairs(activeSignals) do
		if s == signal then
			table.remove(activeSignals, i)
			break
		end
	end
	if signal.Model then
		signal.Model:Destroy()
	end
	if signal.Loot and lootById[signal.Loot.Id] then
		lootById[signal.Loot.Id] = nil
		if signal.Loot.Model then
			signal.Loot.Model:Destroy()
		end
	end
end

local function spawnSignal()
	if #activeSignals >= Config.Signals.MaxActive then
		return
	end
	local zoneName = rng:NextNumber() < 0.55 and "Sunlit Reef" or "Twilight Drop"
	local pos = randomFloorPoint(zoneName)
	if not pos then
		return
	end
	local range = Config.Signals.Value[zoneName]
	local value = rng:NextInteger(range[1], range[2])
	local wreck = buildWreck(pos)
	wreck:SetAttribute("Zone", zoneName)
	wreck.Parent = signalsFolder
	local signal = { Model = wreck, Zone = zoneName, Expires = os.clock() + Config.Signals.Lifetime }
	signal.Loot = createLoot(Config.Loot.Types.SignalCrate, pos + Vector3.new(0, 0.6, 0), value, zoneName, signal)
	table.insert(activeSignals, signal)
	R.Notify:FireAllClients("DISTRESS SIGNAL detected in the " .. zoneName .. "! Rare loot inside.", "signal")
end

function onSignalLooted(sub, signal)
	signal.Loot = nil
	removeSignal(signal)
	R.Notify:FireAllClients(sub.Owner.DisplayName .. "'s crew salvaged the distress signal!", "signal")
	for plr in pairs(sub.Crew) do
		local data = PlayerData.Get(plr)
		if data then
			local found = nil
			for i = 1, #Config.Lore do
				if not data.Lore[tostring(i)] then
					found = i
					break
				end
			end
			if found then
				data.Lore[tostring(found)] = true
				PlayerData.MarkDirty(plr)
				sendData(plr)
				R.Lore:FireClient(plr, found)
			end
		end
	end
end

------------------------------------------------------------------------
-- Monster hooks
------------------------------------------------------------------------
Monsters.Init({
	RootFolder = rootFolder,
	ClampToWater = WorldBuilder.ClampToWater,
	GetDivingSubs = function()
		local list = {}
		for _, sub in pairs(subs) do
			if sub.Diving and not sub.Sinking and not sub.Destroyed and sub.CrewCount > 0 then
				table.insert(list, sub)
			end
		end
		return list
	end,
	GetAllSubs = function()
		local list = {}
		for _, sub in pairs(subs) do
			table.insert(list, sub)
		end
		return list
	end,
	DamageSub = damageSub,
	OnMonsterKilled = function(m, player, sub)
		local bounty = math.floor(m.Def.Bounty * m.Mult + 0.5)
		if sub and not sub.Destroyed then
			sub.CargoValue += bounty
			local key = "Bounty: " .. m.Def.Name
			sub.CargoItems[key] = (sub.CargoItems[key] or 0) + 1
			pushSubAttributes(sub)
		end
		if player then
			local data = PlayerData.Get(player)
			if data then
				data.Kills += 1
				PlayerData.MarkDirty(player)
			end
			notify(player, ("%s down! +%d bounty (cash in at the surface)"):format(m.Def.Name, bounty), "loot")
		end
	end,
})

------------------------------------------------------------------------
-- Main loop (10 times a second)
------------------------------------------------------------------------
local function stepSub(sub, dt)
	local root = sub.Root
	if sub.Destroyed or not root or not root.Parent then
		return
	end
	local pos = root.Position
	local depth = S - pos.Y
	sub.Depth = depth
	local n = crewCount(sub)
	sub.CrewCount = n

	-- Teleport sanity check (stops exploiters warping onto loot)
	if sub.LastPos then
		local moved = (pos - sub.LastPos).Magnitude
		if moved > (sub.Stats.Speed * 2.5 + 15) * dt + 4 then
			sub.SuspectUntil = os.clock() + 2
		end
	end
	sub.LastPos = pos

	-- Way out of bounds? Send it home.
	if pos.Y > S + 15 or depth > 700 or Vector3.new(pos.X, 0, pos.Z).Magnitude > 200 then
		resetToBerth(sub)
		return
	end

	if n == 0 then
		sub.EmptyTime += dt
		if sub.EmptyTime > 3 then
			if depth > Config.SurfaceDepth then
				-- abandoned underwater: the haul is lost
				sub.CargoCount, sub.CargoValue, sub.CargoItems = 0, 0, {}
				sub.Diving = false
				if sub.Prompt then
					sub.Prompt.Enabled = true
				end
				resetToBerth(sub)
			elseif (pos - sub.Berth.SubCFrame.Position).Magnitude > 8 then
				resetToBerth(sub)
			end
			sub.EmptyTime = 0
		end
		if sub.Diving and depth <= Config.SurfaceDepth then
			sub.Diving = false
		end
		sub.HP = math.min(sub.MaxHP, sub.HP + Config.Damage.SurfaceRepairPerSecond * dt)
		sub.Oxygen = sub.MaxOxygen
		while #sub.Leaks > 0 do
			patchLeak(sub)
		end
		pushSubAttributes(sub)
		return
	end
	sub.EmptyTime = 0

	if depth > Config.SurfaceDepth then
		if not sub.Diving then
			startDive(sub)
		end
		sub.MaxDiveDepth = math.max(sub.MaxDiveDepth, depth)

		-- Oxygen
		sub.Oxygen = math.max(0, sub.Oxygen - dt)
		if sub.Oxygen <= 0 then
			sub.HP -= Config.Damage.NoOxygenDPS * dt
			sub.LastCause = "running out of air"
			if os.clock() - (sub.LastWarn.Air or 0) > 4 then
				sub.LastWarn.Air = os.clock()
				notifyCrew(sub, "OUT OF AIR! Surface now or use an Oxygen Tank (2).", "bad")
			end
		end

		-- Crush damage below the hull rating
		local maxDepth = sub.Stats.MaxDepth
		if depth > maxDepth then
			sub.HP -= (Config.Damage.CrushBaseDPS + (depth - maxDepth) * Config.Damage.CrushPerMetre) * dt
			sub.LastCause = "water pressure"
			if os.clock() - (sub.LastWarn.Crush or 0) > 3 then
				sub.LastWarn.Crush = os.clock()
				notifyCrew(sub, "The hull is CRUSHING! Go up - your hull is only rated to " .. maxDepth .. " m.", "bad")
			end
		end

		-- Leaks let water in
		if #sub.Leaks > 0 then
			sub.HP -= #sub.Leaks * Config.Damage.LeakDPS * dt
			if sub.LastCause == "the deep" then
				sub.LastCause = "flooding"
			end
		end

		-- Solo auto-repair kit
		if n == 1 and #sub.Leaks > 0 then
			sub.AutoRepairTimer += dt
			if sub.AutoRepairTimer >= Config.Damage.SoloAutoRepairEvery then
				sub.AutoRepairTimer = 0
				patchLeak(sub)
				notifyCrew(sub, "Auto-repair kit patched a leak.", "good")
			end
		else
			sub.AutoRepairTimer = 0
		end

		-- Salvage
		if os.clock() > (sub.SuspectUntil or 0) then
			checkLoot(sub)
		end

		if sub.HP <= 0 then
			sub.HP = 0
			sinkSub(sub, sub.LastCause)
			return
		end
	else
		if sub.Diving then
			onSurfaced(sub)
		end
		sub.Oxygen = math.min(sub.MaxOxygen, sub.Oxygen + sub.MaxOxygen * 0.3 * dt)
		sub.HP = math.min(sub.MaxHP, sub.HP + Config.Damage.SurfaceRepairPerSecond * dt)
		while #sub.Leaks > 0 do
			patchLeak(sub)
		end
		sub.LastCause = "the deep"
	end
	pushSubAttributes(sub)
end

local tickAcc = 0
RunService.Heartbeat:Connect(function(dt)
	tickAcc += dt
	if tickAcc < 0.1 then
		return
	end
	local step = math.min(tickAcc, 0.5)
	tickAcc = 0
	for _, sub in pairs(subs) do
		local ok, err = pcall(stepSub, sub, step)
		if not ok then
			warn("[DeepDive] sub update error:", err)
		end
	end
	-- Players who fall in the water get fished out
	for _, plr in ipairs(Players:GetPlayers()) do
		if not seatedIn[plr] then
			local _, char = getHumanoid(plr)
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp.Position.Y < S - 4 then
				teleportToDock(plr)
				if rateOk(plr, "splash", 5) then
					notify(plr, "Splash! You got fished out. Board your sub to explore the Well.", "info")
				end
			end
		end
	end
end)

------------------------------------------------------------------------
-- Remote handlers
------------------------------------------------------------------------
R.RequestData.OnServerEvent:Connect(function(plr)
	if ready[plr] and rateOk(plr, "request", 1) then
		sendData(plr)
	end
end)

R.LeaveSub.OnServerEvent:Connect(function(plr)
	local sub = seatedIn[plr]
	if not sub then
		return
	end
	if sub.Depth > Config.SurfaceDepth + 1 then
		notify(plr, "You can't open the hatch underwater! Surface first.", "bad")
		return
	end
	unseatPlayer(plr, true)
end)

R.SwitchStation.OnServerEvent:Connect(function(plr, station)
	local sub = seatedIn[plr]
	if not sub or type(station) ~= "string" or sub.Crew[plr] == station then
		return
	end
	if not rateOk(plr, "switch", 0.6) then
		return
	end
	local target
	for _, seat in ipairs(sub.Seats) do
		if seat:GetAttribute("Station") == station and not seat.Occupant then
			target = seat
		end
	end
	if not target then
		notify(plr, "That station is taken.", "bad")
		return
	end
	local hum = getHumanoid(plr)
	if not hum then
		return
	end
	local oldSeat = sub.SeatOf[plr]
	sub.Switching[plr] = true
	if oldSeat then
		local w = oldSeat:FindFirstChild("SeatWeld")
		if w then
			w:Destroy()
		end
	end
	task.wait(0.05)
	target:Sit(hum)
	task.delay(0.6, function()
		-- if something went wrong, go back to the old seat
		if sub.Switching[plr] and not sub.Destroyed then
			sub.Switching[plr] = nil
			if oldSeat and not oldSeat.Occupant and hum.Parent then
				oldSeat:Sit(hum)
			end
		end
	end)
end)

R.Fire.OnServerEvent:Connect(function(plr, targetPos)
	local sub = seatedIn[plr]
	if not sub or sub.Destroyed or typeof(targetPos) ~= "Vector3" or isNaNVector(targetPos) then
		return
	end
	local station = sub.Crew[plr]
	if station ~= "Turret" then
		if station ~= "Helm" then
			return
		end
		for _, seat in ipairs(sub.Seats) do
			if seat:GetAttribute("Station") == "Turret" and seat.Occupant then
				return -- a gunner is aboard; let them shoot
			end
		end
	end
	local st = sub.Stats
	if st.HarpoonLevel <= 1 then
		if rateOk(plr, "noturret", 4) then
			notify(plr, "No harpoon yet! Buy a Harpoon Turret at the shop.", "bad")
		end
		return
	end
	local now = os.clock()
	if now - sub.LastFire < st.HarpoonCooldown * 0.9 then
		return
	end
	sub.LastFire = now

	local root = sub.Root
	local pivotLocal = sub.Model:GetAttribute("TurretPivot")
	local pivotWorld = root.CFrame:PointToWorldSpace(pivotLocal)
	local dir = targetPos - pivotWorld
	if dir.Magnitude < 1 then
		dir = root.CFrame.LookVector
	end
	dir = dir.Unit
	-- aim the barrel
	local motor = root:FindFirstChild("TurretMotor")
	local localDir = root.CFrame:VectorToObjectSpace(dir)
	if motor and math.abs(localDir.Y) < 0.98 then
		motor.C0 = CFrame.lookAt(pivotLocal, pivotLocal + localDir)
	end
	local origin = pivotWorld + dir * 3.3
	local range = st.HarpoonRange
	local m = Monsters.FindTarget(origin, dir, range, 12)
	local hitPos
	if m then
		hitPos = m.Pos
	else
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true
		local ignore = { sub.Model, lootFolder, signalsFolder, fxFolder }
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		params.FilterDescendantsInstances = ignore
		local result = workspace:Raycast(origin, dir * range, params)
		hitPos = result and result.Position or (origin + dir * range)
	end
	R.HarpoonFX:FireAllClients(sub.Model, origin, hitPos, m ~= nil)
	if m then
		local travel = (hitPos - origin).Magnitude / 220
		task.delay(travel, function()
			Monsters.Damage(m, st.HarpoonDamage, plr, sub)
		end)
	end
end)

R.Sonar.OnServerEvent:Connect(function(plr)
	local sub = seatedIn[plr]
	if not sub then
		return
	end
	local isSonar = sub.Crew[plr] == "Sonar"
	local cd = isSonar and Config.Sonar.CooldownSonarStation or Config.Sonar.CooldownOtherStation
	if os.clock() - sub.LastSonar < cd * 0.95 then
		return
	end
	sub.LastSonar = os.clock()
	local radius = Config.Sonar.Radius * (isSonar and 1.3 or 1)
	for crew in pairs(sub.Crew) do
		R.SonarPing:FireClient(crew, sub.Model, radius, cd)
	end
end)

R.Patch.OnServerEvent:Connect(function(plr)
	local sub = seatedIn[plr]
	if not sub or #sub.Leaks == 0 then
		return
	end
	local need = sub.Crew[plr] == "Repair" and Config.Damage.PatchTimeRepairStation
		or Config.Damage.PatchTimeOtherStation
	if os.clock() - (sub.LastPatch[plr] or 0) < need * 0.85 then
		return
	end
	sub.LastPatch[plr] = os.clock()
	if patchLeak(sub) then
		sub.HP = math.min(sub.MaxHP, sub.HP + 2)
		notify(plr, "Leak patched!", "good")
		pushSubAttributes(sub)
	end
end)

R.UseSupply.OnServerEvent:Connect(function(plr, kind)
	local sup = Config.Supplies[kind]
	local data = PlayerData.Get(plr)
	if not sup or not data or not rateOk(plr, "supply", 0.5) then
		return
	end
	local sub = seatedIn[plr]
	if not sub then
		notify(plr, "Use supplies while you're in a sub.", "bad")
		return
	end
	if (data.Supplies[kind] or 0) <= 0 then
		notify(plr, "You're out of " .. sup.DisplayName .. "s. Buy more at the shop!", "bad")
		return
	end
	if kind == "RepairKit" then
		if sub.HP >= sub.MaxHP - 0.5 and #sub.Leaks == 0 then
			notify(plr, "The hull is already in good shape.", "info")
			return
		end
		sub.HP = math.min(sub.MaxHP, sub.HP + sub.MaxHP * sup.Heal)
		patchLeak(sub)
		patchLeak(sub)
	elseif kind == "OxygenTank" then
		if sub.Oxygen >= sub.MaxOxygen - 1 then
			notify(plr, "Oxygen is already full.", "info")
			return
		end
		sub.Oxygen = math.min(sub.MaxOxygen, sub.Oxygen + sup.Seconds)
	end
	data.Supplies[kind] -= 1
	changed(plr)
	notifyCrew(sub, plr.DisplayName .. " used a " .. sup.DisplayName .. ".", "good")
	pushSubAttributes(sub)
end)

-- Shop ------------------------------------------------------------------
local function onUpgradesChanged(plr, hullChanged)
	local sub = subs[plr]
	if not sub then
		return
	end
	if hullChanged then
		if sub.Diving then
			sub.PendingRebuild = true
			notify(plr, "Your new hull will be fitted when your sub surfaces.", "info")
		else
			spawnSub(plr)
		end
	else
		applyStats(sub)
	end
end

R.Buy.OnServerEvent:Connect(function(plr, category, key)
	if not rateOk(plr, "buy", 0.25) or type(category) ~= "string" or type(key) ~= "string" then
		return
	end
	local data = PlayerData.Get(plr)
	if not data then
		return
	end
	local sub = seatedIn[plr]
	if sub and sub.Depth > Config.SurfaceDepth + 1 then
		notify(plr, "Surface first to use the shop!", "bad")
		return
	end

	if category == "Upgrade" then
		local up = Config.Upgrades[key]
		if not up then
			return
		end
		local cur = data.Upgrades[key] or 1
		local nextLevel = up.Levels[cur + 1]
		if not nextLevel then
			notify(plr, up.DisplayName .. " is fully upgraded!", "info")
			return
		end
		if nextLevel.ComingSoon then
			notify(plr, nextLevel.Name .. " is coming in a future update!", "info")
			return
		end
		if data.Coins < nextLevel.Cost then
			notify(plr, "Not enough coins.", "bad")
			return
		end
		data.Coins -= nextLevel.Cost
		data.Upgrades[key] = cur + 1
		notify(plr, ("Upgraded %s to %s!"):format(up.DisplayName, nextLevel.Name), "good")
		changed(plr)
		onUpgradesChanged(plr, key == "Hull")
	elseif category == "Supply" then
		local sup = Config.Supplies[key]
		if not sup then
			return
		end
		local count = data.Supplies[key] or 0
		if count >= sup.Max then
			notify(plr, "You can't carry more " .. sup.DisplayName .. "s.", "info")
			return
		end
		if data.Coins < sup.Cost then
			notify(plr, "Not enough coins.", "bad")
			return
		end
		data.Coins -= sup.Cost
		data.Supplies[key] = count + 1
		notify(plr, "Bought a " .. sup.DisplayName .. ".", "good")
		changed(plr)
	elseif category == "Paint" or category == "Light" then
		local list = category == "Paint" and Config.Paints or Config.LightColors
		local owned = category == "Paint" and data.OwnedPaints or data.OwnedLights
		local item
		for _, p in ipairs(list) do
			if p.Id == key then
				item = p
			end
		end
		if not item then
			return
		end
		if not owned[key] then
			if data.Coins < item.Cost then
				notify(plr, "Not enough coins.", "bad")
				return
			end
			data.Coins -= item.Cost
			owned[key] = true
			notify(plr, "Unlocked " .. item.Name .. "!", "good")
		end
		if category == "Paint" then
			data.Paint = key
		else
			data.LightColor = key
		end
		changed(plr)
		if subs[plr] then
			applyStats(subs[plr])
		end
	end
end)

-- Crew ------------------------------------------------------------------
R.CrewInvite.OnServerEvent:Connect(function(owner, targetUserId)
	if not rateOk(owner, "invite", 1) then
		return
	end
	local target = Players:GetPlayerByUserId(tonumber(targetUserId) or 0)
	local settings = crewSettings[owner]
	if not target or target == owner or not settings then
		return
	end
	settings.Invited[target.UserId] = true
	R.CrewInvitePrompt:FireClient(target, owner.UserId, owner.DisplayName)
	notify(owner, "Crew invite sent to " .. target.DisplayName .. ".", "good")
end)

R.CrewRespond.OnServerEvent:Connect(function(plr, ownerId, accept)
	local owner = Players:GetPlayerByUserId(tonumber(ownerId) or 0)
	if not owner then
		return
	end
	if not accept then
		notify(owner, plr.DisplayName .. " said no thanks.", "info")
		return
	end
	local sub = subs[owner]
	if not sub then
		notify(plr, "Their sub isn't ready yet. Try again in a moment.", "bad")
		return
	end
	local current = seatedIn[plr]
	if current == sub then
		return
	end
	if current then
		if current.Depth > Config.SurfaceDepth + 1 then
			notify(plr, "Surface first, then you can join their crew!", "bad")
			return
		end
		unseatPlayer(plr, false)
		task.wait(0.1)
	end
	tryBoard(sub, plr)
end)

R.CrewKick.OnServerEvent:Connect(function(owner, targetUserId)
	local target = Players:GetPlayerByUserId(tonumber(targetUserId) or 0)
	local sub = subs[owner]
	if not target or not sub or seatedIn[target] ~= sub or target == owner then
		return
	end
	local settings = crewSettings[owner]
	if settings then
		settings.Invited[target.UserId] = nil
	end
	if sub.Depth > Config.SurfaceDepth + 1 then
		notify(owner, "You can drop off crew once you surface.", "info")
		return
	end
	unseatPlayer(target, true)
	notify(target, owner.DisplayName .. " dropped you off at the dock.", "info")
end)

R.SetCrewOpen.OnServerEvent:Connect(function(owner, open)
	local settings = crewSettings[owner]
	if settings then
		settings.Open = open == true
		owner:SetAttribute("CrewOpen", settings.Open)
		notify(
			owner,
			settings.Open and "Anyone can now board your sub." or "Only friends and invited players can board.",
			"info"
		)
	end
end)

R.TutorialDone.OnServerEvent:Connect(function(plr)
	local data = PlayerData.Get(plr)
	if data and not data.TutorialDone then
		data.TutorialDone = true
		PlayerData.MarkDirty(plr)
	end
end)

WorldBuilder.ShopPrompt.Triggered:Connect(function(plr)
	R.OpenShop:FireClient(plr)
end)

------------------------------------------------------------------------
-- Daily chest
------------------------------------------------------------------------
local function giveDaily(plr, data)
	local today = math.floor(os.time() / 86400)
	local d = data.Daily
	if d.LastDay == today then
		return
	end
	if d.LastDay == today - 1 then
		d.Streak += 1
	else
		d.Streak = 1
	end
	d.LastDay = today
	local coins = math.min(Config.Daily.MaxCoins, Config.Daily.BaseCoins + Config.Daily.PerStreakDay * (d.Streak - 1))
	data.Coins += coins
	local kit = d.Streak % Config.Daily.RepairKitEvery == 0
	if kit then
		data.Supplies.RepairKit = math.min(Config.Supplies.RepairKit.Max, (data.Supplies.RepairKit or 0) + 1)
	end
	PlayerData.MarkDirty(plr)
	R.Daily:FireClient(plr, d.Streak, coins, kit)
end

------------------------------------------------------------------------
-- Robux: developer products & VIP pass
------------------------------------------------------------------------
local productById = {}
for _, p in ipairs(Config.Monetization.Products) do
	if p.Id and p.Id ~= 0 then
		productById[p.Id] = p
	end
end

local function grantProduct(plr, product)
	local data = PlayerData.Get(plr)
	if product.Coins then
		data.Coins += product.Coins
		notify(plr, "+" .. Config.FormatNumber(product.Coins) .. " coins! Thanks for supporting Deep Dive!", "good")
	elseif product.BoostMinutes then
		data.BoostUntil = math.max(os.time(), data.BoostUntil or 0) + product.BoostMinutes * 60
		notify(plr, "2x loot is active for " .. product.BoostMinutes .. " minutes!", "good")
	elseif product.Emergency then
		local sub = seatedIn[plr]
		if not (sub and sub.Diving and emergencySurface(sub)) then
			data.Supplies.RepairKit = math.min(Config.Supplies.RepairKit.Max, (data.Supplies.RepairKit or 0) + 2)
			notify(plr, "Your sub was already safe, so here are 2 Repair Kits instead.", "good")
		end
	end
	changed(plr)
end

MarketplaceService.ProcessReceipt = function(info)
	local plr = Players:GetPlayerByUserId(info.PlayerId)
	local product = productById[info.ProductId]
	local data = plr and PlayerData.Get(plr)
	if not plr or not product or not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if data.Receipts[info.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local ok, err = pcall(grantProduct, plr, product)
	if not ok then
		warn("[DeepDive] product grant failed:", err)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	data.ReceiptCount += 1
	if data.ReceiptCount > 200 then
		data.Receipts = {}
		data.ReceiptCount = 1
	end
	data.Receipts[info.PurchaseId] = true
	PlayerData.Save(plr)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function setVIP(plr)
	vipPlayers[plr] = true
	plr:SetAttribute("VIP", true)
	if subs[plr] then
		applyStats(subs[plr])
	end
	sendData(plr)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
	if purchased and passId == Config.Monetization.VIPPassId and passId ~= 0 then
		setVIP(plr)
		notify(plr, "Welcome aboard, VIP Captain!", "good")
	end
end)

------------------------------------------------------------------------
-- Players joining / leaving
------------------------------------------------------------------------
local function assignBerth(plr)
	for _, berth in ipairs(WorldBuilder.Berths) do
		if not berth.Owner then
			berth.Owner = plr
			berthOf[plr] = berth
			updateBerthSign(berth)
			return berth
		end
	end
	return nil
end

local function onCharacterAdded(plr, char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	hum.Died:Connect(function()
		local sub = seatedIn[plr]
		if sub then
			removeFromCrew(sub, plr)
		end
		task.delay(3, function()
			if plr.Parent then
				plr:LoadCharacter()
			end
		end)
	end)
end

local function onPlayerAdded(plr)
	local data = PlayerData.Load(plr)
	if not plr.Parent then
		PlayerData.Release(plr)
		return
	end
	crewSettings[plr] = { Invited = {}, Open = false }
	local vipId = Config.Monetization.VIPPassId
	if vipId ~= 0 then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(plr.UserId, vipId)
		end)
		if ok and owns then
			vipPlayers[plr] = true
			plr:SetAttribute("VIP", true)
		end
	end
	setupLeaderstats(plr, data)
	nameCache[plr.UserId] = plr.DisplayName
	plr.CharacterAdded:Connect(function(char)
		onCharacterAdded(plr, char)
	end)
	plr:LoadCharacter()
	local berth = assignBerth(plr)
	if berth then
		spawnSub(plr)
	else
		notify(plr, "All berths are full - ask someone to invite you to their crew!", "info")
	end
	giveDaily(plr, data)
	ready[plr] = true
	sendData(plr)
	refreshLeaderstats(plr)
	if not PlayerData.CanSave(plr) then
		notify(
			plr,
			"Saving is off (Studio without API access, or Roblox is down). Progress won't save this session.",
			"bad"
		)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, plr)
end

Players.PlayerRemoving:Connect(function(plr)
	local inSub = seatedIn[plr]
	if inSub then
		removeFromCrew(inSub, plr)
	end
	local own = subs[plr]
	if own then
		destroySub(own)
	end
	local berth = berthOf[plr]
	if berth then
		berth.Owner = nil
		updateBerthSign(berth)
	end
	berthOf[plr] = nil
	crewSettings[plr] = nil
	vipPlayers[plr] = nil
	lastAction[plr] = nil
	ready[plr] = nil
	for _, settings in pairs(crewSettings) do
		settings.Invited[plr.UserId] = nil
	end
	PlayerData.Release(plr)
end)

PlayerData.StartAutosave()

------------------------------------------------------------------------
-- Background loops: loot, signals, leaderboard
------------------------------------------------------------------------
task.spawn(function()
	for zoneName, count in pairs(Config.Loot.SpawnCount) do
		for i = 1, count do
			spawnLoot(zoneName)
			if i % 10 == 0 then
				task.wait()
			end
		end
	end
end)

task.spawn(function()
	task.wait(60)
	while true do
		local ok, err = pcall(spawnSignal)
		if not ok then
			warn("[DeepDive] signal error:", err)
		end
		task.wait(rng:NextNumber(Config.Signals.MinInterval, Config.Signals.MaxInterval))
	end
end)

task.spawn(function()
	while true do
		task.wait(5)
		local now = os.clock()
		for i = #activeSignals, 1, -1 do
			local signal = activeSignals[i]
			if now > signal.Expires then
				removeSignal(signal)
			end
		end
	end
end)

task.spawn(function()
	task.wait(8)
	while true do
		local ok, err = pcall(refreshBoard)
		if not ok then
			warn("[DeepDive] leaderboard error:", err)
		end
		task.wait(90)
	end
end)

_ = Debris
print("[DeepDive] Server ready! Version " .. Config.Version)
