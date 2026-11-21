---
name: simsalabim
description: Configure Bluetooth, camera and NFC providers for an iOS Simulator app with Simsalabim, or seed a booted simulator with reproducible Contacts, Calendar, Reminders, Photos or Health data.
---

# Simsalabim

**Hardware providers.** The simulator app target must link `SimsalabimClient` or the relevant individual bridge. The macOS suite owns the providers. Modes are independent per module. Use `mock` for configured fixtures, `passthrough` for Mac hardware and `off` to disable a provider.

```sh
simsalabim status --json
simsalabim mode impossible mock --launch
simsalabim status --json
```

The module names are `impossible` (BLE), `camouflage` (camera) and `nfcromancer` (NFC). Read the previous mode before a temporary test, verify the selected mode and exercise the feature in the simulator app. Restore the changed module afterwards. If the suite is stopped, `status` exits 69 and `mode --launch` can start it. A standalone provider can own the same socket; check the owner if the module reports Blocked.

**Simulator data.** The CLI uses the fixture saved by Simulacrum at `~/Library/Application Support/Simulacrum/fixture.json`. Seeding works for ordinary simulator apps without linking a bridge. Use the suite's seeding UI while the suite owns the seed socket, or run the CLI with that socket free. Select a booted target and the categories requested. Omitting category flags seeds all supported categories.

```sh
xcrun simctl list devices booted
simsalabim seed --contacts --calendar --device "$udid" --json
```

Set `udid` to the selected simulator's identifier. Inspect the exit status and summary counts and errors before relying on the data. The first Health seed requires an interactive authorization in that simulator. Check `simsalabim seed --help` for `--health` on older installations. From the suite checkout, `make cli` builds `simsalabim-cli/simsalabim` with its sibling SeedAgent and fixtures; keep those resources together.
