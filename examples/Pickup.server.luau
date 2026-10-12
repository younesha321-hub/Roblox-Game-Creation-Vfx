--!strict
-- Standalone demo for an empty test place. All state changes happen on the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteGuard = require(game:GetService("ServerScriptService"):WaitForChild("RemoteGuard"))

local remote = Instance.new("RemoteEvent")
remote.Name = "RemoteGuardDemoRequest"
remote.Parent = ReplicatedStorage

local pickup = Instance.new("Part")
pickup.Name = "RemoteGuardDemoPickup"
pickup.Anchored = true
pickup.CanCollide = false
pickup.CanTouch = false
pickup.Size = Vector3.new(3, 3, 3)
pickup.Position = Vector3.new(0, 3, -12)
pickup.Color = Color3.fromRGB(80, 220, 140)
pickup.Parent = workspace
local available = true

local binding = RemoteGuard.Bind(remote, {
	validate = RemoteGuard.Validate.record({ action = RemoteGuard.Validate.oneOf({ "collect" }) }),
	capacity = 3,
	refillPerSecond = 1,
	authorize = function(player: Player, _payload: any): boolean
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return available and root ~= nil and root:IsA("BasePart")
			and humanoid ~= nil and humanoid.Health > 0
			and (root.Position - pickup.Position).Magnitude <= 12
	end,
	handle = function(player: Player, _payload: any)
		-- This transaction does not yield between checking availability and claiming it.
		available = false
		pickup.Color = Color3.fromRGB(100, 100, 100)
		local previous = player:GetAttribute("RemoteGuardDemoPoints")
		player:SetAttribute("RemoteGuardDemoPoints", (if type(previous) == "number" then previous else 0) + 1)
		task.delay(2, function()
			if pickup.Parent then
				available = true
				pickup.Color = Color3.fromRGB(80, 220, 140)
			end
		end)
	end,
})

script.Destroying:Connect(function()
	binding:Destroy()
	remote:Destroy()
	pickup:Destroy()
end)
