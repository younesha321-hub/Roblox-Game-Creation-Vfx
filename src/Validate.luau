--!strict

-- Validators return stable errors and never stringify untrusted values.
local Validate = {}

export type Validator = (value: any) -> (boolean, string?)

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function assertBound(value: number, label: string)
	assert(type(value) == "number" and isFinite(value), label .. " must be a finite number")
end

local function assertCount(value: number, label: string)
	assertBound(value, label)
	assert(value >= 0 and value % 1 == 0, label .. " must be a non-negative integer")
end

local function assertPlainTable(value: any, label: string)
	assert(type(value) == "table" and getmetatable(value) == nil, label .. " must be a table without a metatable")
end

function Validate.number(minimum: number, maximum: number): Validator
	assertBound(minimum, "minimum")
	assertBound(maximum, "maximum")
	assert(minimum <= maximum, "minimum must be less than or equal to maximum")

	return function(value: any): (boolean, string?)
		if type(value) ~= "number" or not isFinite(value) then
			return false, "expected finite number"
		end
		if value < minimum or value > maximum then
			return false, "number out of range"
		end
		return true, nil
	end
end

function Validate.integer(minimum: number, maximum: number): Validator
	local validateNumber = Validate.number(minimum, maximum)
	assert(minimum % 1 == 0 and maximum % 1 == 0, "integer bounds must be integers")

	return function(value: any): (boolean, string?)
		local ok, reason = validateNumber(value)
		if not ok then
			return false, reason
		end
		if value % 1 ~= 0 then
			return false, "expected integer"
		end
		return true, nil
	end
end

function Validate.string(maxBytes: number, minBytes: number?): Validator
	local minimum = if minBytes == nil then 0 else minBytes
	assertCount(maxBytes, "maxBytes")
	assertCount(minimum, "minBytes")
	assert(minimum <= maxBytes, "minBytes must be less than or equal to maxBytes")

	return function(value: any): (boolean, string?)
		if type(value) ~= "string" then
			return false, "expected string"
		end
		-- Check bytes before walking UTF-8 so oversized strings are rejected cheaply.
		if #value < minimum or #value > maxBytes then
			return false, "string byte length out of range"
		end
		if utf8.len(value) == nil then
			return false, "invalid UTF-8 string"
		end
		return true, nil
	end
end

function Validate.boolean(): Validator
	return function(value: any): (boolean, string?)
		if type(value) ~= "boolean" then
			return false, "expected boolean"
		end
		return true, nil
	end
end

function Validate.oneOf(values: { string }): Validator
	assertPlainTable(values, "values")
	local allowed: { [string]: boolean } = {}
	local count = 0
	for key, value in pairs(values) do
		assert(type(key) == "number" and isFinite(key) and key >= 1 and key % 1 == 0, "values must be a dense array")
		assert(type(value) == "string", "enum values must be strings")
		allowed[value] = true
		count += 1
	end
	assert(count > 0, "values must contain at least one string")
	for index = 1, count do
		assert(rawget(values, index) ~= nil, "values must be a dense array")
	end
	-- Copying prevents a caller from changing a schema after it was registered.
	table.freeze(allowed)

	return function(value: any): (boolean, string?)
		if type(value) ~= "string" or allowed[value] ~= true then
			return false, "expected allowed string"
		end
		return true, nil
	end
end

function Validate.optional(validator: Validator): Validator
	assert(type(validator) == "function", "validator must be a function")
	return function(value: any): (boolean, string?)
		if value == nil then
			return true, nil
		end
		return validator(value)
	end
end

function Validate.array(validator: Validator, maxItems: number): Validator
	assert(type(validator) == "function", "validator must be a function")
	assertCount(maxItems, "maxItems")

	return function(value: any): (boolean, string?)
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			return false, "expected plain array"
		end

		local count = 0
		for key in pairs(value) do
			count += 1
			-- Never enumerate more than maxItems + 1 entries.
			if count > maxItems then
				return false, "too many array items"
			end
			if type(key) ~= "number" or not isFinite(key) or key % 1 ~= 0 or key < 1 or key > maxItems then
				return false, "expected dense array"
			end
		end

		for index = 1, count do
			local item = rawget(value, index)
			if item == nil then
				return false, "expected dense array"
			end
			local ok = validator(item)
			if ok ~= true then
				return false, "invalid array item"
			end
		end
		return true, nil
	end
end

function Validate.record(fields: { [string]: Validator }): Validator
	assertPlainTable(fields, "fields")
	local schema: { [string]: Validator } = {}
	local fieldCount = 0
	for key, validator in pairs(fields) do
		assert(type(key) == "string", "field names must be strings")
		assert(type(validator) == "function", "field validators must be functions")
		schema[key] = validator
		fieldCount += 1
	end
	table.freeze(schema)

	return function(value: any): (boolean, string?)
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			return false, "expected plain record"
		end
		local count = 0
		for key in pairs(value) do
			count += 1
			if count > fieldCount then
				return false, "too many record fields"
			end
			if type(key) ~= "string" or schema[key] == nil then
				return false, "unknown record field"
			end
		end
		for key, validator in pairs(schema) do
			local ok = validator(rawget(value, key))
			if ok ~= true then
				return false, "invalid record field"
			end
		end
		return true, nil
	end
end

return table.freeze(Validate)
