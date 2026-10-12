# Contributing

Small, well-explained fixes and practical Roblox examples are welcome.

1. Explain the problem and the expected behavior in an issue or pull request.
2. Keep validation bounded and keep authority on the server.
3. Add a regression case for a behavior change. Do not edit generated model files.
4. Run the commands in the README and state which checks you actually ran.
5. Describe any changes to the public API or installation steps.

Tests use an injected clock instead of waiting for wall-clock time. Binding tests
use mock signals; changes involving Roblox networking also need a Studio playtest.
Contributions are licensed under the project's MIT license.
