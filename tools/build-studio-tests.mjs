import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const quote = text => {
  let marker = '';
  while (text.includes(`]${marker}]`)) marker += '=';
  return `[${marker}[\n${text}]${marker}]`;
};
const read = file => quote(fs.readFileSync(path.join(root, file), 'utf8'));
const code = `-- Generated from current sources. Run in the Studio Command Bar in Edit mode.
-- No objects are parented into the game's DataModel; no live scripts are changed.
local root = Instance.new("ModuleScript")
root.Name = "RemoteGuardIsolatedTests"
root.Source = ${read('src/init.luau')}
local validate = Instance.new("ModuleScript")
validate.Name = "Validate"
validate.Source = ${read('src/Validate.luau')}
validate.Parent = root
local limiter = Instance.new("ModuleScript")
limiter.Name = "RateLimiter"
limiter.Source = ${read('src/RateLimiter.luau')}
limiter.Parent = root
local suite = Instance.new("ModuleScript")
suite.Name = "CoreTests"
suite.Source = ${read('tests/Core.spec.luau')}
suite.Parent = root
local ok, report = pcall(function()
    local library = require(root)
    return require(suite)(library.Validate, library.RateLimiter)
end)
root:Destroy()
if not ok then error(report) end
for _, result in ipairs(report.cases) do
    if not result.passed then warn(result.name, result.error) end
end
print(string.format("RemoteGuard Studio core: %d passed; %d failed", report.passed, report.failed))
assert(report.failed == 0, "Studio core tests failed")
return report
`;
fs.mkdirSync(path.join(root, 'dist'), { recursive: true });
fs.writeFileSync(path.join(root, 'dist', 'RunCoreTests.command.luau'), code, 'utf8');
console.log('Built isolated Studio core test command from current sources.');
