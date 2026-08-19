# Agent Notes

## Project Shape

- `Sources/SuiteApp` — the suite menu bar app: `SuiteRuntime` (one server +
  mode controller per product), `SuiteStatusBarController` (composite status
  icon, panel, ImpossiBLE's capture/editor document windows), and
  `SuitePanelContent` (stacked provider sections + shared footer).
- `Modules/ImpossiBLE`, `Modules/CAMouflage` — git submodules of the product
  repos. The suite consumes their nested provider packages via **path
  dependencies** (`Modules/<P>/Sources/<P>-Mock`), so a
  `git clone --recursive` builds without any tag-bump dance. The submodule
  pins are the record of which product versions a suite release ships.
- `PLAN.md` — the consolidation plan that produced this architecture
  (Steps 1–3 happened in the product repos and SimBridgeKit).
- `Assets/` — logo and app icon sources. `make` renders `Assets/AppIcon.png`
  into the bundle's `.icns` when present.

## Invariants

- **Dependency arrows only point downward**: Simsalabim → products →
  SimBridgeKit. Nothing in this repo may be depended upon by a product or the
  kit; the products must remain individually installable without this repo.
- **SPM package identity is the directory basename.** The nested provider
  packages live in `Sources/ImpossiBLE-Mock` / `Sources/CAMouflage-Mock`
  precisely so both can coexist in one graph; a directory rename there breaks
  this repo's manifest.
- **Per-module sockets, per-module modes.** There is no global mode: BLE
  passthrough plus camera mock is legitimate. The suite's persisted modes use
  its own defaults domain (`de.vanille.simsalabim`, keys `ImpossiBLEMode` /
  `CAMouflageMode`), so they never collide with the standalone apps'.
- **Coexistence with standalone apps is guard-mediated, not managed.** If a
  standalone app owns a provider socket, the suite's section shows Blocked
  (and vice versa) via SimBridgeKit's ownership guard. To move a module into
  the suite, quit the standalone app and reselect the mode.
- ImpossiBLE's mock devices are shared state: `MockStore` persists in
  `~/Library/Application Support/ImpossiBLE/`, so suite and standalone app
  see the same device configurations. CAMouflage's fixture selection lives in
  UserDefaults and is therefore per-app.
- Info.plist/entitlements are the union of the module requirements (Bluetooth
  + camera usage descriptions and Hardened Runtime device entitlements). A
  new module must extend both.

## Adding a module

1. `git submodule add <repo> Modules/<Name>` (the product must expose a
   `<Name>ProviderKit` library from `Sources/<Name>-Mock`).
2. Add the path dependency and product to `Package.swift`.
3. Extend `SuiteRuntime` (server + mode controller), `SuitePanelContent`
   (section + module header + collapsed/pane-height keys — every boundary
   between adjacent expanded modules gets a drag splitter; the last expanded
   pane takes the remainder), and the composite icon in
   `SuiteStatusBarController`.
4. Union the module's usage descriptions/entitlements into `Resources/`.

## Release Checklist

- `make check-pins` — both submodule pins must be release tags reachable on
  their `origin/master`.
- Bump `CFBundleShortVersionString` in `Resources/Info.plist`.
- `make suite && make assess`, then `make notarize NOTARY_PROFILE=…`.
- Tag, push, GitHub release.

## Validation

```bash
make bootstrap                    # after a fresh clone
make relaunch                     # debug build + restart
# Both sections serve their sockets: seed modes headlessly, then probe
defaults write de.vanille.simsalabim ImpossiBLEMode mock
defaults write de.vanille.simsalabim CAMouflageMode mock
```
