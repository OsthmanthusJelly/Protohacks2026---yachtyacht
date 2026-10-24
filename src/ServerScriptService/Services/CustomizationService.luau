-- Validates and saves boat customization, then applies it to the spawned boat (replicates to everyone).
-- Boat models: parts named "Hull" (or attribute Paintable) get the color, parts named "LED" get the light,
-- a part named "Flag" gets the decal. Missing LED/Flag parts fall back to the hull.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local RemoteEvents = require(ReplicatedStorage.Modules.Network.RemoteEvents)
local DataManager = require(script.Parent.DataStoreService)
local VehiclePhysicsService = require(script.Parent.VehiclePhysicsService)

local PALETTE = GameConfig.Customization.Palette
local THEMES = GameConfig.Customization.InteriorThemes

local CustomizationService = {}

local function isPaletteIndex(value: unknown): boolean
	return type(value) == "number" and value % 1 == 0 and PALETTE[value] ~= nil
end

-- Returns a clean copy with only valid fields, or nil.
local function sanitize(custom: unknown)
	if type(custom) ~= "table" then
		return nil
	end
	local clean = {}
	if isPaletteIndex(custom.Color) then
		clean.Color = custom.Color
	end
	if type(custom.LedEnabled) == "boolean" then
		clean.LedEnabled = custom.LedEnabled
	end
	if isPaletteIndex(custom.LedColor) then
		clean.LedColor = custom.LedColor
	end
	if type(custom.Flag) == "number" and custom.Flag % 1 == 0 and custom.Flag > 0 and custom.Flag < 2 ^ 53 then
		clean.Flag = custom.Flag
	end
	if table.find(THEMES, custom.Interior) then
		clean.Interior = custom.Interior
	end
	return clean
end

local function partsNamed(model: Model, name: string)
	local parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and (part.Name == name or (name == "Hull" and part:GetAttribute("Paintable"))) then
			table.insert(parts, part)
		end
	end
	return parts
end

function CustomizationService.Apply(model: Model, custom)
	local hulls = partsNamed(model, "Hull")
	if custom.Color then
		for _, part in hulls do
			part.Color = PALETTE[custom.Color]
		end
	end

	local leds = partsNamed(model, "LED")
	for _, part in if #leds > 0 then leds else hulls do
		local light = part:FindFirstChild("CustomLED") or Instance.new("PointLight")
		light.Name = "CustomLED"
		light.Enabled = custom.LedEnabled == true
		light.Color = PALETTE[custom.LedColor or 1]
		light.Range = 16
		light.Parent = part
	end

	local flagPart = partsNamed(model, "Flag")[1] or hulls[1]
	if flagPart then
		local decal = flagPart:FindFirstChild("CustomFlag")
		if custom.Flag then
			decal = decal or Instance.new("Decal")
			decal.Name = "CustomFlag"
			decal.Face = Enum.NormalId.Top
			-- shortcut: expects an image asset id; decal ids from the library usually need converting to their image id.
			decal.Texture = "rbxassetid://" .. custom.Flag
			decal.Parent = flagPart
		elseif decal then
			decal:Destroy()
		end
	end

	-- shortcut: the theme is only stored as an attribute; swap interior models here once they exist.
	model:SetAttribute("InteriorTheme", custom.Interior)
end

local function onApply(player: Player, boatId: unknown, custom: unknown)
	local data = DataManager.Get(player)
	local clean = sanitize(custom)
	if not data or type(boatId) ~= "string" or not data.Boats[boatId] or not clean then
		return
	end
	data.Customizations[boatId] = clean

	local model = VehiclePhysicsService.GetBoat(player)
	if model and model:GetAttribute("BoatId") == boatId then
		CustomizationService.Apply(model, clean)
	end
end

function CustomizationService.Start()
	RemoteEvents.ApplyCustomization.OnServerEvent:Connect(onApply)
	VehiclePhysicsService.BoatSpawned:Connect(function(player, model, boatId)
		local data = DataManager.Get(player)
		local custom = data and data.Customizations[boatId]
		if custom then
			CustomizationService.Apply(model, custom)
		end
	end)
end

-- Number of customized fields, used for the rental bonus.
function CustomizationService.CountFields(custom): number
	local count = 0
	for _ in custom or {} do
		count += 1
	end
	return count
end

return CustomizationService
