--[[
	SubBuilder  (ModuleScript)
	LOCATION: ServerScriptService > SubBuilder

	Builds a submarine model out of parts. The look depends on the hull tier
	(bigger hulls = longer sub with more crew seats) and the player's paint.

	Every sub has:
	  Root       invisible centre part (PrimaryPart) that physics moves
	  Drive      LinearVelocity  -> how fast the sub moves
	  Steer      AlignOrientation -> which way the sub faces
	  Seats      one per crew station (Helm is a VehicleSeat)
	  Barrel     harpoon turret barrel on a Motor6D so it can aim
	  Headlight  SpotLight on the nose
	  BoardPrompt  "Board Sub" ProximityPrompt
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("DeepDiveConfig"))

local SubBuilder = {}

local SEAT_LAYOUTS = {
	-- {station, x, z-as-fraction-of-length}
	[2] = { { "Helm", 0, -0.2 }, { "Turret", 0, 0.2 } },
	[4] = { { "Helm", 0, -0.3 }, { "Turret", 0, -0.02 }, { "Sonar", -1.6, 0.25 }, { "Repair", 1.6, 0.25 } },
}

local function newPart(model, root, props, collide)
	local p = Instance.new("Part")
	p.Anchored = false
	p.Massless = true
	p.CanCollide = collide == true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	return p
end

-- Builds the sub at the world origin; call model:PivotTo() afterwards.
function SubBuilder.Build(hullLevel, paintColor, lightColor, ownerName, isVIP)
	local hull = Config.Upgrades.Hull.Levels[hullLevel] or Config.Upgrades.Hull.Levels[1]
	local L = hull.Length
	local D = hull.Diameter
	local R = D / 2
	local mat = hull.Material or Enum.Material.SmoothPlastic
	local accent = Color3.fromRGB(235, 235, 240)
	local dark = Color3.fromRGB(45, 48, 58)

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

	-- Physics movers (the pilot's client drives these)
	local drive = Instance.new("LinearVelocity")
	drive.Name = "Drive"
	drive.Attachment0 = rootAtt
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	drive.MaxForce = 80000
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

	-- Body (cylinder lying along the sub's length)
	local alongZ = CFrame.Angles(0, math.rad(90), 0)
	local body = newPart(model, root, {
		Name = "Body",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(L, D, D),
		CFrame = alongZ,
		Material = mat,
		Color = paintColor,
	}, true)
	body:SetAttribute("Paint", true)

	-- Glass cockpit nose
	newPart(model, root, {
		Name = "Nose",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(D, D, D),
		CFrame = CFrame.new(0, 0, -L / 2),
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(150, 220, 255),
		Transparency = 0.35,
	}, true)

	-- Tail
	local tail = newPart(model, root, {
		Name = "Tail",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(D * 0.96, D * 0.96, D * 0.96),
		CFrame = CFrame.new(0, 0, L / 2),
		Material = mat,
		Color = paintColor,
	}, true)
	tail:SetAttribute("Paint", true)

	-- Accent stripes
	for _, f in ipairs({ -0.32, 0.32 }) do
		newPart(model, root, {
			Name = "Stripe",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.7, D + 0.12, D + 0.12),
			CFrame = CFrame.new(0, 0, L * f) * alongZ,
			Material = Enum.Material.SmoothPlastic,
			Color = accent,
		})
	end

	-- Conning tower (sail)
	local sailH = 2.4 + R * 0.35
	local sail = newPart(model, root, {
		Name = "Sail",
		Size = Vector3.new(D * 0.36, sailH, L * 0.3),
		CFrame = CFrame.new(0, R + sailH / 2 - 0.6, L * 0.06),
		Material = mat,
		Color = paintColor,
	}, true)
	sail:SetAttribute("Paint", true)
	newPart(model, root, {
		Name = "Hatch",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, D * 0.3, D * 0.3),
		CFrame = CFrame.new(0, R + sailH - 0.4, L * 0.06) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Metal,
		Color = dark,
	})
	newPart(model, root, {
		Name = "Periscope",
		Size = Vector3.new(0.35, 2.4, 0.35),
		CFrame = CFrame.new(0, R + sailH + 0.6, L * 0.06 + 1),
		Material = Enum.Material.Metal,
		Color = dark,
	})

	-- Fins
	newPart(model, root, {
		Name = "TailFinV",
		Size = Vector3.new(0.4, D * 0.55, D * 0.45),
		CFrame = CFrame.new(0, R * 0.75, L / 2 + R * 0.35),
		Material = mat,
		Color = accent,
	})
	newPart(model, root, {
		Name = "TailFinH",
		Size = Vector3.new(D * 1.15, 0.4, D * 0.4),
		CFrame = CFrame.new(0, 0, L / 2 + R * 0.4),
		Material = mat,
		Color = accent,
	})
	newPart(model, root, {
		Name = "SideFins",
		Size = Vector3.new(D * 1.5, 0.35, D * 0.35),
		CFrame = CFrame.new(0, -R * 0.2, -L * 0.22),
		Material = mat,
		Color = accent,
	})

	-- Propeller
	local propZ = L / 2 + R + 0.2
	newPart(model, root, {
		Name = "PropHub",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 1.4, 1.4),
		CFrame = CFrame.new(0, 0, propZ) * alongZ,
		Material = Enum.Material.Metal,
		Color = dark,
	})
	for i = 0, 2 do
		newPart(model, root, {
			Name = "PropBlade",
			Size = Vector3.new(0.9, R * 0.9, 0.25),
			CFrame = CFrame.new(0, 0, propZ + 0.2)
				* CFrame.Angles(0, 0, math.rad(i * 120))
				* CFrame.new(0, R * 0.45, 0),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(200, 170, 80),
		})
	end
	local propAtt = Instance.new("Attachment")
	propAtt.Name = "PropAttachment"
	propAtt.Position = Vector3.new(0, 0, propZ + 1.2)
	propAtt.Parent = root
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "PropBubbles"
	bubbles.Texture = "rbxasset://textures/particles/smoke_main.dds"
	bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
	bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.4) })
	bubbles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	bubbles.Lifetime = NumberRange.new(1, 1.8)
	bubbles.Speed = NumberRange.new(2, 4)
	bubbles.SpreadAngle = Vector2.new(25, 25)
	bubbles.EmissionDirection = Enum.NormalId.Back
	bubbles.Rate = 0
	bubbles.LightEmission = 0.2
	bubbles.Parent = propAtt

	-- Portholes (warm glow from inside)
	for _, f in ipairs({ -0.15, 0.12 }) do
		for _, side in ipairs({ -1, 1 }) do
			newPart(model, root, {
				Name = "Porthole",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.3, 1.5, 1.5),
				CFrame = CFrame.new(side * (R - 0.05), 0.4, L * f),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 220, 140),
			})
		end
	end

	-- Headlight
	local lamp = newPart(model, root, {
		Name = "Headlight",
		Size = Vector3.new(1.6, 1.0, 0.5),
		CFrame = CFrame.new(0, -R * 0.62, -L / 2 - R * 0.72),
		Material = Enum.Material.Neon,
		Color = lightColor,
	})
	local spot = Instance.new("SpotLight")
	spot.Name = "Beam"
	spot.Face = Enum.NormalId.Front
	spot.Range = 32
	spot.Angle = 50
	spot.Brightness = 3
	spot.Color = lightColor
	spot.Shadows = true
	spot.Parent = lamp
	local glow = Instance.new("PointLight")
	glow.Name = "HullGlow"
	glow.Range = 13
	glow.Brightness = 0.7
	glow.Color = Color3.fromRGB(255, 225, 180)
	glow.Parent = body

	-- Harpoon turret
	local turretZ = -L * 0.3
	newPart(model, root, {
		Name = "TurretBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 2.2, 2.2),
		CFrame = CFrame.new(0, R + 0.1, turretZ) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Metal,
		Color = dark,
	})
	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(0.55, 0.55, 3.4)
	barrel.Material = Enum.Material.Metal
	barrel.Color = Color3.fromRGB(70, 75, 85)
	barrel.Massless = true
	barrel.CanCollide = false
	barrel.CanTouch = false
	barrel.CastShadow = false
	barrel.CFrame = CFrame.new(0, R + 0.9, turretZ - 1.5)
	barrel.Parent = model
	local motor = Instance.new("Motor6D")
	motor.Name = "TurretMotor"
	motor.Part0 = root
	motor.Part1 = barrel
	motor.C0 = CFrame.new(0, R + 0.9, turretZ)
	motor.C1 = CFrame.new(0, 0, 1.5)
	motor.Parent = root
	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Position = Vector3.new(0, 0, -1.8)
	tip.Parent = barrel
	model:SetAttribute("TurretPivot", Vector3.new(0, R + 0.9, turretZ))

	-- Seats (inside the hull)
	local layout = SEAT_LAYOUTS[#hull.Seats] or SEAT_LAYOUTS[2]
	local seatY = -R + 1.0
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
		seat.CanTouch = false -- boarding happens through the prompt only
		seat.Massless = true
		seat.Anchored = false
		seat.CFrame = CFrame.new(info[2], seatY, L * info[3])
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
	tagAtt.Position = Vector3.new(0, R + sailH + 3, 0)
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
	prompt.MaxActivationDistance = math.max(16, L * 0.8)
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = promptAtt

	model:SetAttribute("IsSub", true)
	model:SetAttribute("HullLength", L)
	model:SetAttribute("HullRadius", R)
	return model
end

-- Applies paint + light colour to an existing sub (no rebuild needed).
function SubBuilder.ApplyLook(model, paintColor, lightColor, shiny)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("Paint") then
			p.Color = paintColor
			p.Reflectance = shiny and 0.25 or 0
		end
	end
	local lamp = model:FindFirstChild("Headlight")
	if lamp then
		lamp.Color = lightColor
		local beam = lamp:FindFirstChild("Beam")
		if beam then
			beam.Color = lightColor
		end
	end
end

return SubBuilder
