-- Run from the repository root: luau tests/run.luau
local Validate = require("../src/Validate")
local RateLimiter = require("../src/RateLimiter")
local run = require("./Core.spec")

local report = run(Validate, RateLimiter)
for _, case in ipairs(report.cases) do
	print((case.passed and "PASS " or "FAIL ") .. case.name)
	if not case.passed then
		print("  " .. tostring(case.error))
	end
end
print(string.format("%d passed; %d failed", report.passed, report.failed))
assert(report.failed == 0, "RemoteGuard behavioral tests failed")
return report
