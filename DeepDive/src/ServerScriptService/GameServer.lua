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

local Config = require(ReplicatedStorage:WaitForChild("DeepDiveConfig"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local SubBuilder = require(script.Parent:WaitForChild("SubBuilder"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Monsters = require(script.Parent:WaitForChild("Monsters"))

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
