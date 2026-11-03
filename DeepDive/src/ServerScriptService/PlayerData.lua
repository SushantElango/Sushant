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
