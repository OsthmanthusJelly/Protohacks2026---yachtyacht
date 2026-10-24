-- Generates the playable map at server start so the place needs no hand-built parts:
-- ocean, four islands, six tycoon plots, docks, boat spawns, secrets, and simple unlock models.
-- Skipped when workspace.Plots already exists, so a hand-built map always wins.
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)

local ISLANDS = {
	RobloxiaPort = { Center = Vector3.new(0, 0, 0), Radius = 260 },
	CoralRiviera = { Center = Vector3.new(700, 0, 0), Radius = 90 },
	LagoonAtoll = { Center = Vector3.new(0, 0, 800), Radius = 90 },
	ClassicIslands = { Center = Vector3.new(-700, 0, -500), Radius = 90 },
}
local GROUND_Y = 2 -- island surface; water surface is at 0
local PLOT_SIZE = 80

local WorldBuilder = {}

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	return p
end

local function label(parent: BasePart, text: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(160, 40)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.MaxDistance = 80
	local text_ = Instance.new("TextLabel")
	text_.Size = UDim2.fromScale(1, 1)
	text_.BackgroundTransparency = 1
	text_.TextColor3 = Color3.new(1, 1, 1)
	text_.TextStrokeTransparency = 0
	text_.TextScaled = true
	text_.Font = Enum.Font.GothamBold
	text_.Text = text
	text_.Parent = billboard
	billboard.Parent = parent
end

local function buildOcean()
	local terrain = workspace.Terrain
	terrain:FillBlock(CFrame.new(0, -10, 150), Vector3.new(1900, 20, 1800), Enum.Material.Water)
	for _, island in ISLANDS do
		terrain:FillCylinder(
			CFrame.new(island.Center + Vector3.new(0, GROUND_Y - 12, 0)),
			24,
			island.Radius,
			Enum.Material.Sand
		)
	end
end

-- Dock on the island's +Z edge, with a boat spawn buoy in the water beside it.
local function buildDock(locationId: string, folder: Folder)
	local island = ISLANDS[locationId]
	local edge = island.Center + Vector3.new(0, 0, island.Radius)
	local dock = part({
		Name = locationId .. "Dock",
		Size = Vector3.new(12, 1, 60),
		Position = edge + Vector3.new(0, GROUND_Y + 0.5, 10),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(140, 100, 60),
		Parent = folder,
	})
	dock:SetAttribute("Location", locationId)
	CollectionService:AddTag(dock, "FerryDock")
	label(dock, GameConfig.Locations[locationId].Name)

	local buoy = part({
		Name = locationId .. "BoatSpawn",
		Size = Vector3.new(3, 6, 3),
		Position = edge + Vector3.new(30, 1, 30),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 140, 0),
		CanCollide = false,
		Parent = folder,
	})
	buoy:SetAttribute("Location", locationId)
	CollectionService:AddTag(buoy, "BoatSpawn")
end

local function buildPlot(index: number, origin: Vector3, plots: Folder)
	local plot = Instance.new("Model")
	plot.Name = "Plot" .. index
	local base = part({
		Name = "Base",
		Size = Vector3.new(PLOT_SIZE, 1, PLOT_SIZE),
		Position = origin + Vector3.new(0, GROUND_Y + 0.5, 0),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(90, 160, 80),
		Parent = plot,
	})
	plot.PrimaryPart = base

	-- Buy buttons along the front edge, in purchase order.
	for i, unlock in GameConfig.DockUnlocks do
		local button = part({
			Name = unlock.Id .. "Button",
			Size = Vector3.new(6, 0.6, 6),
			CFrame = base.CFrame * CFrame.new(-30 + (i - 1) * 11, 0.8, -34),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(60, 220, 90),
			Parent = plot,
		})
		button:SetAttribute("UnlockId", unlock.Id)
		label(button, unlock.Name .. " $" .. unlock.Price)
	end

	-- 40x40 floor = 10x10 grid at CellSize 4.
	part({
		Name = "PartyFloor",
		Size = Vector3.new(40, 0.4, 40),
		CFrame = base.CFrame * CFrame.new(19, 0.7, 19),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(50, 40, 70),
		Parent = plot,
	})

	plot.Parent = plots
end

-- Simple building per unlock, authored around the origin (placed relative to the plot pivot).
local function buildUnlockTemplates()
	if ServerStorage:FindFirstChild("Unlocks") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Unlocks"
	local colors = {
		Color3.fromRGB(150, 110, 70),
		Color3.fromRGB(80, 160, 200),
		Color3.fromRGB(220, 60, 60),
		Color3.fromRGB(240, 240, 240),
		Color3.fromRGB(240, 200, 60),
		Color3.fromRGB(120, 80, 200),
	}
	for i, unlock in GameConfig.DockUnlocks do
		local height = 4 + i * 3
		local model = Instance.new("Model")
		model.Name = unlock.Id
		local block = part({
			Name = unlock.Id,
			Size = Vector3.new(10, height, 10),
			-- Two rows behind the buttons, left of the party floor.
			Position = Vector3.new(-32 + ((i - 1) % 3) * 12, 0.5 + height / 2, -16 + math.floor((i - 1) / 3) * 16),
			Color = colors[i] or colors[1],
			Parent = model,
		})
		model.PrimaryPart = block
		label(block, unlock.Name)
		model.Parent = folder
	end
	folder.Parent = ServerStorage
end

local function buildSecrets(folder: Folder)
	local spots = {
		SunkenChest = ISLANDS.CoralRiviera.Center + Vector3.new(-140, 0.5, 60), -- floating out at sea
		CaveIdol = ISLANDS.LagoonAtoll.Center + Vector3.new(-50, GROUND_Y + 1, -40),
		LighthouseKey = ISLANDS.ClassicIslands.Center + Vector3.new(40, GROUND_Y + 1, -50),
	}
	for id, position in spots do
		local secret = part({
			Name = id,
			Size = Vector3.new(2, 2, 2),
			Position = position,
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 215, 0),
			CanCollide = false,
			Parent = folder,
		})
		secret:SetAttribute("SecretId", id)
		CollectionService:AddTag(secret, "SecretCollectible")
	end
	part({
		Name = "Lighthouse",
		Size = Vector3.new(8, 50, 8),
		Position = spots.LighthouseKey + Vector3.new(10, 24, 0),
		Color = Color3.fromRGB(240, 240, 240),
		Parent = folder,
	})
end

function WorldBuilder.Build()
	if workspace:FindFirstChild("Plots") then
		return
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy() -- would sit on top of the ocean
	end

	buildOcean()
	buildUnlockTemplates()

	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace
	for locationId in ISLANDS do
		buildDock(locationId, world)
	end
	buildSecrets(world)

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, GROUND_Y + 0.5, 0)
	spawn.Parent = world

	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	local index = 0
	for _, x in { -100, 0, 100 } do
		for _, z in { -110, 110 } do
			index += 1
			buildPlot(index, Vector3.new(x, 0, z), plots)
		end
	end
	plots.Parent = workspace
end

return WorldBuilder
