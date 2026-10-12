--!strict

-- A token bucket per user. The injected clock makes the module testable in Luau.
local RateLimiter = {}

export type Limiter = {
	read Allow: (self: Limiter, userId: number) -> (boolean, number),
	read Forget: (self: Limiter, userId: number) -> (),
	read Clear: (self: Limiter) -> (),
}

type Bucket = {
	tokens: number,
	updatedAt: number,
}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function assertUserId(userId: number)
	assert(type(userId) == "number" and isFinite(userId) and userId % 1 == 0, "userId must be a finite integer")
end

function RateLimiter.new(capacity: number, refillPerSecond: number, clock: (() -> number)?): Limiter
	assert(type(capacity) == "number" and isFinite(capacity) and capacity >= 1 and capacity % 1 == 0, "capacity must be a positive finite integer")
	assert(type(refillPerSecond) == "number" and isFinite(refillPerSecond) and refillPerSecond > 0, "refillPerSecond must be a positive finite number")
	assert(clock == nil or type(clock) == "function", "clock must be a function")
	local readClock: () -> number = if clock == nil then os.clock else clock
	local buckets: { [number]: Bucket } = {}

	local function allow(_self: Limiter, userId: number): (boolean, number)
		assertUserId(userId)
		local now = readClock()
		assert(type(now) == "number" and isFinite(now), "clock must return a finite number")

		local bucket = buckets[userId]
		if bucket == nil then
			bucket = { tokens = capacity, updatedAt = now }
			buckets[userId] = bucket
		elseif now > bucket.updatedAt then
			bucket.tokens = math.min(capacity, bucket.tokens + (now - bucket.updatedAt) * refillPerSecond)
			bucket.updatedAt = now
		end
		-- A backward clock never moves the watermark or adds tokens.
		if bucket.tokens >= 1 then
			bucket.tokens -= 1
			return true, 0
		end
		local clockRecovery = math.max(0, bucket.updatedAt - now)
		return false, clockRecovery + (1 - bucket.tokens) / refillPerSecond
	end

	local function forget(_self: Limiter, userId: number)
		assertUserId(userId)
		buckets[userId] = nil
	end

	local function clear(_self: Limiter)
		table.clear(buckets)
	end

	return table.freeze({ Allow = allow, Forget = forget, Clear = clear })
end

return table.freeze(RateLimiter)
