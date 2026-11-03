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
local Config = require(ReplicatedStorage:WaitForChild("DeepDiveConfig"))

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
		seat.CanTouch = false -- boarding happens through the prompt only
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
