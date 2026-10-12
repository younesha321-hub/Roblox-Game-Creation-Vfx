--!strict
-- These tests exercise production Bind code against explicit service/signal mocks.
-- They do not open Roblox network connections or claim live Studio coverage.

type Loader = (environment: any) -> any

local function equal(actual: any, expected: any, context: string?)
	assert(actual == expected, (context or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function raises(callback: () -> ())
	local ok = pcall(callback)
	assert(not ok, "expected callback to fail")
end

local function newSignal(): any
	local connections: { any } = {}
	local signal: any = {}
	function signal:Connect(callback: (...any) -> ())
		local connection: any = { Connected = true, callback = callback }
		function connection:Disconnect()
			self.Connected = false
		end
		table.insert(connections, connection)
		return connection
	end
	function signal:Fire(...: any)
		-- A snapshot allows callbacks to disconnect other callbacks during Fire.
		for _, connection in ipairs(table.clone(connections)) do
			if connection.Connected then
				connection.callback(...)
			end
		end
	end
	function signal:ConnectionCount(): number
		local count = 0
		for _, connection in ipairs(connections) do
			if connection.Connected then count += 1 end
		end
		return count
	end
	return signal
end

local function fixture(loadGuard: Loader): any
	local players: any = { PlayerRemoving = newSignal() }
	local environment: any = { now = 10, server = true, traceLimiter = false }
	local runService: any = {}
	function runService:IsServer(): boolean
		return environment.server
	end
	environment.game = {
		GetService = function(_self: any, name: string): any
			if name == "Players" then return players end
			if name == "RunService" then return runService end
			error("unexpected mocked service")
		end,
	}
	local remote: any = { _mockInstance = true, OnServerEvent = newSignal() }
	function remote:IsA(className: string): boolean
		return className == "RemoteEvent"
	end
	local player: any = { UserId = 101, Parent = players }
	local options: any = {
		validate = function(value: any): boolean return value == "ok" end,
		capacity = 20,
		refillPerSecond = 2,
		handle = function(_player: any, _payload: any) end,
	}
	return {
		environment = environment, players = players, remote = remote,
		player = player, options = options, guard = loadGuard(environment),
	}
end

local statNames = { "accepted", "invalid", "rateLimited", "busy", "unauthorized", "errors", "inactive" }
local function statsEqual(binding: any, expected: { [string]: number })
	local stats = binding:GetStats()
	for _, name in ipairs(statNames) do
		equal(stats[name], expected[name] or 0, "stat " .. name)
	end
end

return function(loadGuard: Loader): (number, number)
	local total, failures = 0, 0
	local function test(name: string, callback: () -> ())
		total += 1
		local ok, problem = pcall(callback)
		if ok then
			print("PASS binding: " .. name)
		else
			failures += 1
			print("FAIL binding: " .. name .. " — " .. tostring(problem))
		end
	end

	test("valid payload reaches the handler with original identities", function()
		local f = fixture(loadGuard)
		local payload = { count = 2 }
		local calls = 0
		f.options.validate = f.guard.Validate.record({ count = f.guard.Validate.integer(1, 3) })
		f.options.handle = function(player: any, value: any)
			equal(player, f.player)
			equal(value, payload)
			calls += 1
		end
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, payload)
		equal(calls, 1)
		statsEqual(binding, { accepted = 1 })
	end)

	test("argument counting distinguishes no payload and explicit nil", function()
		local f = fixture(loadGuard)
		local calls = 0
		f.options.validate = f.guard.Validate.optional(f.guard.Validate.boolean())
		f.options.handle = function(_player: any, payload: any)
			equal(payload, nil)
			calls += 1
		end
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player)
		f.remote.OnServerEvent:Fire(f.player, true, nil)
		f.remote.OnServerEvent:Fire(f.player, nil)
		f.remote.OnServerEvent:Fire(f.player, true, false)
		equal(calls, 1)
		statsEqual(binding, { accepted = 1, invalid = 3 })
	end)

	test("invalid requests consume tokens before validation", function()
		local f = fixture(loadGuard)
		local validations, handled = 0, 0
		f.options.capacity = 1
		f.options.validate = function(_payload: any): boolean validations += 1; return false end
		f.options.handle = function(_player: any, _payload: any) handled += 1 end
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, "bad")
		f.remote.OnServerEvent:Fire(f.player, "ok")
		equal(validations, 1)
		equal(handled, 0)
		statsEqual(binding, { invalid = 1, rateLimited = 1 })
	end)

	test("different players including Studio test IDs have independent token buckets", function()
		local f = fixture(loadGuard)
		local other = { UserId = -1, Parent = f.players }
		f.options.capacity = 1
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.remote.OnServerEvent:Fire(other, "ok")
		statsEqual(binding, { accepted = 2, rateLimited = 1 })
	end)

	test("authorization requires literal true", function()
		local f = fixture(loadGuard)
		local response: any = false
		local calls = 0
		f.options.authorize = function(_player: any, _payload: any): any return response end
		f.options.handle = function(_player: any, _payload: any) calls += 1 end
		local binding = f.guard.Bind(f.remote, f.options)
		for _, rejected in ipairs({ false, 1, "yes" }) do
			response = rejected
			f.remote.OnServerEvent:Fire(f.player, "ok")
		end
		response = nil
		f.remote.OnServerEvent:Fire(f.player, "ok")
		response = true
		f.remote.OnServerEvent:Fire(f.player, "ok")
		equal(calls, 1)
		statsEqual(binding, { unauthorized = 4, accepted = 1 })
	end)

	test("validation requires literal true", function()
		local f = fixture(loadGuard)
		local response: any = false
		local authorizations = 0
		f.options.validate = function(_payload: any): any return response end
		f.options.authorize = function(_player: any, _payload: any): boolean authorizations += 1; return true end
		local binding = f.guard.Bind(f.remote, f.options)
		for _, rejected in ipairs({ false, 1, "true" }) do
			response = rejected
			f.remote.OnServerEvent:Fire(f.player, "ok")
		end
		response = nil
		f.remote.OnServerEvent:Fire(f.player, "ok")
		response = true
		f.remote.OnServerEvent:Fire(f.player, "ok")
		equal(authorizations, 1)
		statsEqual(binding, { invalid = 4, accepted = 1 })
	end)

	test("validator errors are isolated and release the busy flag", function()
		local f = fixture(loadGuard)
		local fail = true
		f.options.validate = function(_payload: any): boolean
			if fail then error("validator fixture failure") end
			return true
		end
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		fail = false
		f.remote.OnServerEvent:Fire(f.player, "ok")
		statsEqual(binding, { errors = 1, accepted = 1 })
	end)

	test("authorization errors are isolated and release the busy flag", function()
		local f = fixture(loadGuard)
		local fail = true
		f.options.authorize = function(_player: any, _payload: any): boolean
			if fail then error("authorization fixture failure") end
			return true
		end
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		fail = false
		f.remote.OnServerEvent:Fire(f.player, "ok")
		statsEqual(binding, { errors = 1, accepted = 1 })
	end)

	test("handler errors are isolated and do not count as accepted", function()
		local f = fixture(loadGuard)
		local fail = true
		f.options.handle = function(_player: any, _payload: any)
			if fail then error("handler fixture failure") end
		end
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		fail = false
		f.remote.OnServerEvent:Fire(f.player, "ok")
		statsEqual(binding, { errors = 1, accepted = 1 })
	end)

	test("nested requests from the same player are rejected as busy", function()
		local f = fixture(loadGuard)
		local validations, handled = 0, 0
		f.options.capacity = 2
		f.options.validate = function(_payload: any): boolean validations += 1; return true end
		f.options.handle = function(player: any, payload: any)
			handled += 1
			if handled == 1 then f.remote.OnServerEvent:Fire(player, payload) end
		end
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		-- The rejected nested call must still consume the second token.
		f.remote.OnServerEvent:Fire(f.player, "ok")
		equal(validations, 1)
		equal(handled, 1)
		statsEqual(binding, { busy = 1, accepted = 1, rateLimited = 1 })
	end)

	test("a busy player does not block a different player", function()
		local f = fixture(loadGuard)
		local other = { UserId = 102, Parent = f.players }
		local calls = 0
		f.options.handle = function(player: any, payload: any)
			calls += 1
			if player == f.player then f.remote.OnServerEvent:Fire(other, payload) end
		end
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		equal(calls, 2)
		statsEqual(binding, { accepted = 2 })
	end)

	test("inactive players are ignored before consuming tokens", function()
		local f = fixture(loadGuard)
		f.options.capacity = 1
		local binding = f.guard.Bind(f.remote, f.options)
		f.player.Parent = nil
		f.remote.OnServerEvent:Fire(f.player, "ok")
		statsEqual(binding, {})
		f.player.Parent = f.players
		f.remote.OnServerEvent:Fire(f.player, "ok")
		statsEqual(binding, { accepted = 1 })
	end)

	test("PlayerRemoving forgets the previous token bucket", function()
		local f = fixture(loadGuard)
		f.options.capacity = 1
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.player.Parent = nil
		f.players.PlayerRemoving:Fire(f.player)
		f.player.Parent = f.players
		f.remote.OnServerEvent:Fire(f.player, "ok")
		statsEqual(binding, { accepted = 2, rateLimited = 1 })
	end)

	test("Destroy is idempotent, disconnects signals, and clears limiter state", function()
		local f = fixture(loadGuard)
		f.environment.traceLimiter = true
		f.guard = loadGuard(f.environment)
		local calls = 0
		f.options.handle = function(_player: any, _payload: any) calls += 1 end
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		equal(f.remote.OnServerEvent:ConnectionCount(), 1)
		equal(f.players.PlayerRemoving:ConnectionCount(), 1)
		binding:Destroy()
		binding:Destroy()
		equal(f.environment.limiterCalls.clear, 1)
		equal(f.remote.OnServerEvent:ConnectionCount(), 0)
		equal(f.players.PlayerRemoving:ConnectionCount(), 0)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.players.PlayerRemoving:Fire(f.player)
		equal(f.environment.limiterCalls.forget, 0)
		equal(calls, 1)
		statsEqual(binding, { accepted = 1 })
	end)

	test("stats are independent frozen snapshots", function()
		local f = fixture(loadGuard)
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		local snapshot = binding:GetStats()
		assert(table.isfrozen(snapshot))
		assert(table.isfrozen(binding))
		raises(function() snapshot.accepted = 99 end)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		equal(snapshot.accepted, 1)
		assert(snapshot ~= binding:GetStats())
		statsEqual(binding, { accepted = 2 })
	end)

	test("Destroy during authorization prevents the handler", function()
		local f = fixture(loadGuard)
		local binding: any = nil
		local calls = 0
		f.options.authorize = function(_player: any, _payload: any): boolean
			binding:Destroy()
			return true
		end
		f.options.handle = function(_player: any, _payload: any) calls += 1 end
		binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		equal(calls, 0)
		statsEqual(binding, { inactive = 1 })
	end)

	test("player removal during authorization prevents the handler", function()
		local f = fixture(loadGuard)
		local calls = 0
		f.options.authorize = function(player: any, _payload: any): boolean
			player.Parent = nil
			f.players.PlayerRemoving:Fire(player)
			return true
		end
		f.options.handle = function(_player: any, _payload: any) calls += 1 end
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		equal(calls, 0)
		statsEqual(binding, { inactive = 1 })
	end)

	test("binding snapshots callback options and limiter configuration", function()
		local f = fixture(loadGuard)
		local validations, authorizations, handled = 0, 0, 0
		f.options.capacity = 1
		f.options.validate = function(_payload: any): boolean validations += 1; return true end
		f.options.authorize = function(_player: any, _payload: any): boolean authorizations += 1; return true end
		f.options.handle = function(_player: any, _payload: any) handled += 1 end
		local binding = f.guard.Bind(f.remote, f.options)
		f.options.validate = function(_payload: any): boolean return false end
		f.options.authorize = function(_player: any, _payload: any): boolean return false end
		f.options.handle = function(_player: any, _payload: any) error("mutated handler must not run") end
		f.options.capacity = 100
		f.options.refillPerSecond = 100
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.remote.OnServerEvent:Fire(f.player, "ok")
		equal(validations, 1)
		equal(authorizations, 1)
		equal(handled, 1)
		statsEqual(binding, { accepted = 1, rateLimited = 1 })
	end)

	test("server, RemoteEvent, and configuration checks reject invalid bindings", function()
		local f = fixture(loadGuard)
		f.environment.server = false
		raises(function() f.guard.Bind(f.remote, f.options) end)
		f.environment.server = true
		raises(function() f.guard.Bind({}, f.options) end)
		local wrongInstance = { _mockInstance = true, IsA = function(_self: any, _name: string): boolean return false end }
		raises(function() f.guard.Bind(wrongInstance, f.options) end)
		raises(function() f.guard.Bind(f.remote, nil) end)
		for _, field in ipairs({ "validate", "handle", "authorize" }) do
			local invalid = table.clone(f.options)
			invalid[field] = "invalid callback"
			raises(function() f.guard.Bind(f.remote, invalid) end)
		end
		local invalid = table.clone(f.options)
		invalid.capacity = 0
		raises(function() f.guard.Bind(f.remote, invalid) end)
		invalid = table.clone(f.options)
		invalid.refillPerSecond = 0
		raises(function() f.guard.Bind(f.remote, invalid) end)
		equal(f.remote.OnServerEvent:ConnectionCount(), 0)
		equal(f.players.PlayerRemoving:ConnectionCount(), 0)
	end)

	test("wrapper uses real limiter refill, cap, and backward-clock protection", function()
		local f = fixture(loadGuard)
		f.options.capacity = 2
		local binding = f.guard.Bind(f.remote, f.options)
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.environment.now = 9
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.environment.now = 10.5
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.environment.now = 20
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.remote.OnServerEvent:Fire(f.player, "ok")
		f.remote.OnServerEvent:Fire(f.player, "ok")
		statsEqual(binding, { accepted = 5, rateLimited = 4 })
	end)

	return total, failures
end
