#!/usr/bin/env node
// Run the actual Bind implementation in Luau CLI with explicit Roblox mocks.
// Only source-loading and Roblox service boundaries are adapted; core algorithms
// are loaded from the current production files on every invocation.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const argument = process.argv[2] ?? "luau";
const executable = /[\\/]/.test(argument) ? resolve(argument) : argument;

function luauString(text) {
  // JSON handles quotes, backslashes, and control characters. Translate only
  // actual JSON Unicode escapes to Luau syntax, preserving escaped backslashes.
  return JSON.stringify(text).replace(/\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4})/g, (escape) =>
    escape.startsWith("\\u") ? `\\u{${escape.slice(2)}}` : escape,
  );
}

const source = (name) => luauString(readFileSync(join(root, name), "utf8"));
const runner = `-- Generated from CURRENT production files; do not commit this file.
local baseEnvironment = getfenv()
local validateSource = ${source("src/Validate.luau")}
local rateLimiterSource = ${source("src/RateLimiter.luau")}
local guardSource = ${source("src/init.luau")}
local suiteSource = ${source("tests/Binding.spec.luau")}

local function compile(text, name)
    local factory, problem = loadstring(text, "@" .. name)
    assert(factory, problem)
    return factory
end

local actualValidate = compile(validateSource, "src/Validate.luau")()
local rateLimiterCache = {}
local function loadGuard(mockEnvironment)
    local actualRateLimiter = rateLimiterCache[mockEnvironment]
    if actualRateLimiter == nil then
        local rateFactory = compile(rateLimiterSource, "src/RateLimiter.luau")
        setfenv(rateFactory, setmetatable({
            os = { clock = function() return mockEnvironment.now end },
        }, { __index = baseEnvironment }))
        actualRateLimiter = rateFactory()
        rateLimiterCache[mockEnvironment] = actualRateLimiter
    end

    local limiterDependency = actualRateLimiter
    if mockEnvironment.traceLimiter then
        -- Observe cleanup calls while delegating all behavior to the REAL limiter.
        local calls = { clear = 0, forget = 0 }
        mockEnvironment.limiterCalls = calls
        limiterDependency = {
            new = function(capacity, refillPerSecond)
                local real = actualRateLimiter.new(capacity, refillPerSecond)
                return {
                    Allow = function(_self, userId) return real:Allow(userId) end,
                    Forget = function(_self, userId)
                        calls.forget += 1
                        real:Forget(userId)
                    end,
                    Clear = function(_self)
                        calls.clear += 1
                        real:Clear()
                    end,
                }
            end,
        }
    end

    local validateSentinel, limiterSentinel = {}, {}
    local environment = setmetatable({
        game = mockEnvironment.game,
        script = { Validate = validateSentinel, RateLimiter = limiterSentinel },
        typeof = function(value)
            if type(value) == "table" and rawget(value, "_mockInstance") == true then
                return "Instance"
            end
            return typeof(value)
        end,
        require = function(reference)
            if reference == validateSentinel then return actualValidate end
            if reference == limiterSentinel then return limiterDependency end
            error("unexpected mocked require reference")
        end,
    }, { __index = baseEnvironment })
    local factory = compile(guardSource, "src/init.luau")
    setfenv(factory, environment)
    return factory()
end

local suite = compile(suiteSource, "tests/Binding.spec.luau")()
local total, failures = suite(loadGuard)
print(string.format("Binding mock tests: %d passed, %d failed (%d total)", total - failures, failures, total))
if failures > 0 then error("binding mock tests failed", 0) end
`;

const buildDirectory = join(root, ".test-build");
mkdirSync(buildDirectory, { recursive: true });
const runnerPath = join(buildDirectory, "binding-runner.luau");
writeFileSync(runnerPath, runner, "utf8");

const result = spawnSync(executable, [runnerPath], {
  cwd: root,
  shell: false,
  stdio: "inherit",
});
if (result.error) {
  console.error(`Could not start Luau: ${result.error.message}`);
  console.error("Usage: node tools/test-binding.mjs [path-to-luau]");
  process.exitCode = 1;
} else {
  process.exitCode = result.status ?? 1;
}
