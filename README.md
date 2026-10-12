# Roblox Remote Guard

A small, dependency-free Luau library for validating Roblox `RemoteEvent`
payloads and limiting server-side request handling per player.

Remote Guard turns recurring server-side validation and cooldown patterns into
reusable modules. It is an early project informed by those patterns in the
maintainer's existing Roblox game. The standalone library has not yet been
integrated into that game for production use. External adoption has not been
measured or verified.

## What it provides

- Composable validators for finite numbers, integers, UTF-8 strings, booleans,
  string enums, optional values, bounded dense arrays and closed records.
- A token bucket per player with configurable burst and refill rate.
- A server-only RemoteEvent binding that validates before authorization and
  handling, prevents overlapping handlers for the same player and binding,
  cleans up departing players, and exposes aggregate counters.
- A standalone pickup example, repeatable tests, a Rojo layout and MIT license.

No assets, external packages, HTTP calls or DataStores are required by the library.

## Installation

### Roblox Studio

Download `RemoteGuard.rbxmx` from the [0.1.0 alpha release](https://github.com/younesha321-hub/Roblox-Game-Creation-Vfx/releases/tag/v0.1.0).
You can also build the same model from the source with Node.js:

```sh
node tools/build-model.mjs
```

In Studio, right-click **ServerScriptService**, choose **Insert from File**, and
select `dist/RemoteGuard.rbxmx`. The resulting structure is:

```text
ServerScriptService
└── RemoteGuard (ModuleScript, from src/init.luau)
    ├── Validate (ModuleScript)
    └── RateLimiter (ModuleScript)
```

Alternatively create this structure manually and paste each source into the
matching ModuleScript. Keep the binding module on the server.

### Rojo

The provided `default.project.json` maps the library into ServerScriptService.
Merge that mapping into your project's Rojo configuration. For the standalone
example, build `demo.project.json` and open the resulting place in Studio:

```sh
rojo build demo.project.json -o RemoteGuardDemo.rbxlx
```

Run the demo in a separate test place. Walk near the green cube and press **E**
or tap the button. The server checks distance and availability before awarding
a point. The cube becomes available again after two seconds.

## Basic usage

Create a `RemoteEvent` named `BuyItem` under ReplicatedStorage. The client sends
one payload table. It sends the item ID and quantity; prices and balances belong
to the server.

```luau
local RemoteGuard = require(game.ServerScriptService.RemoteGuard)
local V = RemoteGuard.Validate
local remote = game.ReplicatedStorage.BuyItem

local binding = RemoteGuard.Bind(remote, {
    validate = V.record({
        itemId = V.oneOf({ "potion", "shield" }),
        quantity = V.integer(1, 5),
    }),
    capacity = 4,
    refillPerSecond = 2,
    authorize = function(player, payload)
        -- Implement this in your game: ownership, balance, distance and state.
        return ShopService:CanBuy(player, payload.itemId, payload.quantity)
    end,
    handle = function(player, payload)
        -- This operation must recheck shared state and commit atomically.
        ShopService:Buy(player, payload.itemId, payload.quantity)
    end,
})

-- When this feature is removed or replaced:
-- binding:Destroy()
```

`ShopService` above represents your own server-side implementation. For a
complete runnable example, use `examples/Pickup.server.luau` and
`examples/Pickup.client.luau`.

```luau
-- Client: one payload argument.
game.ReplicatedStorage.BuyItem:FireServer({ itemId = "potion", quantity = 1 })
```

## Validator API

Every validator is a function returning `(accepted: boolean, reason: string?)`.
Invalid developer configuration throws an assertion. Rejected payloads return
false with a short reason that does not echo their contents.

| Constructor | Accepts |
| --- | --- |
| `V.number(min, max)` | Finite numbers in the inclusive range |
| `V.integer(min, max)` | Whole finite numbers in the inclusive integer range |
| `V.string(maxBytes, minBytes?)` | Valid UTF-8 within byte bounds; minimum defaults to 0 |
| `V.boolean()` | `true` or `false`, without coercion |
| `V.oneOf({ "a", "b" })` | Only the listed strings; choices must be a nonempty dense array |
| `V.optional(validator)` | `nil` or a value accepted by the wrapped validator |
| `V.array(validator, maxItems)` | A dense array with at most maxItems, including an empty array |
| `V.record({ field = validator })` | A plain table with the declared fields and no extra fields |

Arrays and records reject metatables. Record fields are required unless wrapped
in `optional`. Schemas are copied at construction; mutating the original enum or
field table does not change an existing validator. Use explicit finite schemas
with small field, byte and item bounds. Nested work is determined by those
bounds; custom recursive validators must supply their own depth and cycle limits.

## Rate limiter API

```luau
local RateLimiter = require(game.ServerScriptService.RemoteGuard.RateLimiter)
local limiter = RateLimiter.new(4, 2) -- burst of 4, refill 2 tokens per second
local allowed, retryAfterSeconds = limiter:Allow(player.UserId)
limiter:Forget(player.UserId)
-- limiter:Clear()
```

Capacity is a positive integer; refill rate is finite and positive. User keys are
finite integers, including zero and negative IDs for local test fixtures. `Allow` spends one
token on success and returns a delay on denial. Each player has a separate bucket.
Manual users must call `Forget` when the player leaves. The binding does this for
you. Pass a third argument, `clock`, for deterministic tests. Backward clock
movement cannot refill a bucket; retry time also includes recovery to its prior
time watermark.

## Binding behavior and limits

Each `Bind` call has its own limiter. For separate actions, use separate remotes
and bindings or compose a game-specific action layer. Exactly one argument is
accepted, including an explicit `nil` if its validator permits it.

Invalid requests consume tokens before validation. Validator and authorization
callbacks must return exactly `true` to proceed. During any yielding callback,
further requests by that player to the same binding are rejected as busy if a
token is available; requests with no token are counted as rateLimited first. This
does not serialize different players or different bindings. Authorization should
be quick; important mutations must recheck shared state and commit without yielding.

`binding:GetStats()` returns a frozen snapshot with `accepted`, `invalid`,
`rateLimited`, `busy`, `unauthorized`, `errors` and `inactive`. Callback failures
increment `errors`; the library does not log payloads, kick players or roll back
game changes. `Destroy` disconnects both signals and clears internal state. A
handler already running at destruction cannot be cancelled automatically.

This library controls server handler execution after event delivery. Game-specific
authorization, distance, balances and ownership checks are still required. Bind
the protected handler through the library; other listeners on the same remote
remain independent. See [SECURITY.md](SECURITY.md).

## Development and tests

Use the official [Luau CLI](https://github.com/luau-lang/luau/releases) and Node.js.
From the repository root:

```sh
luau tests/run.luau
node tools/test-binding.mjs
luau-analyze src/Validate.luau src/RateLimiter.luau
node tools/build-model.mjs
```

The binding runner reads the current production sources and supplies explicit
mock services and signals. It does not test actual Roblox networking. A custom
Luau executable path may be supplied as its first argument. All scripts and
examples are also syntax-compiled in CI. The adapter uses Roblox types; the
standalone analyzer check covers the engine-independent modules.

See [docs/VALIDATION.md](docs/VALIDATION.md) for the latest checks actually run
and their limits. A Studio playtest with two clients is still needed before a
production integration. No production use or performance benchmark is claimed.

On Windows, `powershell -File tools/Verify.ps1` downloads the verified official
Luau 0.742 archive locally when needed, runs the checks and builds the model.
Node.js must be available. To repeat the isolated engine core check, run
`node tools/build-studio-tests.mjs`, then paste `dist/RunCoreTests.command.luau`
into Studio's Command Bar in Edit mode. That command loads current library
sources into unparented modules; it does not change the game's scripts or test
network delivery.

## Repository layout

```text
src/                    Library modules
examples/               Standalone server and client pickup example
tests/                  Behavioral core tests and mock binding tests
tools/                  Model generator and binding test runner
docs/                   Validation evidence
.github/workflows/      Continuous checks
default.project.json    Library mapping for Rojo
demo.project.json       Standalone demo place mapping
LICENSE                 MIT license
```

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). The scope is
payload validation and request handling. Features requiring persistent storage,
automatic punishment or asset access belong in separate game-specific systems.
