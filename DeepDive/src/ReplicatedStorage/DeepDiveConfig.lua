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

return Config
