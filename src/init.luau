--!strict
-- Server-only RemoteEvent adapter. The validators and limiter are also usable alone.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Validate = require(script.Validate)
local RateLimiter = require(script.RateLimiter)

export type Validator = (value: any) -> (boolean, string?)
export type Options = {
	validate: Validator,
	capacity: number,
	refillPerSecond: number,
	authorize: ((player: Player, payload: any) -> boolean)?,
	handle: (player: Player, payload: any) -> (),
}
export type Stats = {
	accepted: number,
	invalid: number,
	rateLimited: number,
	busy: number,
	unauthorized: number,
	errors: number,
	inactive: number,
}
export type Binding = {
	Destroy: (self: Binding) -> (),
	GetStats: (self: Binding) -> Stats,
}

local RemoteGuard = { Validate = Validate, RateLimiter = RateLimiter }

function RemoteGuard.Bind(remote: RemoteEvent, options: Options): Binding
	assert(RunService:IsServer(), "RemoteGuard.Bind must run on the server")
	assert(typeof(remote) == "Instance" and remote:IsA("RemoteEvent"), "expected RemoteEvent")
	assert(type(options) == "table", "expected options")
	assert(type(options.validate) == "function", "expected validator")
	assert(type(options.handle) == "function", "expected handler")
	assert(options.authorize == nil or type(options.authorize) == "function", "expected authorization callback")
	-- Snapshot callbacks so changing the caller's table cannot change this binding.
	local validate, authorize, handle = options.validate, options.authorize, options.handle
	local limiter = RateLimiter.new(options.capacity, options.refillPerSecond)
	local busy: { [Player]: boolean } = {}
	local destroyed = false
	local stats: Stats = {
		accepted = 0, invalid = 0, rateLimited = 0, busy = 0,
		unauthorized = 0, errors = 0, inactive = 0,
	}
	local eventConnection = remote.OnServerEvent:Connect(function(player: Player, ...: any)
		if destroyed or player.Parent ~= Players then
			return
		end
		-- Invalid traffic also consumes tokens, before any payload traversal.
		if not limiter:Allow(player.UserId) then
			stats.rateLimited += 1
			return
		end
		if select("#", ...) ~= 1 then
			stats.invalid += 1
			return
		end
		if busy[player] then
			stats.busy += 1
			return
		end
		busy[player] = true
		local payload = ...
		local ok, outcome = pcall(function(): string
			if validate(payload) ~= true then
				return "invalid"
			end
			if authorize and authorize(player, payload) ~= true then
				return "unauthorized"
			end
			if destroyed or player.Parent ~= Players then
				return "inactive"
			end
			handle(player, payload)
			return "accepted"
		end)
		busy[player] = nil
		if not ok then
			stats.errors += 1
			-- Inspect GetStats while developing. Do not log every rejected request.
			return
		end
		if outcome == "accepted" then stats.accepted += 1
		elseif outcome == "invalid" then stats.invalid += 1
		elseif outcome == "unauthorized" then stats.unauthorized += 1
		elseif outcome == "inactive" then stats.inactive += 1 end
	end)
	local removalConnection = Players.PlayerRemoving:Connect(function(player: Player)
		limiter:Forget(player.UserId)
		busy[player] = nil
	end)
	local binding: Binding = {
		Destroy = function(_self: Binding)
			if destroyed then return end
			destroyed = true
			eventConnection:Disconnect()
			removalConnection:Disconnect()
			limiter:Clear()
			table.clear(busy)
		end,
		GetStats = function(_self: Binding): Stats
			return table.freeze(table.clone(stats))
		end,
	}
	return table.freeze(binding)
end

return table.freeze(RemoteGuard)
