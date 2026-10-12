--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("RemoteGuardDemoRequest") :: RemoteEvent

local gui = Instance.new("ScreenGui")
gui.Name = "RemoteGuardDemo"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local button = Instance.new("TextButton")
button.AnchorPoint = Vector2.new(0.5, 1)
button.Position = UDim2.fromScale(0.5, 0.95)
button.Size = UDim2.fromOffset(290, 54)
button.TextSize = 18
button.Parent = gui

local function refresh()
	local points = player:GetAttribute("RemoteGuardDemoPoints") or 0
	button.Text = "Collect nearby (E) | Points: " .. tostring(points)
end
local function collect()
	remote:FireServer({ action = "collect" })
end
button.Activated:Connect(collect)
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == Enum.KeyCode.E then collect() end
end)
player:GetAttributeChangedSignal("RemoteGuardDemoPoints"):Connect(refresh)
refresh()
