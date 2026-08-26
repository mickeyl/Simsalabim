# Agent Notes

## Project Shape

- `Sources/SuiteApp` — the suite menu bar app: `SuiteRuntime` (one server +
  mode controller per product), `SuiteStatusBarController` (composite status
  icon, panel, ImpossiBLE's capture/editor document windows), and
  `SuitePanelContent` (stacked provider sections + shared footer).
- `Modules/ImpossiBLE`, `Modules/CAMouflage`, `Modules/NFCromancer`,
  `Modules/Simulacrum` — git submodules of the product repos. The suite
  consumes their nested provider packages via **path dependencies**
  (`Modules/<P>/Sources/<P>-Mac`), so a `git clone --recursive` builds
  without any tag-bump dance. The submodule pins are the record of which
  product versions a suite release ships.
- `PLAN.md` — the consolidation plan that produced this architecture
  (Steps 1–3 happened in the product repos and SimBridgeKit).
- `Assets/` — logo and app icon sources. `make` renders `Assets/AppIcon.png`
  into the bundle's `.icns` when present.

## Invariants

- **Dependency arrows only point downward**: Simsalabim → products →
  SimBridgeKit. Nothing in this repo may be depended upon by a product or the
  kit; the products must remain individually installable without this repo.
- **SPM package identity is the directory basename.** The nested provider
  packages live in `Sources/ImpossiBLE-Mac` / `Sources/CAMouflage-Mac`
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

## Panel layout: exclusive accordion (and the splitter history behind it)

Since 2026-08-24 the panel is an **exclusive accordion**: all module headers
stay visible (status dots included), exactly one module is expanded at a time
(persisted as the `ExpandedModule` defaults key; empty = all collapsed), and
the expanded module takes the full remaining pane — the same room its
standalone app would offer. This replaced the earlier collapse-flags-plus-
splitter layout, whose height math across N heterogeneous panes never carried
its weight and had a known gap (fixed tail panes weren't subtracted from the
flexible panes' budget).

The splitter that layout used froze both panes while dragging — only the grip
travelled (a pure `.offset`, no layout) and the stored height was applied
once, on release. That was deliberate and was arrived at the hard way; the
lessons below are why any future return to multiple simultaneously-resizing
panes must be re-measured first:

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
   `<Name>ProviderKit` library from `Sources/<Name>-Mac`).
2. Add the path dependency and product to `Package.swift`.
NFCromancer was added 2026-08-19 as the reference third module — it needs the
`com.apple.security.smartcard` entitlement (unioned into `Resources/`). The
suite's client row now aggregates all three provider sockets generically.
(It originally sat as a fixed-height pane below the then-splitter layout;
that distinction disappeared with the accordion.)

Simulacrum was added 2026-08-24 as the fourth module and the first that
doesn't fit the mode-picker shape at all — see its own
`~/Documents/late/Simulacrum/SEEDING_PLAN.md` for the design. No
`ProviderMode`/`ModeTransitionController`: `SeedServer` just binds
`/tmp/simulacrum.sock` in `SuiteRuntime.init()` (`.start()` called directly,
no controller-driven start/stop), and stops in the quit chain like the other
three. Its panel section is one accordion pane like everyone else's.
It does **not** join the client row (its "device bar" is a booted-simulator
picker, a different concept from a connected simulator-app client) and does
**not** contribute to the composite menu-bar icon (no persistent "on" state
to represent there — the status dot in its own header reflects the last
seed run instead: `.secondary` idle/clean, `.blue` running, `.orange`
finished-with-errors, `.red` failed). The suite's own `Makefile` gained an
`$(AGENT_APP)`/`bundle-agent` step that cross-compiles `SeedAgent` from
`Modules/Simulacrum` for the iOS Simulator SDK and copies the ad-hoc-signed
`.app` plus fixture photo swatches into `Resources/` — wired into both
`suite` and `suite-debug`, mirroring how the module icons/font already get
bundled. No entitlement changes: `SeedRunner` only shells out to `simctl`
and opens a Unix socket, neither needs anything beyond what the (non-
sandboxed) suite app already has.

3. Extend `SuiteRuntime` (server + mode controller — or just a `.start()`
   call for a module with no mode, like Simulacrum), `SuitePanelContent`
   (one new `Module` enum case + a `moduleHeader` call + the expanded pane;
   the accordion hands the open module the full pane, so there are no
   per-module sizing keys to add), and the composite icon in
   `SuiteStatusBarController` (skip the icon contribution if the module has
   no ongoing "on"/"off" state to represent there).
4. Union the module's usage descriptions/entitlements into `Resources/`.

## Release Checklist

- `make check-pins` — every submodule pin must be a release tag reachable on
  its `origin/master`.
- Bump `CFBundleShortVersionString` in `Resources/Info.plist`.
- `make suite && make assess`, then `make notarize NOTARY_PROFILE=…` — or, where
  no notarytool keychain profile exists, zip the bundle (`ditto -c -k
  --keepParent --sequesterRsrc`), `asc notarization submit --file Simsalabim.zip
  --wait`, `xcrun stapler staple Simsalabim.app`, and re-zip.
- Tag, push, GitHub release.

## Validation

```bash
make bootstrap                    # after a fresh clone
make relaunch                     # debug build + restart
# Both sections serve their sockets: seed modes headlessly, then probe
defaults write de.vanille.simsalabim ImpossiBLEMode mock
defaults write de.vanille.simsalabim CAMouflageMode mock
```
