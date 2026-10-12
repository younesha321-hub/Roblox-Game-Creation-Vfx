# Security reports

If you find a flaw in this library, use the repository's **Security > Report a
vulnerability** feature when available. If private reporting is unavailable,
open an issue describing the affected API and impact without disclosing details
of an attack against a live game. This early project has no guaranteed response time.

Remote Guard validates inputs and limits handler execution. Developers must still
check authorization, distance, ownership, balances and shared game state on the
server. A valid payload does not prove a legitimate action.

Rate limits begin after Roblox delivers an event to the server. They do not prevent
transport-level traffic or protect handlers connected separately to the same remote.
Callback failures are counted, not rolled back. Keep important state transitions
atomic and inspect `GetStats().errors` during development.
