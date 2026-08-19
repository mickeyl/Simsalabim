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

## Performance: why the splitter uses delayed resize

The pane splitter freezes both panes while dragging — only the grip travels
(a pure `.offset`, no layout) and the stored height is applied once, on
release. This is deliberate and was arrived at the hard way; do not "fix" it
back to live resizing without re-measuring:

- **Live resize stuttered badly**, even on a 20-core machine, because the
  entire path is serial on the main thread: every mouse event (~100/s, above
  display refresh) synchronously triggered layout + commit of the whole
  panel.
- **It was not SwiftUI diffing.** `_logChanges()` instrumentation during a
  real drag showed ~1200 body evaluations of the (cheap) panel content and
  essentially zero re-evaluations of the provider sections. Pre-scaling the
  brand icons and rasterizing their shadows (`drawingGroup`) did not help
  either — those fixes remain because they are correct, but they were not
  the bottleneck.
- **The bottleneck is AppKit, not SwiftUI:** SwiftUI `ScrollView`s on macOS
  are `NSScrollView`-backed, and resizing that machinery (tiling, scroller
  layout, document-view invalidation) at mouse-event rate is far too
  expensive. The killer in practice was ImpossiBLE's device list in Mock
  mode; frame-by-frame video analysis showed near-full-panel repaints on
  nearly every captured frame.
- Related lesson, learned in the same session: never route per-tick gesture
  values through `@AppStorage`/UserDefaults — the change-notification
  round-trip interleaves with the gesture's own updates. Buffer in `@State`,
  persist on `.onEnded`.

If true live resizing is ever wanted, the path is to make the pane contents
resize-cheap first — e.g. move the device lists to `List`
(`NSTableView`-backed, optimized for live resize) — and re-measure before
switching the splitter behavior.

## Adding a module

1. `git submodule add <repo> Modules/<Name>` (the product must expose a
   `<Name>ProviderKit` library from `Sources/<Name>-Mock`).
2. Add the path dependency and product to `Package.swift`.
NFCromancer was added 2026-08-19 as the reference third module — it needs the
`com.apple.security.smartcard` entitlement (unioned into `Resources/`) and sits
as the last, intrinsic-height pane below the BLE↔CAM splitter. The suite's
client row now aggregates all three provider sockets generically.

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
