local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local RemoteEvents = require(ReplicatedStorage.Modules.Network.RemoteEvents)

RemoteEvents.Notify.OnClientEvent:Connect(function(text)
	pcall(StarterGui.SetCore, StarterGui, "SendNotification", { Title = "Yacht Tycoon", Text = text, Duration = 4 })
end)

for _, controller in script.Parent:WaitForChild("Controllers"):GetChildren() do
	task.spawn(require(controller).Start)
end
