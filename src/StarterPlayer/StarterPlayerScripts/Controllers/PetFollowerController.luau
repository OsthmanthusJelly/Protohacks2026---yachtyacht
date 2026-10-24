-- Renders every player's equipped pets (player attribute "EquippedPets") trailing behind them.
-- Pets are client-only anchored models, lerped each frame. Models come from ReplicatedStorage.Pets[id].
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLLOW_SPEED = 8
local SPACING = 3.5

local PetFollowerController = {}

-- [Player] = { Model }
local pets = {}

local function makePet(id: string): Model
	local templates = ReplicatedStorage:FindFirstChild("Pets")
	local template = templates and templates:FindFirstChild(id)
	local model = if template then template:Clone() else Instance.new("Model")
	if not template then
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * 1.5
		ball.Color = Color3.fromRGB(255, 200, 80)
		ball.Parent = model
		model.PrimaryPart = ball
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	model.Name = id
	return model
end

local function refresh(player: Player)
	for _, model in pets[player] or {} do
		model:Destroy()
	end
	pets[player] = {}
	local ids = player:GetAttribute("EquippedPets")
	if type(ids) ~= "string" then
		return
	end
	for id in ids:gmatch("[^,]+") do
		local model = makePet(id)
		model.Parent = workspace
		table.insert(pets[player], model)
	end
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("EquippedPets"):Connect(function()
		refresh(player)
	end)
	refresh(player)
end

function PetFollowerController.Start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		for _, model in pets[player] or {} do
			model:Destroy()
		end
		pets[player] = nil
	end)

	RunService.RenderStepped:Connect(function(dt)
		local alpha = math.min(1, dt * FOLLOW_SPEED)
		local bob = math.sin(os.clock() * 3) * 0.3
		for player, models in pets do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				for i, model in models do
					-- One row behind the player, centred.
					local side = (i - (#models + 1) / 2) * SPACING
					local target = root.CFrame * CFrame.new(side, bob, SPACING)
					model:PivotTo(model:GetPivot():Lerp(target, alpha))
				end
			end
		end
	end)
end

return PetFollowerController
