--[[
	DEEP DIVE - CLIENT SCRIPT
	=========================
	WHERE: Explorer > StarterPlayer > StarterPlayerScripts > (+) LocalScript
	Paste this WHOLE file into it. (The server Script from
	DeepDive_Server.lua must be in ServerScriptService.)
]]

--[[
	GameClient  (LocalScript)
	LOCATION: StarterPlayer > StarterPlayerScripts > GameClient

	Everything the player sees and touches:
	  * HUD: coins, depth gauge, hull / oxygen / cargo, leaks, supplies
	  * driving the sub (keyboard, phone buttons, gamepad)
	  * harpoon aiming, sonar pings, patching leaks
	  * darkness, fog and floating particles that grow with depth
	  * shop, crew menu, invites, daily chest, lore logs, tutorial
	The client only SENDS REQUESTS. The server decides coins, loot and damage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local TextChatService = game:GetService("TextChatService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
-- Settings come from the server script (one place to change them)
local Config = ReplicatedStorage:WaitForChild("DeepDiveRemotes"):WaitForChild("GetConfig"):InvokeServer()
function Config.GetZone(depth)
	for i, zone in ipairs(Config.Zones) do
		if depth < zone.Max then
			return zone, i
		end
	end
	return Config.Zones[#Config.Zones], #Config.Zones
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

local remotesFolder = ReplicatedStorage:WaitForChild("DeepDiveRemotes")
local R = setmetatable({}, {
	__index = function(t, k)
		local v = remotesFolder:WaitForChild(k)
		t[k] = v
		return v
	end,
})

local S = Config.SURFACE_Y
local camera = workspace.CurrentCamera
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local data = nil
local meta = { VIP = false, CanSave = true, ServerTime = os.time(), ReceivedAt = os.clock() }
local currentSub, currentSeat, station = nil, nil, nil
local upHeld, downHeld, firing, patchHeld = false, false, false, false
local patchProgress = 0
local lastFire, lastSonar, sonarCooldown = 0, -100, Config.Sonar.CooldownOtherStation
local shake = 0
local tutorialStep = 0
local shopOpen, crewOpen = false, false
local refreshShop, refreshCrew -- set later

------------------------------------------------------------------------
-- UI helpers
------------------------------------------------------------------------
local THEME = {
	BG = Color3.fromRGB(12, 22, 42),
	BG2 = Color3.fromRGB(22, 38, 66),
	BG3 = Color3.fromRGB(32, 54, 90),
	ACCENT = Color3.fromRGB(70, 200, 255),
	GOOD = Color3.fromRGB(80, 220, 120),
	BAD = Color3.fromRGB(255, 85, 85),
	GOLD = Color3.fromRGB(255, 205, 70),
	TEXT = Color3.fromRGB(255, 255, 255),
	DIM = Color3.fromRGB(170, 190, 215),
	SIGNAL = Color3.fromRGB(255, 120, 170),
}
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold

local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 10) })
end

local function stroke(color, thickness, transparency)
	return new("UIStroke", {
		Color = color or THEME.ACCENT,
		Thickness = thickness or 2,
		Transparency = transparency or 0.4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(px)
	return new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
	})
end

local function label(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or BODY_FONT
	props.TextColor3 = props.TextColor3 or THEME.TEXT
	props.TextScaled = props.TextScaled ~= false
	return new("TextLabel", props)
end

local sounds = Instance.new("Folder")
local function playSound(key, volume, pitch)
	local id = Config.Sounds[key]
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.PlaybackSpeed = pitch or 1
	s.Parent = sounds
	s:Play()
	Debris:AddItem(s, 4)
end

local function button(props)
	local color = props.Color or THEME.ACCENT
	props.Color = nil
	props.BackgroundColor3 = color
	props.AutoButtonColor = true
	props.Font = props.Font or TITLE_FONT
	props.TextColor3 = props.TextColor3 or Color3.fromRGB(15, 25, 45)
	props.TextScaled = true
	local b = new("TextButton", props, { corner(10), padding(4) })
	b.Activated:Connect(function()
		playSound("Click", 0.25, 1.6)
	end)
	return b
end

local function lerpColor(a, b, t)
	return a:Lerp(b, math.clamp(t, 0, 1))
end

------------------------------------------------------------------------
-- Screen
------------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "DeepDiveUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = false,
	Parent = player:WaitForChild("PlayerGui"),
})
sounds.Parent = gui
local uiScale = new("UIScale", { Parent = gui })
local function updateScale()
	local vp = camera.ViewportSize
	uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 760), 0.6, 1.15)
end
updateScale()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

-- Low-health red vignette
local vignette = new("Frame", {
	Name = "Vignette",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.BAD,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 0,
	Parent = gui,
})
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, 1),
		NumberSequenceKeypoint.new(0.75, 1),
		NumberSequenceKeypoint.new(1, 0),
	}),
	Parent = vignette,
})
local hitFlash = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.BAD,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 0,
	Parent = gui,
})

------------------------------------------------------------------------
-- Top-left: coins
------------------------------------------------------------------------
local statsPanel = new("Frame", {
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.fromOffset(230, 92),
	BackgroundColor3 = THEME.BG,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { corner(14), stroke(THEME.ACCENT, 2, 0.5), padding(8) })
new("Frame", {
	Size = UDim2.fromOffset(30, 30),
	Position = UDim2.fromOffset(0, 2),
	BackgroundColor3 = THEME.GOLD,
	Parent = statsPanel,
}, {
	corner(15),
	label({ Size = UDim2.fromScale(1, 1), Text = "C", TextColor3 = Color3.fromRGB(120, 80, 0), Font = TITLE_FONT }),
})
local coinsLabel = label({
	Position = UDim2.fromOffset(38, 0),
	Size = UDim2.new(1, -38, 0, 34),
	Text = "0",
	Font = TITLE_FONT,
	TextColor3 = THEME.GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = statsPanel,
})
local bestLabel = label({
	Position = UDim2.fromOffset(0, 38),
	Size = UDim2.new(1, 0, 0, 18),
	Text = "Best dive: 0 m",
	TextColor3 = THEME.DIM,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = statsPanel,
})
local boostLabel = label({
	Position = UDim2.fromOffset(0, 58),
	Size = UDim2.new(1, 0, 0, 18),
	Text = "",
	TextColor3 = THEME.GOOD,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = statsPanel,
})

------------------------------------------------------------------------
-- Top-right: menu buttons
------------------------------------------------------------------------
local menu = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(250, 48),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8),
	}),
})
local shopButton = button({ Text = "SHOP", Size = UDim2.fromOffset(110, 46), Color = THEME.GOLD, Parent = menu })
local crewButton = button({ Text = "CREW", Size = UDim2.fromOffset(110, 46), Color = THEME.ACCENT, Parent = menu })

------------------------------------------------------------------------
-- Top-centre: depth gauge
------------------------------------------------------------------------
local depthPanel = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(240, 84),
	BackgroundColor3 = THEME.BG,
	BackgroundTransparency = 0.2,
	Visible = false,
	Parent = gui,
}, { corner(14), stroke(THEME.ACCENT, 2, 0.5) })
local depthLabel = label({
	Size = UDim2.new(1, 0, 0.58, 0),
	Text = "0 m",
	Font = TITLE_FONT,
	Parent = depthPanel,
})
local zoneLabel = label({
	Position = UDim2.fromScale(0, 0.55),
	Size = UDim2.new(1, 0, 0.24, 0),
	Text = "Sunlit Reef",
	TextColor3 = THEME.ACCENT,
	Parent = depthPanel,
})
local ratingLabel = label({
	Position = UDim2.fromScale(0, 0.78),
	Size = UDim2.new(1, 0, 0.18, 0),
	Text = "Hull rated 210 m",
	TextColor3 = THEME.DIM,
	Parent = depthPanel,
})

-- Right side: depth bar with zones
local BAR_MAX = 700
local depthBar = new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.5, 0),
	Size = UDim2.fromOffset(22, 320),
	BackgroundColor3 = THEME.BG,
	Visible = false,
	Parent = gui,
}, { corner(8), stroke(THEME.ACCENT, 2, 0.5) })
for _, zone in ipairs(Config.Zones) do
	local top = math.min(zone.Min, BAR_MAX) / BAR_MAX
	local bottom = math.min(zone.Max, BAR_MAX) / BAR_MAX
	if bottom > top then
		new("Frame", {
			Position = UDim2.fromScale(0, top),
			Size = UDim2.fromScale(1, bottom - top),
			BackgroundColor3 = zone.Color,
			BackgroundTransparency = zone.Locked and 0.75 or 0.35,
			BorderSizePixel = 0,
			Parent = depthBar,
		})
	end
end
local ratingLine = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(-0.3, 0.3),
	Size = UDim2.new(1.6, 0, 0, 3),
	BackgroundColor3 = THEME.BAD,
	BorderSizePixel = 0,
	Parent = depthBar,
})
local depthMarker = new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(0, 0),
	Size = UDim2.fromOffset(16, 16),
	BackgroundColor3 = THEME.TEXT,
	Rotation = 45,
	Parent = depthBar,
}, { corner(3) })

------------------------------------------------------------------------
-- Left: sub panel
------------------------------------------------------------------------
local subPanel = new("Frame", {
	Position = UDim2.fromOffset(12, 112),
	Size = UDim2.fromOffset(250, 262),
	BackgroundColor3 = THEME.BG,
	BackgroundTransparency = 0.15,
	Visible = false,
	Parent = gui,
}, { corner(14), stroke(THEME.ACCENT, 2, 0.5), padding(10) })
local subTitle = label({
	Size = UDim2.new(1, 0, 0, 22),
	Text = "Your Sub",
	Font = TITLE_FONT,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = subPanel,
})
local stationLabel = label({
	Position = UDim2.fromOffset(0, 22),
	Size = UDim2.new(1, 0, 0, 16),
	Text = "Station: Helm",
	TextColor3 = THEME.ACCENT,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = subPanel,
})

local function makeBar(y, color, text)
	local back = new("Frame", {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundColor3 = THEME.BG3,
		Parent = subPanel,
	}, { corner(8) })
	local fill = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		Parent = back,
	}, { corner(8) })
	local txt = label({
		Size = UDim2.fromScale(1, 1),
		Text = text,
		ZIndex = 2,
		TextStrokeTransparency = 0.4,
		Parent = back,
	})
	new("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3), Parent = txt })
	return { Fill = fill, Text = txt, Color = color }
end

local hpBar = makeBar(44, THEME.GOOD, "HULL")
local o2Bar = makeBar(72, THEME.ACCENT, "AIR")
local cargoLabel = label({
	Position = UDim2.fromOffset(0, 100),
	Size = UDim2.new(1, 0, 0, 20),
	Text = "Cargo 0/8  -  0 coins",
	TextColor3 = THEME.GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = subPanel,
})
local leakLabel = label({
	Position = UDim2.fromOffset(0, 122),
	Size = UDim2.new(1, 0, 0, 20),
	Text = "",
	TextColor3 = THEME.BAD,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = subPanel,
})

-- Station switcher
local stationRow = new("Frame", {
	Position = UDim2.fromOffset(0, 146),
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	Parent = subPanel,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
	}),
})
local stationButtons = {}

-- Supplies
local supplyRow = new("Frame", {
	Position = UDim2.fromOffset(0, 182),
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundTransparency = 1,
	Parent = subPanel,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
	}),
})
local kitButton = button({
	Text = "[1] Repair Kit x0",
	Size = UDim2.new(0.5, -3, 1, 0),
	Color = THEME.GOOD,
	Font = BODY_FONT,
	Parent = supplyRow,
})
local o2Button = button({
	Text = "[2] Oxygen x0",
	Size = UDim2.new(0.5, -3, 1, 0),
	Color = THEME.ACCENT,
	Font = BODY_FONT,
	Parent = supplyRow,
})
local leaveButton = button({
	Position = UDim2.fromOffset(0, 222),
	Size = UDim2.new(1, 0, 0, 30),
	Text = "LEAVE SUB",
	Color = THEME.BG3,
	TextColor3 = THEME.TEXT,
	Parent = subPanel,
})
local emergencyButton = button({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -116),
	Size = UDim2.fromOffset(260, 44),
	Text = "EMERGENCY SURFACE (Robux)",
	Color = THEME.BAD,
	TextColor3 = THEME.TEXT,
	Visible = false,
	Parent = gui,
})

------------------------------------------------------------------------
-- Bottom: hint + action buttons
------------------------------------------------------------------------
local hintLabel = label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(760, 24),
	Text = "",
	TextColor3 = THEME.DIM,
	TextStrokeTransparency = 0.5,
	Parent = gui,
})

local actions = new("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -40),
	Size = UDim2.fromOffset(250, 210),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
local function actionButton(text, color, pos, size)
	return button({
		Text = text,
		Position = pos,
		Size = size or UDim2.fromOffset(84, 84),
		Color = color,
		Parent = actions,
	})
end
local fireButton = actionButton("FIRE", THEME.BAD, UDim2.fromOffset(160, 120), UDim2.fromOffset(90, 90))
fireButton.TextColor3 = THEME.TEXT
local sonarButton = actionButton("SONAR", THEME.ACCENT, UDim2.fromOffset(68, 136), UDim2.fromOffset(74, 74))
local patchButton = actionButton("PATCH", THEME.GOLD, UDim2.fromOffset(160, 24), UDim2.fromOffset(90, 84))
local upButton = actionButton("UP", THEME.BG3, UDim2.fromOffset(0, 40), UDim2.fromOffset(60, 60))
local downButton = actionButton("DOWN", THEME.BG3, UDim2.fromOffset(0, 108), UDim2.fromOffset(60, 60))
upButton.TextColor3 = THEME.TEXT
downButton.TextColor3 = THEME.TEXT
for _, b in ipairs({ fireButton, sonarButton }) do
	b:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
end
local sonarCdFill = new("Frame", {
	Size = UDim2.fromScale(1, 0),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	ZIndex = 3,
	Parent = sonarButton,
}, { corner(40) })
local patchFill = new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromScale(0, 0.12),
	BackgroundColor3 = THEME.GOOD,
	ZIndex = 3,
	Parent = patchButton,
}, { corner(4) })

------------------------------------------------------------------------
-- Toasts
------------------------------------------------------------------------
local toastHolder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 100),
	Size = UDim2.fromOffset(520, 220),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	new("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local toastOrder = 0
local KIND_COLORS = {
	info = THEME.ACCENT,
	good = THEME.GOOD,
	bad = THEME.BAD,
	loot = THEME.GOLD,
	signal = THEME.SIGNAL,
}
local function toast(text, kind)
	toastOrder += 1
	local color = KIND_COLORS[kind] or THEME.ACCENT
	local items = {}
	for _, c in ipairs(toastHolder:GetChildren()) do
		if c:IsA("Frame") then
			table.insert(items, c)
		end
	end
	if #items >= 4 then
		table.sort(items, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		items[1]:Destroy()
	end
	local frame = new("Frame", {
		Size = UDim2.fromOffset(500, 34),
		BackgroundColor3 = THEME.BG,
		BackgroundTransparency = 0.1,
		LayoutOrder = toastOrder,
		Parent = toastHolder,
	}, { corner(10), stroke(color, 2, 0.2), padding(6) })
	local l = label({ Size = UDim2.fromScale(1, 1), Text = text, TextColor3 = color, Parent = frame })
	task.delay(4, function()
		if frame.Parent then
			TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.wait(0.45)
			frame:Destroy()
		end
	end)
end

------------------------------------------------------------------------
-- Popups (generic modal card)
------------------------------------------------------------------------
local function popup(title, lines, buttons, color, autoClose)
	color = color or THEME.ACCENT
	local frame = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(440, 120 + #lines * 30),
		BackgroundColor3 = THEME.BG,
		ZIndex = 20,
		Parent = gui,
	}, { corner(18), stroke(color, 3, 0), padding(14) })
	label({
		Size = UDim2.new(1, 0, 0, 40),
		Text = title,
		Font = TITLE_FONT,
		TextColor3 = color,
		ZIndex = 21,
		Parent = frame,
	})
	for i, line in ipairs(lines) do
		label({
			Position = UDim2.fromOffset(0, 44 + (i - 1) * 30),
			Size = UDim2.new(1, 0, 0, 26),
			Text = line,
			ZIndex = 21,
			TextWrapped = true,
			Parent = frame,
		})
	end
	local row = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = frame,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
	})
	local function close()
		if frame.Parent then
			frame:Destroy()
		end
	end
	for _, b in ipairs(buttons or { { "OK", nil, color } }) do
		local btn = button({
			Text = b[1],
			Size = UDim2.fromOffset(150, 40),
			Color = b[3] or color,
			ZIndex = 22,
			Parent = row,
		})
		btn.Activated:Connect(function()
			close()
			if b[2] then
				b[2]()
			end
		end)
	end
	frame.Size = UDim2.fromOffset(440, 40)
	TweenService
		:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(440, 120 + #lines * 30) })
		:Play()
	if autoClose then
		task.delay(autoClose, close)
	end
	return frame, close
end

------------------------------------------------------------------------
-- Modal windows (shop, crew)
------------------------------------------------------------------------
local function window(titleText, color)
	local frame = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(760, 500),
		BackgroundColor3 = THEME.BG,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	}, { corner(18), stroke(color, 3, 0.1), padding(12) })
	label({
		Size = UDim2.new(1, -60, 0, 40),
		Text = titleText,
		Font = TITLE_FONT,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
		Parent = frame,
	})
	local closeBtn = button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(44, 40),
		Text = "X",
		Color = THEME.BAD,
		TextColor3 = THEME.TEXT,
		ZIndex = 12,
		Parent = frame,
	})
	return frame, closeBtn
end

-- SHOP -------------------------------------------------------------------
local shopFrame, shopClose = window("SALVAGE SHOP", THEME.GOLD)
local shopCoins = label({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -54, 0, 4),
	Size = UDim2.fromOffset(220, 32),
	Text = "0 coins",
	TextColor3 = THEME.GOLD,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 11,
	Parent = shopFrame,
})
local tabRow = new("Frame", {
	Position = UDim2.fromOffset(0, 48),
	Size = UDim2.new(1, 0, 0, 38),
	BackgroundTransparency = 1,
	ZIndex = 11,
	Parent = shopFrame,
}, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }),
})
local shopScroll = new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 94),
	Size = UDim2.new(1, 0, 1, -94),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 11,
	Parent = shopFrame,
}, {
	new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -8, 0, 124),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
	new("UIPadding", { PaddingRight = UDim.new(0, 10) }),
})
local currentTab = "Upgrades"
local tabButtons = {}
for _, tabName in ipairs({ "Upgrades", "Supplies", "Paint", "Robux" }) do
	local b = button({
		Text = tabName,
		Size = UDim2.fromOffset(130, 38),
		Color = THEME.BG3,
		TextColor3 = THEME.TEXT,
		ZIndex = 12,
		Parent = tabRow,
	})
	tabButtons[tabName] = b
	b.Activated:Connect(function()
		currentTab = tabName
		refreshShop()
	end)
end

local function describeLevel(key, lvl)
	if not lvl then
		return ""
	end
	if lvl.ComingSoon then
		return "Coming in a future update"
	end
	if key == "Hull" then
		return ("%d HP  -  dive to %d m  -  %d seats"):format(lvl.MaxHP, lvl.MaxDepth, #lvl.Seats)
	elseif key == "Engine" then
		return ("Speed %d  -  Turning %.2f"):format(lvl.Speed, lvl.Turn)
	elseif key == "Lights" then
		return ("Beam %d m  -  Width %d"):format(lvl.Range, lvl.Angle)
	elseif key == "Cargo" then
		return ("%d cargo slots"):format(lvl.Slots)
	elseif key == "Plating" then
		return ("-%d%% damage  -  +%d HP"):format(math.floor(lvl.Armor * 100 + 0.5), lvl.BonusHP)
	elseif key == "Harpoon" then
		if lvl.Damage <= 0 then
			return "No weapon"
		end
		return ("%d damage  -  %.1fs reload"):format(lvl.Damage, lvl.Cooldown)
	end
	return ""
end

local function shopCard(order, title, sub1, sub2, btnText, btnColor, onBuy, swatch)
	local card = new("Frame", {
		BackgroundColor3 = THEME.BG2,
		LayoutOrder = order,
		ZIndex = 12,
		Parent = shopScroll,
	}, { corner(12), stroke(THEME.BG3, 2, 0), padding(10) })
	local textX = 0
	if swatch then
		new("Frame", {
			Size = UDim2.fromOffset(56, 56),
			BackgroundColor3 = swatch,
			ZIndex = 13,
			Parent = card,
		}, { corner(28), stroke(THEME.TEXT, 2, 0.3) })
		textX = 64
	end
	label({
		Position = UDim2.fromOffset(textX, 0),
		Size = UDim2.new(1, -textX, 0, 26),
		Text = title,
		Font = TITLE_FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = card,
	})
	label({
		Position = UDim2.fromOffset(textX, 28),
		Size = UDim2.new(1, -textX, 0, 18),
		Text = sub1 or "",
		TextColor3 = THEME.DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = card,
	})
	label({
		Position = UDim2.fromOffset(textX, 48),
		Size = UDim2.new(1, -textX, 0, 18),
		Text = sub2 or "",
		TextColor3 = THEME.ACCENT,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = card,
	})
	local b = button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(150, 34),
		Text = btnText,
		Color = btnColor,
		ZIndex = 13,
		Parent = card,
	})
	if onBuy then
		b.Activated:Connect(onBuy)
	else
		b.AutoButtonColor = false
	end
	return card
end

local productPrices = {}
local function getPrice(id, infoType)
	if productPrices[id] ~= nil then
		return productPrices[id]
	end
	productPrices[id] = false
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, infoType)
		end)
		if ok and info and info.PriceInRobux then
			productPrices[id] = info.PriceInRobux
			if shopOpen and currentTab == "Robux" then
				refreshShop()
			end
		end
	end)
	return false
end

function refreshShop()
	for name, b in pairs(tabButtons) do
		b.BackgroundColor3 = (name == currentTab) and THEME.GOLD or THEME.BG3
		b.TextColor3 = (name == currentTab) and Color3.fromRGB(15, 25, 45) or THEME.TEXT
	end
	for _, c in ipairs(shopScroll:GetChildren()) do
		if c:IsA("Frame") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	if not data then
		return
	end
	shopCoins.Text = Config.FormatNumber(data.Coins) .. " coins"
	local coins = data.Coins
	if currentTab == "Upgrades" then
		for i, key in ipairs(Config.UpgradeOrder) do
			local up = Config.Upgrades[key]
			local lvl = data.Upgrades[key] or 1
			local cur = up.Levels[lvl]
			local nxt = up.Levels[lvl + 1]
			local title = up.DisplayName .. ": " .. cur.Name
			local sub1 = describeLevel(key, cur)
			if not nxt then
				shopCard(i, title, sub1, "Fully upgraded!", "MAXED", THEME.BG3, nil)
			elseif nxt.ComingSoon then
				shopCard(i, title, sub1, "Next: " .. nxt.Name, "SOON", THEME.BG3, nil)
			else
				local afford = coins >= nxt.Cost
				shopCard(
					i,
					title,
					sub1,
					"Next: " .. nxt.Name .. "  (" .. describeLevel(key, nxt) .. ")",
					Config.FormatNumber(nxt.Cost),
					afford and THEME.GOOD or THEME.BG3,
					function()
						R.Buy:FireServer("Upgrade", key)
					end
				)
			end
		end
	elseif currentTab == "Supplies" then
		for i, key in ipairs(Config.SupplyOrder) do
			local sup = Config.Supplies[key]
			local have = data.Supplies[key] or 0
			shopCard(
				i,
				sup.DisplayName,
				sup.Description,
				("You have %d / %d"):format(have, sup.Max),
				Config.FormatNumber(sup.Cost),
				(coins >= sup.Cost and have < sup.Max) and THEME.GOOD or THEME.BG3,
				function()
					R.Buy:FireServer("Supply", key)
				end
			)
		end
	elseif currentTab == "Paint" then
		local order = 0
		for _, p in ipairs(Config.Paints) do
			order += 1
			local owned = data.OwnedPaints[p.Id]
			local equipped = data.Paint == p.Id
			local text = equipped and "EQUIPPED" or (owned and "EQUIP" or Config.FormatNumber(p.Cost))
			local color = equipped and THEME.BG3 or ((owned or coins >= p.Cost) and THEME.GOOD or THEME.BG3)
			shopCard(order, p.Name, "Hull paint", p.Shiny and "Shiny!" or "", text, color, function()
				R.Buy:FireServer("Paint", p.Id)
			end, p.Color)
		end
		for _, l in ipairs(Config.LightColors) do
			order += 1
			local owned = data.OwnedLights[l.Id]
			local equipped = data.LightColor == l.Id
			local text = equipped and "EQUIPPED" or (owned and "EQUIP" or Config.FormatNumber(l.Cost))
			local color = equipped and THEME.BG3 or ((owned or coins >= l.Cost) and THEME.GOOD or THEME.BG3)
			shopCard(order, l.Name, "Headlight colour", "", text, color, function()
				R.Buy:FireServer("Light", l.Id)
			end, l.Color)
		end
	elseif currentTab == "Robux" then
		local order = 0
		local m = Config.Monetization
		if m.VIPPassId ~= 0 then
			order += 1
			local price = getPrice(m.VIPPassId, Enum.InfoType.GamePass)
			shopCard(
				order,
				"VIP Captain Pass",
				"+" .. m.VIPCargoBonus .. " cargo slots, gold name, [VIP] chat tag",
				meta.VIP and "You own this!" or "One-time purchase",
				meta.VIP and "OWNED" or (price and ("R$ " .. price) or "BUY"),
				meta.VIP and THEME.BG3 or THEME.GOOD,
				not meta.VIP
						and function()
							MarketplaceService:PromptGamePassPurchase(player, m.VIPPassId)
						end
					or nil
			)
		end
		for _, p in ipairs(m.Products) do
			if p.Id ~= 0 and not p.Emergency then
				order += 1
				local price = getPrice(p.Id, Enum.InfoType.Product)
				shopCard(
					order,
					p.Name,
					p.Coins and "Skip the grind" or "Make every dive count",
					"",
					price and ("R$ " .. price) or "BUY",
					THEME.GOOD,
					function()
						MarketplaceService:PromptProductPurchase(player, p.Id)
					end
				)
			end
		end
		if order == 0 then
			label({
				Size = UDim2.new(1, 0, 0, 40),
				Text = "Robux items aren't set up yet. Everything in Deep Dive can be earned by playing!",
				TextColor3 = THEME.DIM,
				ZIndex = 13,
				Parent = shopScroll,
			})
		end
	end
end

local function canShopNow()
	if currentSub and currentSub.PrimaryPart then
		local depth = S - currentSub.PrimaryPart.Position.Y
		if depth > Config.SurfaceDepth + 1 then
			return false
		end
	end
	return true
end

local function openShop()
	if not canShopNow() then
		toast("Surface first to use the shop!", "bad")
		return
	end
	shopOpen = true
	shopFrame.Visible = true
	refreshShop()
	if tutorialStep == 5 then
		tutorialStep = 6
	end
end
shopButton.Activated:Connect(function()
	if shopOpen then
		shopOpen = false
		shopFrame.Visible = false
	else
		openShop()
	end
end)
shopClose.Activated:Connect(function()
	shopOpen = false
	shopFrame.Visible = false
end)

-- CREW -------------------------------------------------------------------
local crewFrame, crewClose = window("CREW", THEME.ACCENT)
crewFrame.Size = UDim2.fromOffset(520, 460)
local openToggle = button({
	Position = UDim2.fromOffset(0, 48),
	Size = UDim2.new(1, 0, 0, 36),
	Text = "Open crew: OFF (only friends + invited can board)",
	Color = THEME.BG3,
	TextColor3 = THEME.TEXT,
	Font = BODY_FONT,
	ZIndex = 12,
	Parent = crewFrame,
})
local crewScroll = new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 92),
	Size = UDim2.new(1, 0, 1, -92),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 11,
	Parent = crewFrame,
}, {
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIPadding", { PaddingRight = UDim.new(0, 10) }),
})

local function crewRow(order, text, btnText, btnColor, onClick)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = THEME.BG2,
		LayoutOrder = order,
		ZIndex = 12,
		Parent = crewScroll,
	}, { corner(10), padding(6) })
	label({
		Size = UDim2.new(1, -130, 1, 0),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = row,
	})
	if btnText then
		local b = button({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 120, 1, 0),
			Text = btnText,
			Color = btnColor,
			ZIndex = 13,
			Parent = row,
		})
		if onClick then
			b.Activated:Connect(onClick)
		end
	end
end

local function crewHeader(order, text)
	label({
		Size = UDim2.new(1, 0, 0, 26),
		Text = text,
		Font = TITLE_FONT,
		TextColor3 = THEME.ACCENT,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		ZIndex = 12,
		Parent = crewScroll,
	})
end

function refreshCrew()
	for _, c in ipairs(crewScroll:GetChildren()) do
		if c:IsA("Frame") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local open = player:GetAttribute("CrewOpen") == true
	openToggle.Text = open and "Open crew: ON (anyone can board your sub)"
		or "Open crew: OFF (only friends + invited can board)"
	openToggle.BackgroundColor3 = open and THEME.GOOD or THEME.BG3
	local order = 0
	order += 1
	crewHeader(order, "Aboard your sub")
	local any = false
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("SubOwnerId") == player.UserId then
			any = true
			order += 1
			local stationName = p:GetAttribute("Station") or "?"
			if p == player then
				crewRow(order, p.DisplayName .. " (you) - " .. stationName)
			else
				crewRow(order, p.DisplayName .. " - " .. stationName, "Drop off", THEME.BAD, function()
					R.CrewKick:FireServer(p.UserId)
				end)
			end
		end
	end
	if not any then
		order += 1
		crewRow(order, "Nobody yet. Invite players below!")
	end
	order += 1
	crewHeader(order, "Invite players (extra crew = +15% loot each)")
	local others = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			others += 1
			order += 1
			local where = p:GetAttribute("SubOwnerId") and " (in a sub)" or ""
			crewRow(order, p.DisplayName .. where, "Invite", THEME.GOOD, function()
				R.CrewInvite:FireServer(p.UserId)
			end)
		end
	end
	if others == 0 then
		order += 1
		crewRow(order, "No other players here yet. Invite friends to the game!")
	end
end

crewButton.Activated:Connect(function()
	crewOpen = not crewOpen
	crewFrame.Visible = crewOpen
	if crewOpen then
		refreshCrew()
	end
end)
crewClose.Activated:Connect(function()
	crewOpen = false
	crewFrame.Visible = false
end)
openToggle.Activated:Connect(function()
	R.SetCrewOpen:FireServer(not (player:GetAttribute("CrewOpen") == true))
end)
player:GetAttributeChangedSignal("CrewOpen"):Connect(function()
	if crewOpen then
		refreshCrew()
	end
end)
Players.PlayerAdded:Connect(function(p)
	p:GetAttributeChangedSignal("SubOwnerId"):Connect(function()
		if crewOpen then
			refreshCrew()
		end
	end)
	if crewOpen then
		refreshCrew()
	end
end)
for _, p in ipairs(Players:GetPlayers()) do
	p:GetAttributeChangedSignal("SubOwnerId"):Connect(function()
		if crewOpen then
			refreshCrew()
		end
	end)
end
Players.PlayerRemoving:Connect(function()
	if crewOpen then
		task.defer(refreshCrew)
	end
end)

------------------------------------------------------------------------
-- Tutorial
------------------------------------------------------------------------
local TUTORIAL = {
	"Welcome to DEEP DIVE! Walk to your sub at your berth (your name is on the sign) and press E to board.",
	isTouch and "Use the joystick to drive. Hold DOWN to dive and UP to rise."
		or "W/S = forward/back, A/D = turn, Q = dive, E = rise. Go down!",
	"See the glowing things on the sea floor? That's SALVAGE. Drive into it to collect it.",
	"Loot only counts once you SURFACE. Rise to the top to cash in your haul!",
	"Nice haul! Open the SHOP to buy a Harpoon Turret and upgrade your sub.",
}
local tutorialFrame = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -44),
	Size = UDim2.fromOffset(600, 64),
	BackgroundColor3 = THEME.BG,
	BackgroundTransparency = 0.05,
	Visible = false,
	Parent = gui,
}, { corner(14), stroke(THEME.GOLD, 3, 0), padding(8) })
local tutorialText = label({
	Size = UDim2.new(1, -80, 1, 0),
	Text = "",
	TextColor3 = THEME.GOLD,
	TextWrapped = true,
	Parent = tutorialFrame,
})
local skipTutorial = button({
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(1, 0.5),
	Size = UDim2.fromOffset(70, 34),
	Text = "Skip",
	Color = THEME.BG3,
	TextColor3 = THEME.TEXT,
	Parent = tutorialFrame,
})
local function finishTutorial()
	tutorialStep = 99
	tutorialFrame.Visible = false
	R.TutorialDone:FireServer()
end
skipTutorial.Activated:Connect(finishTutorial)
local function setTutorialStep(n)
	if tutorialStep >= 99 then
		return
	end
	tutorialStep = n
	if n > #TUTORIAL then
		finishTutorial()
		return
	end
	tutorialText.Text = TUTORIAL[n]
	tutorialFrame.Visible = true
end

------------------------------------------------------------------------
-- Data updates
------------------------------------------------------------------------
local function boostRemaining()
	if not data then
		return 0
	end
	local now = meta.ServerTime + (os.clock() - meta.ReceivedAt)
	return math.max(0, (data.BoostUntil or 0) - now)
end

local function onData(newData, newMeta)
	local first = data == nil
	data = newData
	meta.VIP = newMeta.VIP
	meta.CanSave = newMeta.CanSave
	meta.ServerTime = newMeta.ServerTime
	meta.ReceivedAt = os.clock()
	coinsLabel.Text = Config.FormatNumber(data.Coins)
	bestLabel.Text = "Best dive: " .. Config.FormatNumber(data.BestDepth) .. " m"
	kitButton.Text = "[1] Repair Kit x" .. (data.Supplies.RepairKit or 0)
	o2Button.Text = "[2] Oxygen x" .. (data.Supplies.OxygenTank or 0)
	if isTouch then
		kitButton.Text = "Repair Kit x" .. (data.Supplies.RepairKit or 0)
		o2Button.Text = "Oxygen x" .. (data.Supplies.OxygenTank or 0)
	end
	if shopOpen then
		refreshShop()
	end
	if first and not data.TutorialDone then
		setTutorialStep(currentSub and 2 or 1)
	end
end
R.DataUpdate.OnClientEvent:Connect(onData)
R.RequestData:FireServer()

------------------------------------------------------------------------
-- Server messages
------------------------------------------------------------------------
R.Notify.OnClientEvent:Connect(function(text, kind)
	toast(text, kind)
	if kind == "signal" then
		playSound("Ping", 0.6, 0.7)
	end
end)

R.OpenShop.OnClientEvent:Connect(openShop)

R.CrewInvitePrompt.OnClientEvent:Connect(function(ownerId, ownerName)
	playSound("Ping", 0.5, 1.2)
	popup("CREW INVITE", { ownerName .. " wants you on their crew!", "Extra crew members earn bonus loot." }, {
		{
			"JOIN",
			function()
				R.CrewRespond:FireServer(ownerId, true)
			end,
			THEME.GOOD,
		},
		{
			"NO THANKS",
			function()
				R.CrewRespond:FireServer(ownerId, false)
			end,
			THEME.BG3,
		},
	}, THEME.ACCENT, 25)
end)

R.Daily.OnClientEvent:Connect(function(streak, coins, kit)
	task.wait(2)
	local lines = { ("Day %d streak!"):format(streak), "+" .. coins .. " coins" }
	if kit then
		table.insert(lines, "+1 Repair Kit bonus!")
	end
	table.insert(lines, "Come back tomorrow for a bigger chest.")
	popup("DAILY CHEST", lines, { { "COLLECT", nil, THEME.GOLD } }, THEME.GOLD)
	playSound("Coin", 0.6, 1.3)
end)

R.Lore.OnClientEvent:Connect(function(index)
	local entry = Config.Lore[index]
	if not entry then
		return
	end
	local frame = popup(
		"EXPEDITION LOG FOUND",
		{ entry.Title, "", "", "" },
		{ { "CLOSE", nil, THEME.SIGNAL } },
		THEME.SIGNAL
	)
	label({
		Position = UDim2.fromOffset(0, 74),
		Size = UDim2.new(1, 0, 0, 84),
		Text = entry.Text,
		Font = Enum.Font.Gotham,
		TextColor3 = THEME.DIM,
		TextWrapped = true,
		ZIndex = 21,
		Parent = frame,
	})
end)

R.Surfaced.OnClientEvent:Connect(function(info)
	playSound("Coin", 0.7, 1)
	local lines = {}
	local itemParts = {}
	for name, count in pairs(info.Items) do
		table.insert(itemParts, name .. " x" .. count)
	end
	if #itemParts > 0 then
		table.insert(lines, table.concat(itemParts, ",  "))
	end
	if info.Bonus > 0 then
		table.insert(lines, ("Crew bonus: +%d%%"):format(math.floor(info.Bonus * 100 + 0.5)))
	end
	if info.Boost then
		table.insert(lines, "2x loot boost!")
	end
	table.insert(lines, "+" .. Config.FormatNumber(info.Payout) .. " coins")
	if info.Record then
		table.insert(lines, "NEW DEPTH RECORD: " .. info.Depth .. " m!")
	end
	popup(info.Payout > 0 and "HAUL BANKED!" or "SURFACED", lines, { { "NICE!", nil, THEME.GOOD } }, THEME.GOOD, 7)
	if tutorialStep == 4 then
		setTutorialStep(5)
		task.delay(12, function()
			if tutorialStep == 5 then
				finishTutorial()
			end
		end)
	end
end)

R.Sunk.OnClientEvent:Connect(function(info)
	shake = 1.5
	popup("SUB DESTROYED", {
		"Taken down by " .. tostring(info.Cause) .. ".",
		"Lost " .. Config.FormatNumber(info.Lost) .. " coins of salvage.",
		"Insurance paid " .. Config.FormatNumber(info.Insurance) .. ".",
		"A new sub is waiting at your berth.",
	}, { { "OK", nil, THEME.BAD } }, THEME.BAD)
end)

R.SubHit.OnClientEvent:Connect(function(amount)
	shake = math.min(1.4, shake + 0.3 + amount / 15)
	hitFlash.BackgroundTransparency = 0.6
	TweenService:Create(hitFlash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	playSound("Hit", 0.6, 0.8)
end)

-- Floating "+value" text where loot was picked up
R.LootFX.OnClientEvent:Connect(function(name, value, pos, color)
	toast("+" .. value .. "  " .. name, "loot")
	playSound("Coin", 0.5, 1.5)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = workspace
	local bb = new("BillboardGui", {
		Size = UDim2.fromOffset(120, 40),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = anchor,
	})
	local l = label({
		Size = UDim2.fromScale(1, 1),
		Text = "+" .. value,
		Font = TITLE_FONT,
		TextColor3 = color or THEME.GOLD,
		TextStrokeTransparency = 0.2,
		Parent = bb,
	})
	TweenService:Create(bb, TweenInfo.new(1.2), { StudsOffset = Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.3)
	if tutorialStep == 3 then
		setTutorialStep(4)
	end
end)

------------------------------------------------------------------------
-- Harpoon visuals (everyone sees every shot)
------------------------------------------------------------------------
local fxFolder = Instance.new("Folder")
fxFolder.Name = "DeepDiveLocalFX"
fxFolder.Parent = workspace

R.HarpoonFX.OnClientEvent:Connect(function(subModel, origin, hitPos, hit)
	if (origin - camera.CFrame.Position).Magnitude > 450 then
		return
	end
	local dir = hitPos - origin
	local dist = dir.Magnitude
	if dist < 0.5 then
		return
	end
	dir = dir.Unit
	local travel = dist / 220
	local spear = Instance.new("Part")
	spear.Anchored = true
	spear.CanCollide = false
	spear.CanQuery = false
	spear.CastShadow = false
	spear.Size = Vector3.new(0.25, 0.25, 2.8)
	spear.Material = Enum.Material.Metal
	spear.Color = Color3.fromRGB(200, 200, 210)
	spear.CFrame = CFrame.lookAt(origin, origin + dir)
	spear.Parent = fxFolder
	local tipGlow = Instance.new("PointLight")
	tipGlow.Range = 6
	tipGlow.Color = Color3.fromRGB(255, 240, 200)
	tipGlow.Parent = spear
	local tail = Instance.new("Attachment")
	tail.Position = Vector3.new(0, 0, 1.4)
	tail.Parent = spear
	local barrel = subModel and subModel:FindFirstChild("Barrel")
	local tip = barrel and barrel:FindFirstChild("Tip")
	if tip then
		local rope = Instance.new("Beam")
		rope.Attachment0 = tip
		rope.Attachment1 = tail
		rope.Width0 = 0.08
		rope.Width1 = 0.08
		rope.FaceCamera = true
		rope.Color = ColorSequence.new(Color3.fromRGB(150, 120, 80))
		rope.LightEmission = 0.3
		rope.Parent = spear
	end
	TweenService:Create(spear, TweenInfo.new(travel, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(hitPos, hitPos + dir),
	}):Play()
	playSound("Harpoon", 0.5, 1.1)
	task.delay(travel, function()
		if hit then
			playSound("Hit", 0.5, 1.3)
		end
		task.wait(0.25)
		spear:Destroy()
	end)
end)

------------------------------------------------------------------------
-- Sonar pings
------------------------------------------------------------------------
local function marker(adornee, text, color)
	local bb = new("BillboardGui", {
		Size = UDim2.fromOffset(70, 34),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Adornee = adornee,
		Parent = player.PlayerGui,
	})
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = color,
		Parent = bb,
	}, { corner(6), stroke(Color3.new(0, 0, 0), 1, 0.3) })
	label({
		Position = UDim2.fromOffset(0, 13),
		Size = UDim2.new(1, 0, 0, 18),
		Text = text,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
		Parent = bb,
	})
	Debris:AddItem(bb, Config.Sonar.MarkerTime)
end

R.SonarPing.OnClientEvent:Connect(function(subModel, radius, cd)
	sonarCooldown = cd
	lastSonar = os.clock()
	local root = subModel and subModel.PrimaryPart
	if not root then
		return
	end
	playSound("Ping", 0.7, 0.9)
	local center = root.Position
	-- expanding ring
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Ball
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Material = Enum.Material.ForceField
	ring.Color = THEME.ACCENT
	ring.Size = Vector3.new(4, 4, 4)
	ring.CFrame = CFrame.new(center)
	ring.Parent = fxFolder
	TweenService:Create(ring, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {
		Size = Vector3.new(radius * 2, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 1.3)

	local root2 = workspace:FindFirstChild("DeepDive")
	if not root2 then
		return
	end
	local found = 0
	for _, loot in ipairs(root2.Loot:GetChildren()) do
		local p = loot.PrimaryPart
		if p and (p.Position - center).Magnitude <= radius then
			found += 1
			marker(p, "$" .. tostring(loot:GetAttribute("LootValue") or "?"), THEME.GOLD)
		end
	end
	local monsterCount = 0
	local monsters = root2:FindFirstChild("Monsters")
	if monsters then
		for _, m in ipairs(monsters:GetChildren()) do
			local p = m.PrimaryPart
			if p and (p.Position - center).Magnitude <= radius then
				monsterCount += 1
				marker(p, "!", THEME.BAD)
			end
		end
	end
	toast(("Sonar: %d salvage, %d monsters nearby"):format(found, monsterCount), "info")
end)

------------------------------------------------------------------------
-- Sub seat tracking
------------------------------------------------------------------------
local function subStations(sub)
	local list = {}
	for _, c in ipairs(sub:GetChildren()) do
		if (c:IsA("Seat") or c:IsA("VehicleSeat")) and c:GetAttribute("Station") then
			table.insert(list, c)
		end
	end
	table.sort(list, function(a, b)
		local order = { Helm = 1, Turret = 2, Sonar = 3, Repair = 4 }
		return (order[a:GetAttribute("Station")] or 9) < (order[b:GetAttribute("Station")] or 9)
	end)
	return list
end

local function rebuildStationButtons()
	for _, b in ipairs(stationButtons) do
		b:Destroy()
	end
	stationButtons = {}
	if not currentSub then
		return
	end
	local seats = subStations(currentSub)
	for _, seat in ipairs(seats) do
		local st = seat:GetAttribute("Station")
		local b = button({
			Text = st,
			Size = UDim2.new(1 / #seats, -4, 1, 0),
			Color = THEME.BG3,
			TextColor3 = THEME.TEXT,
			Font = BODY_FONT,
			Parent = stationRow,
		})
		b:SetAttribute("Station", st)
		b.Activated:Connect(function()
			R.SwitchStation:FireServer(st)
		end)
		table.insert(stationButtons, b)
	end
end

local function sinkAction()
	return Enum.ContextActionResult.Sink
end

local controlsBound = false
local function bindControls()
	if controlsBound then
		return
	end
	controlsBound = true
	local P = 3000
	ContextActionService:BindActionAtPriority("DD_Up", function(_, state)
		upHeld = state == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Sink
	end, false, P, Enum.KeyCode.E, Enum.KeyCode.Space, Enum.KeyCode.ButtonR1)
	ContextActionService:BindActionAtPriority("DD_Down", function(_, state)
		downHeld = state == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Sink
	end, false, P, Enum.KeyCode.Q, Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.ButtonL1)
	ContextActionService:BindActionAtPriority("DD_Sonar", function(_, state)
		if state == Enum.UserInputState.Begin then
			R.Sonar:FireServer()
		end
		return Enum.ContextActionResult.Sink
	end, false, P, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
	ContextActionService:BindActionAtPriority("DD_Patch", function(_, state)
		patchHeld = state == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Sink
	end, false, P, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	ContextActionService:BindActionAtPriority("DD_Kit", function(_, state)
		if state == Enum.UserInputState.Begin then
			R.UseSupply:FireServer("RepairKit")
		end
		return Enum.ContextActionResult.Sink
	end, false, P, Enum.KeyCode.One)
	ContextActionService:BindActionAtPriority("DD_O2", function(_, state)
		if state == Enum.UserInputState.Begin then
			R.UseSupply:FireServer("OxygenTank")
		end
		return Enum.ContextActionResult.Sink
	end, false, P, Enum.KeyCode.Two)
	ContextActionService:BindActionAtPriority("DD_FirePad", function(_, state)
		firing = state == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Sink
	end, false, P, Enum.KeyCode.ButtonR2)
	-- block the jump key (it would try to open the hatch)
	ContextActionService:BindActionAtPriority("DD_NoJump", sinkAction, false, P - 1, Enum.PlayerActions.CharacterJump)
end

local function unbindControls()
	if not controlsBound then
		return
	end
	controlsBound = false
	for _, name in ipairs({ "DD_Up", "DD_Down", "DD_Sonar", "DD_Patch", "DD_Kit", "DD_O2", "DD_FirePad", "DD_NoJump" }) do
		ContextActionService:UnbindAction(name)
	end
	upHeld, downHeld, firing, patchHeld = false, false, false, false
end

local function onSeatChanged(seat)
	local sub = seat and seat.Parent
	if seat and sub and sub:GetAttribute("IsSub") and seat:GetAttribute("Station") then
		local wasIn = currentSub ~= nil
		currentSub = sub
		currentSeat = seat
		station = seat:GetAttribute("Station")
		bindControls()
		subPanel.Visible = true
		actions.Visible = true
		depthPanel.Visible = true
		depthBar.Visible = true
		rebuildStationButtons()
		-- follow the sub itself so the camera never clips inside the hull
		if sub.PrimaryPart then
			camera.CameraSubject = sub.PrimaryPart
		end
		-- the sub is full of water... but you're sitting, not swimming!
		local myHum = seat.Occupant
		if myHum then
			myHum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		end
		if not wasIn then
			player.CameraMaxZoomDistance = 90
			player.CameraMinZoomDistance = 28
			task.delay(0.15, function()
				player.CameraMinZoomDistance = 10
			end)
		end
		if tutorialStep == 1 then
			setTutorialStep(2)
		end
	else
		currentSub, currentSeat, station = nil, nil, nil
		unbindControls()
		subPanel.Visible = false
		actions.Visible = false
		depthPanel.Visible = false
		depthBar.Visible = false
		emergencyButton.Visible = false
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 40
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
			hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
		end
		rebuildStationButtons()
	end
end

local function onCharacter(char)
	local hum = char:WaitForChild("Humanoid")
	hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		onSeatChanged(hum.SeatPart)
	end)
	onSeatChanged(hum.SeatPart)
end
if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------
kitButton.Activated:Connect(function()
	R.UseSupply:FireServer("RepairKit")
end)
o2Button.Activated:Connect(function()
	R.UseSupply:FireServer("OxygenTank")
end)
leaveButton.Activated:Connect(function()
	R.LeaveSub:FireServer()
end)
sonarButton.Activated:Connect(function()
	R.Sonar:FireServer()
end)
emergencyButton.Activated:Connect(function()
	for _, p in ipairs(Config.Monetization.Products) do
		if p.Emergency and p.Id ~= 0 then
			MarketplaceService:PromptProductPurchase(player, p.Id)
		end
	end
end)

local function holdButton(btn, setter)
	btn.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			setter(true)
		end
	end)
	btn.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			setter(false)
		end
	end)
end
local touchUp, touchDown, touchFire, touchPatch = false, false, false, false
holdButton(upButton, function(v)
	touchUp = v
end)
holdButton(downButton, function(v)
	touchDown = v
end)
holdButton(fireButton, function(v)
	touchFire = v
end)
holdButton(patchButton, function(v)
	touchPatch = v
end)

-- Mouse: click to fire
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and currentSub then
		firing = true
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	end
end)

------------------------------------------------------------------------
-- Aiming
------------------------------------------------------------------------
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
aimParams.IgnoreWater = true

local function nearestMonsterInView(maxRange)
	local root = workspace:FindFirstChild("DeepDive")
	local folder = root and root:FindFirstChild("Monsters")
	if not folder or not currentSub or not currentSub.PrimaryPart then
		return nil
	end
	local subPos = currentSub.PrimaryPart.Position
	local look = camera.CFrame.LookVector
	local best, bestScore
	for _, m in ipairs(folder:GetChildren()) do
		local p = m.PrimaryPart
		if p then
			local to = p.Position - subPos
			local dist = to.Magnitude
			if dist < maxRange and dist > 1 then
				local dot = to.Unit:Dot(look)
				if dot > 0.55 then
					local score = dot - dist / maxRange
					if not bestScore or score > bestScore then
						best, bestScore = p.Position, score
					end
				end
			end
		end
	end
	return best
end

local function aimPoint(useMouse)
	local ignore = { currentSub }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	table.insert(ignore, fxFolder)
	aimParams.FilterDescendantsInstances = ignore
	local ray
	if useMouse then
		local m = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(m.X, m.Y)
	else
		local assist = nearestMonsterInView(130)
		if assist then
			return assist
		end
		local vp = camera.ViewportSize
		ray = camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
	end
	local result = workspace:Raycast(ray.Origin, ray.Direction * 300, aimParams)
	return result and result.Position or (ray.Origin + ray.Direction * 160)
end

------------------------------------------------------------------------
-- Driving the sub (only the Helm drives)
------------------------------------------------------------------------
local yaw, vel = 0, Vector3.zero
local pitchS, rollS = 0, 0
local wasPilot = false

local function yawOf(cf)
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

RunService.Heartbeat:Connect(function(dt)
	local sub = currentSub
	local isPilot = sub and station == "Helm" and currentSeat and currentSeat:IsA("VehicleSeat")
	if not isPilot then
		wasPilot = false
		return
	end
	local root = sub.PrimaryPart
	local drive = root and root:FindFirstChild("Drive")
	local steer = root and root:FindFirstChild("Steer")
	if not drive or not steer then
		return
	end
	if not wasPilot then
		wasPilot = true
		yaw = yawOf(root.CFrame)
		vel = root.AssemblyLinearVelocity
	end

	local speed = sub:GetAttribute("Speed") or 16
	local turn = sub:GetAttribute("Turn") or 1
	local slow = 1 - (sub:GetAttribute("Slow") or 0)
	local drag = sub:GetAttribute("Drag") or Vector3.zero
	local throttle = currentSeat.ThrottleFloat
	local steerIn = currentSeat.SteerFloat
	local vertical = ((upHeld or touchUp) and 1 or 0) - ((downHeld or touchDown) and 1 or 0)

	yaw -= steerIn * turn * dt
	local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local target = forward * throttle * speed + Vector3.new(0, vertical * speed * 0.75, 0)
	target = target * slow + drag

	-- stay in the water: float at the surface, never fly
	local y = root.Position.Y
	local top = S + 0.5
	if y > top - 0.5 and target.Y > 0 then
		target = Vector3.new(target.X, math.max(0, (top - y) * 3), target.Z)
	end
	if y > top + 0.5 then
		target = Vector3.new(target.X, (top - y) * 3, target.Z)
	end

	vel = vel:Lerp(target, math.clamp(dt * 2.2, 0, 1))
	drive.VectorVelocity = vel

	local wantPitch = math.rad(9) * vertical * (y < top - 2 and 1 or 0)
	local wantRoll = -math.rad(7) * steerIn * math.clamp(math.abs(throttle) + 0.3, 0, 1)
	pitchS += (wantPitch - pitchS) * math.clamp(dt * 3, 0, 1)
	rollS += (wantRoll - rollS) * math.clamp(dt * 3, 0, 1)
	steer.CFrame = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitchS, 0, rollS)
end)

------------------------------------------------------------------------
-- Firing, patching (every frame)
------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	local sub = currentSub
	if not sub then
		patchProgress = 0
		patchFill.Size = UDim2.fromScale(0, 0.12)
		return
	end
	-- Fire
	local wantsFire = firing or touchFire
	local canShoot = (station == "Turret" or station == "Helm") and (sub:GetAttribute("HarpoonLevel") or 1) > 1
	if wantsFire and canShoot then
		local cd = sub:GetAttribute("HarpoonCooldown") or 1
		if os.clock() - lastFire >= cd then
			lastFire = os.clock()
			local useMouse = firing and UserInputService.MouseEnabled and not touchFire
			R.Fire:FireServer(aimPoint(useMouse))
		end
	elseif wantsFire and (station == "Turret" or station == "Helm") and os.clock() - lastFire > 3 then
		lastFire = os.clock()
		R.Fire:FireServer(aimPoint(false)) -- server replies "buy a harpoon"
	end
	-- Patch
	local leaks = sub:GetAttribute("Leaks") or 0
	if (patchHeld or touchPatch) and leaks > 0 then
		local need = station == "Repair" and Config.Damage.PatchTimeRepairStation or Config.Damage.PatchTimeOtherStation
		patchProgress += dt
		if patchProgress >= need then
			patchProgress = 0
			R.Patch:FireServer()
		end
		patchFill.Size = UDim2.fromScale(math.clamp(patchProgress / need, 0, 1), 0.12)
	else
		patchProgress = 0
		patchFill.Size = UDim2.fromScale(0, 0.12)
	end
end)

------------------------------------------------------------------------
-- Ocean atmosphere: darkness, fog, floating particles
------------------------------------------------------------------------
local colorFx = Instance.new("ColorCorrectionEffect")
colorFx.Name = "DeepDiveColor"
colorFx.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Name = "DeepDiveBloom"
bloom.Intensity = 0.7
bloom.Size = 24
bloom.Threshold = 0.95
bloom.Parent = Lighting

local sunRays = Instance.new("SunRaysEffect")
sunRays.Intensity = 0.06
sunRays.Spread = 0.8
sunRays.Parent = Lighting

local snowPart = Instance.new("Part")
snowPart.Name = "MarineSnow"
snowPart.Anchored = true
snowPart.CanCollide = false
snowPart.CanQuery = false
snowPart.CanTouch = false
snowPart.Transparency = 1
snowPart.Size = Vector3.new(70, 40, 70)
snowPart.Parent = fxFolder
local snow = Instance.new("ParticleEmitter")
snow.Shape = Enum.ParticleEmitterShape.Box
snow.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
snow.Rate = 60
snow.Lifetime = NumberRange.new(4, 7)
snow.Speed = NumberRange.new(0.2, 0.8)
snow.SpreadAngle = Vector2.new(180, 180)
snow.Size = NumberSequence.new(0.12)
snow.LightEmission = 0.4
snow.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.2, 0.4),
	NumberSequenceKeypoint.new(0.8, 0.4),
	NumberSequenceKeypoint.new(1, 1),
})
snow.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
snow.Enabled = false
snow.Parent = snowPart

local SURFACE_LIGHT = {
	Ambient = Color3.fromRGB(70, 80, 95),
	OutdoorAmbient = Color3.fromRGB(130, 140, 150),
	Brightness = 2,
	FogColor = Color3.fromRGB(190, 215, 235),
}

RunService.RenderStepped:Connect(function()
	local camPos = camera.CFrame.Position
	local d = S - camPos.Y
	if d > 0.3 then
		local t = math.clamp(d / 620, 0, 1)
		local fogBonus = currentSub and (currentSub:GetAttribute("FogBonus") or 0) or 0
		Lighting.FogStart = 0
		Lighting.FogEnd = (330 - 275 * t ^ 0.65) + fogBonus * (0.4 + t)
		Lighting.FogColor = lerpColor(Color3.fromRGB(30, 110, 150), Color3.fromRGB(2, 6, 14), t * 1.3)
		Lighting.Ambient = lerpColor(Color3.fromRGB(60, 100, 130), Color3.fromRGB(6, 8, 14), t * 1.5)
		Lighting.OutdoorAmbient = lerpColor(Color3.fromRGB(70, 120, 150), Color3.fromRGB(4, 6, 10), t * 1.5)
		Lighting.Brightness = 1.4 * (1 - math.clamp(t * 1.8, 0, 1))
		colorFx.TintColor = lerpColor(Color3.fromRGB(190, 225, 255), Color3.fromRGB(150, 180, 255), t)
		colorFx.Saturation = -0.1
		colorFx.Contrast = 0.05
		snow.Enabled = true
		snowPart.CFrame = CFrame.new(camPos)
	else
		Lighting.FogEnd = 100000
		Lighting.FogColor = SURFACE_LIGHT.FogColor
		Lighting.Ambient = SURFACE_LIGHT.Ambient
		Lighting.OutdoorAmbient = SURFACE_LIGHT.OutdoorAmbient
		Lighting.Brightness = SURFACE_LIGHT.Brightness
		colorFx.TintColor = Color3.new(1, 1, 1)
		colorFx.Saturation = 0
		colorFx.Contrast = 0
		snow.Enabled = false
	end
end)

-- Smooth monster movement: the server sends where each monster should be,
-- and we glide it there every frame so it never looks choppy.
local monsterVisual = setmetatable({}, { __mode = "k" })
local function findSub(ownerId)
	local root = workspace:FindFirstChild("DeepDive")
	local folder = root and root:FindFirstChild("Subs")
	if folder then
		for _, s in ipairs(folder:GetChildren()) do
			if s:GetAttribute("OwnerId") == ownerId then
				return s
			end
		end
	end
	return nil
end
RunService.RenderStepped:Connect(function(dt)
	local root = workspace:FindFirstChild("DeepDive")
	local folder = root and root:FindFirstChild("Monsters")
	if not folder then
		return
	end
	local alpha = math.clamp(dt * 12, 0, 1)
	for _, m in ipairs(folder:GetChildren()) do
		local part = m.PrimaryPart
		if part then
			local target
			local latched = false
			local ownerId = m:GetAttribute("LatchOwner")
			if ownerId then
				-- stuck to a sub: place it on OUR copy of the sub so it never trails behind
				local sub = findSub(ownerId)
				local offset = m:GetAttribute("LatchOffset")
				if sub and sub.PrimaryPart and offset then
					local cf = sub.PrimaryPart.CFrame * offset
					target = CFrame.lookAt(cf.Position, sub.PrimaryPart.Position)
					latched = true
				end
			end
			target = target or m:GetAttribute("CF")
			if target then
				local current = monsterVisual[m]
				if not current or latched or (current.Position - target.Position).Magnitude > 40 then
					current = target
				else
					current = current:Lerp(target, alpha)
				end
				monsterVisual[m] = current
				part.CFrame = current
			end
		end
	end
end)

-- Camera shake when the hull gets hit (runs right after the camera updates)
RunService:BindToRenderStep("DeepDiveShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shake > 0.01 then
		local s = shake * 0.4
		camera.CFrame = camera.CFrame
			* CFrame.new(math.random() * s - s / 2, math.random() * s - s / 2, 0)
			* CFrame.Angles(0, 0, (math.random() - 0.5) * s * 0.05)
		shake = math.max(0, shake - dt * 2.5)
	end
end)

------------------------------------------------------------------------
-- HUD refresh (10x per second)
------------------------------------------------------------------------
local function setBar(bar, value, max, text)
	local f = max > 0 and math.clamp(value / max, 0, 1) or 0
	bar.Fill.Size = UDim2.fromScale(f, 1)
	bar.Text.Text = text
	return f
end

local hudAcc = 0
RunService.Heartbeat:Connect(function(dt)
	hudAcc += dt
	if hudAcc < 0.1 then
		return
	end
	hudAcc = 0

	-- 2x boost timer
	local boost = boostRemaining()
	if boost > 0 then
		boostLabel.Text = ("2x LOOT  %d:%02d"):format(math.floor(boost / 60), math.floor(boost % 60))
	else
		boostLabel.Text = meta.CanSave and "" or "Saving is OFF"
		boostLabel.TextColor3 = meta.CanSave and THEME.GOOD or THEME.BAD
	end

	-- Propeller bubbles on every nearby sub
	local root = workspace:FindFirstChild("DeepDive")
	if root then
		for _, sub in ipairs(root.Subs:GetChildren()) do
			local r = sub.PrimaryPart
			local att = r and r:FindFirstChild("PropAttachment")
			local pe = att and att:FindFirstChild("PropBubbles")
			if pe then
				local spd = r.AssemblyLinearVelocity.Magnitude
				pe.Rate = (spd > 2 and r.Position.Y < S - 1) and math.min(40, spd * 1.5) or 0
			end
		end
		-- Distress signal distance labels
		for _, sig in ipairs(root.Signals:GetChildren()) do
			local bb = sig:FindFirstChild("SignalGui")
			local l = bb and bb:FindFirstChild("Label")
			local p = sig.PrimaryPart
			if l and p then
				local dist = (p.Position - camera.CFrame.Position).Magnitude
				l.Text = ("DISTRESS SIGNAL\n%d m - %s"):format(math.floor(dist), sig:GetAttribute("Zone") or "")
				-- blink
				p.Transparency = (math.floor(os.clock() * 2) % 2 == 0) and 0 or 0.6
			end
		end
	end

	local sub = currentSub
	if not sub or not sub.PrimaryPart then
		hintLabel.Text = isTouch and "Walk to your sub and tap Board to dive!"
			or "Walk to your sub and press E to board. SHOP and CREW are top-right."
		return
	end

	local pos = sub.PrimaryPart.Position
	local depth = math.max(0, S - pos.Y)
	local zone = Config.GetZone(depth)
	local maxDepth = sub:GetAttribute("MaxDepth") or 210
	depthLabel.Text = Config.FormatNumber(depth) .. " m"
	zoneLabel.Text = depth < Config.SurfaceDepth and "SURFACE" or zone.Name
	zoneLabel.TextColor3 = zone.Color
	ratingLabel.Text = ("%s hull rated %d m"):format(sub:GetAttribute("HullName") or "", maxDepth)
	local danger = depth > maxDepth
	local nearLimit = depth > maxDepth - 20
	depthLabel.TextColor3 = danger and THEME.BAD or (nearLimit and THEME.GOLD or THEME.TEXT)
	ratingLabel.TextColor3 = danger and THEME.BAD or THEME.DIM
	depthMarker.Position = UDim2.fromScale(0, math.clamp(depth / BAR_MAX, 0, 1))
	ratingLine.Position = UDim2.fromScale(-0.3, math.clamp(maxDepth / BAR_MAX, 0, 1))

	local owner = sub:GetAttribute("OwnerName") or "?"
	subTitle.Text = owner .. "'s " .. (sub:GetAttribute("HullName") or "Sub")
	stationLabel.Text = "Station: " .. tostring(station)

	local hp, maxHp = sub:GetAttribute("HP") or 0, sub:GetAttribute("MaxHP") or 100
	local hpF = setBar(hpBar, hp, maxHp, ("HULL  %d / %d"):format(hp, maxHp))
	hpBar.Fill.BackgroundColor3 = hpF > 0.5 and THEME.GOOD or (hpF > 0.25 and THEME.GOLD or THEME.BAD)
	local o2, maxO2 = sub:GetAttribute("Oxygen") or 0, sub:GetAttribute("MaxOxygen") or 150
	local o2F = setBar(o2Bar, o2, maxO2, ("AIR  %d:%02d"):format(math.floor(o2 / 60), o2 % 60))
	o2Bar.Fill.BackgroundColor3 = o2F > 0.25 and THEME.ACCENT or THEME.BAD
	local count, maxCargo = sub:GetAttribute("CargoCount") or 0, sub:GetAttribute("CargoMax") or 8
	cargoLabel.Text = ("Cargo %d/%d  -  %s coins"):format(
		count,
		maxCargo,
		Config.FormatNumber(sub:GetAttribute("CargoValue") or 0)
	)
	cargoLabel.TextColor3 = count >= maxCargo and THEME.BAD or THEME.GOLD
	local leaks = sub:GetAttribute("Leaks") or 0
	leakLabel.Text = leaks > 0 and ("LEAKS: %d  - hold R / PATCH"):format(leaks) or ""
	if isTouch and leaks > 0 then
		leakLabel.Text = ("LEAKS: %d  - hold PATCH"):format(leaks)
	end

	-- Low health / crush warning vignette
	local warnLevel = 0
	if hpF < 0.35 then
		warnLevel = 0.5 + math.sin(os.clock() * 6) * 0.2
	end
	if danger then
		warnLevel = math.max(warnLevel, 0.6 + math.sin(os.clock() * 8) * 0.25)
	end
	vignette.BackgroundTransparency = 1 - warnLevel * 0.6

	-- Emergency surface (only if the Robux product is set up)
	local hasEmergency = false
	for _, p in ipairs(Config.Monetization.Products) do
		if p.Emergency and p.Id ~= 0 then
			hasEmergency = true
		end
	end
	emergencyButton.Visible = hasEmergency and sub:GetAttribute("Diving") == true and hpF < 0.35

	-- Buttons
	local surfaced = depth <= Config.SurfaceDepth + 1
	leaveButton.Visible = surfaced
	local harpoon = (sub:GetAttribute("HarpoonLevel") or 1) > 1
	fireButton.Visible = (station == "Turret" or station == "Helm") and (isTouch or not UserInputService.MouseEnabled)
	fireButton.BackgroundColor3 = harpoon and THEME.BAD or THEME.BG3
	upButton.Visible = station == "Helm" and isTouch
	downButton.Visible = station == "Helm" and isTouch
	patchButton.Visible = leaks > 0
	local sonarLeft = sonarCooldown - (os.clock() - lastSonar)
	sonarCdFill.Size = UDim2.fromScale(1, math.clamp(sonarLeft / sonarCooldown, 0, 1))
	for _, b in ipairs(stationButtons) do
		local st = b:GetAttribute("Station")
		local occupied = false
		for _, seat in ipairs(subStations(sub)) do
			if seat:GetAttribute("Station") == st and seat.Occupant then
				occupied = true
			end
		end
		if st == station then
			b.BackgroundColor3 = THEME.ACCENT
			b.TextColor3 = Color3.fromRGB(15, 25, 45)
		else
			b.BackgroundColor3 = occupied and THEME.BG2 or THEME.BG3
			b.TextColor3 = occupied and THEME.DIM or THEME.TEXT
		end
	end

	-- Controls hint
	if isTouch then
		hintLabel.Text = station == "Helm"
				and "Joystick: drive  -  UP/DOWN: rise/dive  -  FIRE: harpoon  -  SONAR: find loot"
			or (station .. ": tap the buttons on the right")
	elseif station == "Helm" then
		hintLabel.Text =
			"HELM:  W/S move  -  A/D turn  -  Q dive  -  E rise  -  Click harpoon  -  F sonar  -  1/2 supplies"
	elseif station == "Turret" then
		hintLabel.Text = "TURRET:  Aim with the mouse and click to fire harpoons!"
	elseif station == "Sonar" then
		hintLabel.Text = "SONAR:  Press F to ping - shows loot and monsters (faster from this seat)"
	elseif station == "Repair" then
		hintLabel.Text = "REPAIR:  Hold R to patch leaks fast  -  1 repair kit  -  2 oxygen"
	end

	-- Tutorial progress
	if tutorialStep == 2 and depth > 15 then
		setTutorialStep(3)
	end
	if tutorialStep == 3 and count > 0 then
		setTutorialStep(4)
	end
end)

------------------------------------------------------------------------
-- Ocean life (all on this client, purely visual):
--   * fish tails swish, jellyfish pulse, tentacles sway, eels slither
--   * sub propellers spin, beacons blink
--   * kelp and sea fans sway in the current
--   * schools of small harmless fish swim around you underwater
------------------------------------------------------------------------
local function startOceanLife()
	local SPHERE = Enum.MeshType.Sphere
	local jointCache = setmetatable({}, { __mode = "k" })
	local propAngles = setmetatable({}, { __mode = "k" })

	local function getAnim(model)
		local c = jointCache[model]
		if c then
			return c
		end
		c = { Joints = {}, Meshes = {} }
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Motor6D") and d:GetAttribute("Amp") then
				table.insert(c.Joints, {
					Joint = d,
					Amp = d:GetAttribute("Amp"),
					Freq = d:GetAttribute("Freq") or 5,
					Phase = d:GetAttribute("Phase") or 0,
					Axis = d:GetAttribute("Axis") or "Y",
				})
			elseif d:IsA("SpecialMesh") and d:GetAttribute("Pulse") then
				table.insert(c.Meshes, d)
			end
		end
		jointCache[model] = c
		return c
	end

	-- Kelp / sea fans
	local swayParts = {}
	task.spawn(function()
		local world = workspace:WaitForChild("DeepDiveWorld", 60)
		local reef = world and world:WaitForChild("Reef", 60)
		if not reef then
			return
		end
		task.wait(2)
		for _, p in ipairs(reef:GetDescendants()) do
			if p:IsA("BasePart") and p:GetAttribute("Sway") then
				table.insert(swayParts, {
					Part = p,
					Base = p.CFrame,
					Half = p.Size.Y / 2,
					Phase = math.random() * 10,
				})
			end
		end
	end)

	-- Fish schools
	local schools = {}
	local SHALLOW_COLORS = {
		Color3.fromRGB(255, 210, 60),
		Color3.fromRGB(80, 170, 255),
		Color3.fromRGB(225, 232, 240),
		Color3.fromRGB(255, 130, 80),
		Color3.fromRGB(120, 230, 200),
	}
	local DEEP_COLORS = { Color3.fromRGB(150, 165, 190), Color3.fromRGB(100, 115, 145) }

	local function fishPart(size, color, material)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		local m = Instance.new("SpecialMesh")
		m.MeshType = SPHERE
		m.Parent = p
		p.Parent = fxFolder
		return p
	end

	local function newSchool(center, deep)
		local school = {
			Center = center,
			Dir = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.2, math.random() - 0.5).Unit,
			Speed = 3 + math.random() * 4,
			Fish = {},
		}
		local color = deep and DEEP_COLORS[math.random(#DEEP_COLORS)] or SHALLOW_COLORS[math.random(#SHALLOW_COLORS)]
		local size = 0.6 + math.random() * 0.6
		for _ = 1, math.random(8, 14) do
			local body = fishPart(Vector3.new(0.35, 0.6, 1.3) * size, color, deep and Enum.Material.Glass or nil)
			local tail = fishPart(
				Vector3.new(0.08, 0.6, 0.5) * size,
				color,
				deep and Enum.Material.Neon or nil -- glowing lantern-fish tails in the deep
			)
			table.insert(school.Fish, {
				Body = body,
				Tail = tail,
				Offset = Vector3.new(math.random() * 10 - 5, math.random() * 4 - 2, math.random() * 10 - 5),
				Phase = math.random() * 10,
				Size = size,
			})
		end
		table.insert(schools, school)
	end

	local function clearSchools()
		for _, school in ipairs(schools) do
			for _, f in ipairs(school.Fish) do
				f.Body:Destroy()
				f.Tail:Destroy()
			end
		end
		table.clear(schools)
	end

	local swayAcc = 0
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		local camPos = camera.CFrame.Position
		local root = workspace:FindFirstChild("DeepDive")

		-- Monsters
		local mFolder = root and root:FindFirstChild("Monsters")
		if mFolder then
			for _, m in ipairs(mFolder:GetChildren()) do
				local p = m.PrimaryPart
				if p and (p.Position - camPos).Magnitude < 220 then
					local anim = getAnim(m)
					local boost = m:GetAttribute("LatchOwner") and 1.6 or 1
					for _, j in ipairs(anim.Joints) do
						local a = math.sin(t * j.Freq * boost + j.Phase) * j.Amp
						if j.Axis == "X" then
							j.Joint.Transform = CFrame.Angles(a, 0, 0)
						elseif j.Axis == "Z" then
							j.Joint.Transform = CFrame.Angles(0, 0, a)
						else
							j.Joint.Transform = CFrame.Angles(0, a, 0)
						end
					end
					local pulse = math.sin(t * 3)
					for _, mesh in ipairs(anim.Meshes) do
						mesh.Scale = Vector3.new(1 + pulse * 0.08, 1 - pulse * 0.12, 1 + pulse * 0.08)
					end
				end
			end
		end

		-- Subs: spin propellers, blink beacons
		local sFolder = root and root:FindFirstChild("Subs")
		if sFolder then
			local blink = (t % 1.6) < 0.15
			for _, sub in ipairs(sFolder:GetChildren()) do
				local r = sub.PrimaryPart
				if r then
					local motor = r:FindFirstChild("PropMotor")
					if motor then
						local spd = r.AssemblyLinearVelocity.Magnitude
						local angle = (propAngles[sub] or 0) + dt * (1.5 + spd * 0.9)
						propAngles[sub] = angle
						motor.Transform = CFrame.Angles(0, 0, angle)
					end
					local beacon = sub:FindFirstChild("Beacon")
					if beacon then
						beacon.Transparency = blink and 0 or 0.7
					end
				end
			end
		end

		-- Kelp sway (15 times a second is plenty)
		swayAcc += dt
		if swayAcc > 1 / 15 then
			swayAcc = 0
			for _, s in ipairs(swayParts) do
				if (s.Base.Position - camPos).Magnitude < 160 then
					local ax = math.sin(t * 0.8 + s.Phase) * 0.09
					local az = math.cos(t * 0.6 + s.Phase * 1.3) * 0.09
					s.Part.CFrame = s.Base
						* CFrame.new(0, -s.Half, 0)
						* CFrame.Angles(ax, 0, az)
						* CFrame.new(0, s.Half, 0)
				end
			end
		end

		-- Fish schools
		local depth = S - camPos.Y
		if depth < 6 then
			if #schools > 0 then
				clearSchools()
			end
			return
		end
		local deep = depth > 200
		while #schools < 5 do
			local dir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
			dir = dir.Magnitude > 0 and dir.Unit or Vector3.new(1, 0, 0)
			local c = camPos + dir * (25 + math.random() * 40) + Vector3.new(0, math.random() * 16 - 8, 0)
			c = Vector3.new(c.X, math.min(c.Y, S - 5), c.Z)
			newSchool(c, deep)
		end
		local parts, cframes = {}, {}
		for i = #schools, 1, -1 do
			local school = schools[i]
			-- wander, stay below the surface, scatter if the sub is close
			local turn = Vector3.new(
				math.noise(t * 0.2, i) * 0.6,
				math.noise(t * 0.15, i, 3) * 0.15,
				math.noise(i, t * 0.2) * 0.6
			)
			school.Dir = (school.Dir + turn * dt).Unit
			if school.Center.Y > S - 5 then
				school.Dir = Vector3.new(school.Dir.X, -math.abs(school.Dir.Y) - 0.2, school.Dir.Z).Unit
			end
			local speed = school.Speed
			if currentSub and currentSub.PrimaryPart then
				local away = school.Center - currentSub.PrimaryPart.Position
				if away.Magnitude < 14 and away.Magnitude > 0.1 then
					school.Dir = (school.Dir + away.Unit * dt * 4).Unit
					speed *= 2.5
				end
			end
			school.Center += school.Dir * speed * dt
			if (school.Center - camPos).Magnitude > 120 then
				for _, f in ipairs(school.Fish) do
					f.Body:Destroy()
					f.Tail:Destroy()
				end
				table.remove(schools, i)
			else
				local look = school.Dir
				for _, f in ipairs(school.Fish) do
					local wob = Vector3.new(
						math.sin(t + f.Phase) * 1.2,
						math.sin(t * 1.3 + f.Phase) * 0.5,
						math.cos(t * 0.9 + f.Phase) * 1.2
					)
					local pos = school.Center + f.Offset + wob
					local cf = CFrame.lookAt(pos, pos + look)
					table.insert(parts, f.Body)
					table.insert(cframes, cf)
					table.insert(parts, f.Tail)
					table.insert(
						cframes,
						cf * CFrame.new(0, 0, 0.75 * f.Size) * CFrame.Angles(0, math.sin(t * 14 + f.Phase) * 0.6, 0)
					)
				end
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end
startOceanLife()

------------------------------------------------------------------------
-- VIP chat tag
------------------------------------------------------------------------
pcall(function()
	TextChatService.OnIncomingMessage = function(message)
		local props = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if source then
			local p = Players:GetPlayerByUserId(source.UserId)
			if p and p:GetAttribute("VIP") then
				props.PrefixText = '<font color="#FFD23C">[VIP]</font> ' .. message.PrefixText
			end
		end
		return props
	end
end)

print("[DeepDive] Client ready")
