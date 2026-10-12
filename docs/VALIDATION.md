# Validation evidence

Checked on **12 October 2026** against the files in this package.

| Check | Result | Scope |
| --- | --- | --- |
| Official Luau 0.742 CLI, `tests/run.luau` | 44 passed, 0 failed | Current validator and token-bucket production sources |
| Roblox Studio, isolated generated core command | Same 44 cases passed, 0 failed | Actual ModuleScript loading and core behavior in the engine |
| Luau 0.742, `tools/test-binding.mjs` | 20 passed, 0 failed | Actual adapter source with explicit mock Roblox services and signals |
| `luau-analyze` on Validate and RateLimiter | Passed | Engine-independent module type analysis |
| `luau-compile --null` on all library, test and example sources | Passed | Syntax and bytecode compilation; not a full engine type analysis |
| Studio model generation | Passed | Model generated directly from the current sources |
| GitHub Actions, first public commit | Passed | [Luau checks run](https://github.com/younesha321-hub/Roblox-Game-Creation-Vfx/actions/runs/38263690875), commit `e2f8a84a6e90162e10b501067b6c54e6d0cc87f5` |

There are **64 distinct behavioral cases**. Running the same 44 core cases in
two runtimes does not create 88 distinct cases. Neither the test counts nor the
presence of a CI configuration imply downstream adoption.

Core checks cover finite-number boundaries, malformed UTF-8, byte lengths,
unknown fields, immutable schemas, dense arrays, metatables, finite nested
schemas with cyclic payloads, exact Boolean results, burst capacity, fractional
refill, independent players, cleanup, invalid configurations and backward clocks.

Binding checks cover argument counts including explicit nil, token consumption
before validation, authorization, exceptions, reentrant requests, separate
players, cleanup, immutable stats, callback snapshots, shutdown during
authorization and the real limiter's refill behavior.

The Studio command creates unparented ModuleScripts and destroys the temporary
root after execution. It does not alter the game's live scripts. No game was
published or migrated as part of this check.

## Remaining integration work

- The pickup example has been syntax-compiled, but not playtested end to end.
- Actual RemoteEvent network delivery and concurrent yielding callbacks with two
  real Studio clients have not been tested by the mock signal suite.
- The standalone library has not been integrated into a production game.
- No performance, transport-level denial-of-service or external adoption claims
  are made. The first public GitHub Actions run completed successfully.

Before production use, playtest the demo in a separate place with two clients,
check valid, malformed and repeated requests, verify independent limits and
player cleanup, and review game-specific authorization and atomic state changes.
Update this document only with checks actually performed.
