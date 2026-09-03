# Simsalabim — Consolidation & Umbrella Plan

> **Status (2026-08-18): all four steps are implemented.** Step 1 shipped as
> ImpossiBLE 3.0.0 (helper daemon folded into the mock app; notarization still
> pending a notarytool credential profile). Step 2: SimBridgeKit
> (github.com/mickeyl/SimBridgeKit) carries the shared transport and menu bar
> shell; both products adopted both components. Step 3: both products expose
> `ImpossiBLEProviderKit` / `CAMouflageProviderKit` library products wrapped by
> thin standalone executables. Step 4: this repo — the Simsalabim suite app —
> embeds both ProviderKits under one status item, with the products as git
> submodules. This file is the plan that produced the architecture; the
> repo's AGENTS.md describes the current state.

**Making the impossible possible in the iOS Simulator — as a suite.**

Simsalabim is the umbrella over the simulator-retrofitting products. Each
product stays an individually installable, self-contained tool; Simsalabim
binds them into one host app, one brand, one distribution channel.

Current members:

- **ImpossiBLE** — CoreBluetooth central role (`~/Documents/late/ImpossiBLE`)
- **CAMouflage** — AVFoundation capture (`~/Documents/late/CAMouflage`)

Future candidates (out of scope here, listed so the architecture leaves room):
ExternalAccessory (MFi), CoreNFC, CoreMotion, iBeacon ranging, CoreBluetooth
peripheral role.

---

## 1. Constraints (non-negotiable)

1. **ImpossiBLE and CAMouflage remain individual products.** Separate repos,
   separate release cadence, separate standalone mock apps, installable and
   usable without Simsalabim.
2. **Simsalabim integrates them via git submodules** and builds one suite menu
   bar app from their exported host-side libraries.
3. **Dependency arrows only point downward:**
   `Simsalabim → products → SimBridgeKit`. A product must never depend on the
   umbrella, and SimBridgeKit must never depend on a product. Anything that
   violates this breaks constraint 1.
4. **The simulator-side libraries stay separate SPM products.** An app that
   tests only camera flows must not link CoreBluetooth swizzles, and vice
   versa. Every `+load` swizzle is SDK-breakage surface; blast-radius
   separation is a feature.
5. **Wire formats are the seam.** All refactoring below keeps the socket
   protocols unchanged unless a change is called out explicitly (§5).

## 2. Target architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Simsalabim.app  (umbrella repo, git submodules)             │
│   suite menu bar app: one status item, per-module sections  │
│   Modules/ImpossiBLE   (submodule)                          │
│   Modules/CAMouflage   (submodule)                          │
├─────────────────────────────────────────────────────────────┤
│ Product repos (unchanged sovereignty)                       │
│   ImpossiBLE:  library (sim) + ImpossiBLEProviderKit (mac)  │
│                + thin standalone ImpossiBLE-Mac.app        │
│   CAMouflage:  library (sim) + CAMouflageProviderKit (mac)  │
│                + thin standalone CAMouflage-Mac.app        │
├─────────────────────────────────────────────────────────────┤
│ SimBridgeKit  (own repo, SPM package, macOS + iOS targets)  │
│   host: UDS server, NDJSON envelope, takeover semantics,    │
│         client-fixture lifecycle, socket-ownership guard,   │
│         menu bar shell (status item, panel, mode control,   │
│         launch-at-login, preferences)                       │
│   sim:  (optional, later) shared connection core            │
└─────────────────────────────────────────────────────────────┘
```

Each module keeps its own socket (`/tmp/impossible.sock`,
`/tmp/camouflage.sock`, plus the CAMouflage frame socket). The suite app is
purely a different host binding the same sockets — simulator libraries cannot
tell the difference.

## 3. Package boundaries

### 3.1 Product repos: nested provider packages stay nested

Both products already carry a second `Package.swift` in `Sources/MockApp`
(macOS 15, executable-only). We keep that nesting rather than folding the
provider into the root package: the root packages are iOS-platform simulator
libraries, and merging macOS provider targets into them would force a combined
platform list and build every product for every destination. The umbrella can
reference nested packages directly via path dependencies — submodules make
that natural.

Refactor per product (mechanical, no behavior change):

```
Sources/MockApp/Package.swift        # gains a library product
  targets:
    <Name>ProviderKit  (library)     # Server/, Models/, Views/ panel sections
    <Name>-Mac        (executable)  # MacApp.swift + StatusBarController glue
  products:
    .library(name: "<Name>ProviderKit", targets: ["<Name>ProviderKit"])
    .executable(name: "<Name>-Mac", ...)
```

What goes where:

- **ProviderKit**: socket server + responders, device/fixture models, the
  panel *content* views (device list, editors, capture sheet, passthrough
  picker), activity state. Public API surface: a `Provider` facade the shell
  can start/stop/query, plus a SwiftUI section view.
- **Thin app**: `@main`, app lifecycle, and the SimBridgeKit shell wired to
  exactly one ProviderKit. After Step 2 this shrinks to ~50 lines.
- ImpossiBLE's FontAwesome resource stays in ProviderKit (SPM resource rules
  already handle it).

### 3.2 SimBridgeKit contents (extraction targets)

Host-side (macOS target), extracted from today's duplicated code:

| Component | Today in ImpossiBLE | Today in CAMouflage |
|---|---|---|
| UDS server (bind/listen/accept, `SO_NOSIGPIPE`, unlink discipline) | `MockServer.swift` | `MockCameraServer.swift` |
| NDJSON envelope (type + payload codec) | `MockServer.swift` | `MockCameraServer.swift` |
| Takeover semantics (last-connection-wins, see §5) | divergent | `MockCameraServer.swift` |
| Client-fixture lifecycle (ephemeral / visible / verified, cleared on both connection edges) | `MockServer` client-supplied paths | `ClientMockConfiguration` |
| Socket-ownership guard (new, see §6) | missing (known follow-up) | missing |
| Menu bar shell: status item, borderless panel, mode controller, footer toggles, launch-at-login | `StatusBarController`, `ProviderModeController`, `AppPreferences` | `StatusBarController`, `ProviderMode`, `AppPreferences` |
| `AppVersion` (git-count build number) | duplicated | duplicated |

Simulator-side sharing (`CBSConnection` / `CMFConnection` are ports of each
other) is deliberately **deferred**: the libraries are ObjC, vendored-in-place,
and their independence is constraint 4. Revisit only when a third simulator
library would create a third copy.

## 4. Migration steps, in order

Order matters: each step reshapes code the next step builds on. Do not start
the Simsalabim repo before Steps 1–3 are done, so it builds against the final
interfaces from day one.

### Step 1 — ImpossiBLE: fold the helper daemon into the mock app

Adopt the CAMouflage shape (its `AGENTS.md` architecture note is the
rationale; the same two-process test applies: mock and passthrough never run
simultaneously, and macOS CoreBluetooth does not need crash isolation from the
UI).

1. Move `Sources/Helper/CBSHelperMain.m` (~1650 lines, single-file clang
   build) into the MockApp package as an ObjC target
   (`ImpossiBLEPassthroughCore`); SPM handles mixed languages across target
   boundaries. Strip `main`/socket-listener code; keep the CoreBluetooth ⇄
   JSON translation layer. Porting to Swift is optional and incremental,
   not a precondition.
2. Introduce a responder seam in the mock app's server: one socket owner
   dispatching to `MockResponder` (today's mock logic) or
   `PassthroughResponder` (the extracted translation layer), selected by the
   existing Off/Mock/Passthrough mode.
3. Delete the supervision apparatus: `ForwarderController` (~400 lines),
   `pgrep`/LaunchServices mutual exclusion, "Keep Helper on Quit" (the app is
   `LSUIElement` with launch-at-login; a headless helper mode has no remaining
   audience). Replace the passthrough-activity *file* handoff
   (`/tmp/impossible-passthrough-activity.json`) with direct in-process state —
   the file existed only because the activity lived in another process.
4. Rewrite the capture workflow to use CoreBluetooth directly in-process.
   Today it stops the mock server, launches the helper, connects as a socket
   client, scans, then reverses everything. All of that collapses into a
   `CBCentralManager` owned by the capture sheet.
5. Entitlements/TCC: add `NSBluetoothAlwaysUsageDescription` to the mock app's
   `Info.plist` and `com.apple.security.device.bluetooth` to
   `entitlements.plist`. This is the exact "works in debug (ad-hoc, Hardened
   Runtime off), denied in release" trap CAMouflage documented for the camera
   entitlement — handle it now, not after the first mystery report. Ad-hoc dev
   builds re-prompt TCC after every rebuild; expected, document it.
6. Makefile: remove `helper`/`debug`/`run`/`stop`/`restart`/`watch`/
   `helper-assess`/`helper-notarize` targets and the `bin/` install path;
   `mock-*` targets become the only surface. Update README (two-process
   description, Forwarding-vs-Mocking section, Makefile table) and AGENTS.md.
7. Unify takeover semantics while touching the server (§5).

Wire format on `/tmp/impossible.sock` is unchanged; existing client libraries
keep working against the new provider.

**Validate:**

```bash
make mac-clean mac && open ImpossiBLE-Mac.app
# SampleApp in the simulator: Mock mode serves fixtures; Passthrough scans,
# connects, reads/writes/subscribes, opens L2CAP against real hardware.
# Capture: scan + deep inspection works without any helper process appearing
# in `ps`. Release-signed build: passthrough works (entitlement present).
xcodebuild -project SampleApp/SampleApp.xcodeproj -scheme SampleApp \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

### Step 2 — Extract SimBridgeKit

1. New repo `SimBridgeKit`, SPM package, macOS 15 target. Seed it from the
   *CAMouflage* copies where they diverge (they are the younger, cleaner
   port), then reconcile ImpossiBLE-only features (persistent panel,
   dismiss-on-switch, footer confirmation toasts) into the shell.
2. Both nested provider packages take SimBridgeKit as a URL-based SPM
   dependency (tagged releases). For co-development use
   `swift package edit SimBridgeKit` (or drag the local package into an Xcode
   workspace); do **not** also vendor it as a submodule with a path dependency
   — the same package identity from two locations does not resolve.
3. Move the components from §3.2 one at a time, each landing in both products
   before the next moves. Big-bang extraction of all six rows invites a
   two-repo debugging session.
4. Implement the socket-ownership guard (§6) here so both products inherit it.

**Validate:** both standalone mock apps build against SimBridgeKit `main`,
full manual pass per product (mode switching, fixtures, passthrough, client
fixtures, panel behavior), plus each repo's existing validation recipe.

### Step 3 — ProviderKit split in both products

Apply §3.1: split each nested package into ProviderKit library + thin
executable. Pure target surgery — no logic changes — so review stays cheap.
The standalone apps must remain byte-for-byte equivalent in behavior.

**Validate:** `cd Sources/MockApp && swift build` per product; standalone app
smoke test per product; `plutil -lint` on the plists.

### Step 4 — Create the Simsalabim repo

```
Simsalabim/
├── Package.swift            # suite app target
│     .package(path: "Modules/ImpossiBLE/Sources/MockApp")
│     .package(path: "Modules/CAMouflage/Sources/MockApp")
│     + SimBridgeKit (transitive; resolve to the same tag both products pin)
├── Modules/
│   ├── ImpossiBLE/          # git submodule, pinned to a release tag
│   └── CAMouflage/          # git submodule, pinned to a release tag
├── Sources/SuiteApp/        # one status item, per-module panel sections,
│                            # per-module Off/Mock/Passthrough, shared footer
├── Makefile                 # ported shell: mock/notarize/relaunch/status/log
├── PLAN.md                  # this file, moved here
├── README.md                # suite pitch + links to product READMEs
└── AGENTS.md                # umbrella invariants (dependency direction, §6)
```

Suite app specifics:

- One `Simsalabim.app` menu bar item; the panel stacks one section per
  ProviderKit. Each module keeps its own mode control; "Off" per module, no
  global mode (BLE passthrough + camera mock is a legitimate combination).
- Info.plist/entitlements are the union of the module requirements
  (`NSBluetoothAlwaysUsageDescription`, `NSCameraUsageDescription`,
  `com.apple.security.device.bluetooth`, `com.apple.security.device.camera`).
- Repo hygiene: `git clone --recursive` documented in README **and** a
  `make bootstrap` target running `git submodule update --init`; CI job fails
  if a submodule pin is not an ancestor of that product's `main` (stale-pin
  guard) or not on a release tag at release time.
- Nested `.build/` dirs inside submodules need ignore entries so `git status`
  in the umbrella stays quiet.
- Distribution: products keep their existing Homebrew formulae; Simsalabim
  gets its own formula/cask. A suite release = bump both submodule pins to
  tags, build, notarize, tag.

**Validate:** fresh `git clone --recursive` + `make mock` produces a working
suite app; both simulator SampleApps run against it simultaneously (BLE and
camera at once — the first genuinely new capability); standalone apps still
build unchanged from their own repos.

## 5. Wire-protocol reconciliation (the only behavior changes)

1. **Takeover semantics — unify on last-connection-wins.** Today ImpossiBLE
   rejects the *newcomer* with busy (and the newcomer stops reconnecting);
   CAMouflage evicts the *previous* client. CAMouflage's variant is the better
   DX — relaunching the app or switching simulators "just works" — and becomes
   the norm, implemented once in SimBridgeKit. ImpossiBLE must adopt the full
   eviction choreography: on takeover, tear down the old client's scans,
   connections, and L2CAP channels exactly as the existing
   provider-disconnect path does (`cbs_handle_daemon_disconnect` already
   handles the client side).
2. **`hello` handshake for ImpossiBLE.** Adopt CAMouflage's
   `hello {clientVersion, bundleId, pid}` as the first client message. The
   provider logs and surfaces version skew in the panel instead of silently
   ignoring unknown message types. Old clients that send no hello keep
   working (grace: treat first non-hello message as legacy).

Both changes ship in a minor ImpossiBLE release *before* the suite exists, so
skew diagnostics are in the field first.

## 6. Socket-ownership guard

With standalone apps *and* the suite app in the wild, two providers can fight
over the same socket; today the last one wins via `unlink`+`bind` and clients
silently bounce (ImpossiBLE's documented "single-instance lock" follow-up, one
level up). Implemented once in SimBridgeKit's server:

- Before binding: `connect()` to the existing socket path. If a listener
  answers, **refuse to start that module's provider** and surface it in the
  panel/log: "ImpossiBLE-Mac is already serving — quit it or use its
  section here." Only an unanswered (stale) socket file is unlinked.
- The suite app degrades per module: if only the BLE socket is taken, the
  camera section still runs.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Helper-to-in-process port destabilizes passthrough (threading: helper code assumed process-global queues) | Port the translation layer behind the responder seam first, keep the wire format frozen, validate against real hardware before deleting the helper build targets |
| Hardened-runtime Bluetooth entitlement missed → release-only passthrough failure | Entitlement added in Step 1 alongside the code move; `make mock-assess` in the release checklist |
| SimBridgeKit extraction drifts into a rewrite | One §3.2 row at a time, both products green after each move |
| Same-identity conflict SimBridgeKit (URL) vs local checkout | Never a submodule+path dep in the umbrella; co-dev via `swift package edit` only |
| Stale submodule pins ship a suite with known-fixed bugs | CI ancestor/tag check (Step 4); pins bumped only to tags at release |
| Version skew across 3 apps × 2 libraries | §5.2 hello handshake, shipped before the suite |

## 8. Explicitly out of scope (tracked, not planned)

- Unified cross-module test-fixture API (one `SetMockConfiguration` for the
  whole simulated environment) — wants SimBridgeKit to exist first.
- Shared simulator-side connection core (constraint 4 note in §3.2).
- New modules (ExternalAccessory, CoreNFC, CoreMotion, …) — each starts as a
  product repo following the post-Step-3 template.
- **Consolidated Simsalabim Showcase iOS app.** Add a developer-facing iOS
  app to this repository that exercises every provider end to end in one
  booted Simulator. It is an integration harness and product showcase, not a
  replacement for the focused sample apps in the product repositories; those
  must remain independently buildable and useful when developing a provider
  outside the suite.

  **Dependency and target shape:**

  - The app lives in Simsalabim and preserves the downward dependency rule.
    It links the existing `SimsalabimClient` umbrella to activate the
    ImpossiBLE, CAMouflage, and NFCromancer simulator bridges. No product or
    SimBridgeKit target may depend back on the showcase.
  - Add `SimulacrumClientKit` separately for the optional live Health channel.
    Store-backed Contacts, Calendar, Reminders, Photos, Health samples, and
    workouts remain host-seeded by Simulacrum; they must not be duplicated as
    in-app fixtures or replaced with private database writes.
  - Make the iOS app a first-class generated target (prefer XcodeGen, matching
    Simulacrum's entitled SeedAgent) with committed source configuration and
    discoverable root `make showcase-build`, `showcase-run`, and
    `showcase-test` entry points. Do not commit a generated `.xcodeproj` when
    `project.yml` is the source of truth.
  - The target owns the union of the required iOS usage descriptions and
    capabilities, including camera, Bluetooth, NFC, and HealthKit. Keep real
    device builds possible: simulator bridge packages already become no-ops
    there, and showcase-only diagnostics should be gated without changing the
    providers' public runtime behavior.

  **Showcase surfaces:**

  - A landing screen reports the connection/readiness of every provider and
    clearly distinguishes host mode (Off/Mock/Passthrough), authorization,
    socket ownership/blocking, and last activity. Provider modes remain
    independently controlled by the Mac suite; the iOS app must not invent a
    global mode.
  - BLE demonstrates scan, connect/disconnect, service and characteristic
    discovery, read/write, notifications, and the mock L2CAP handler where the
    configured fixture supports it.
  - Camera demonstrates authorization, capture-session lifecycle, live
    preview, camera switching when available, and still capture so mock and
    passthrough frames travel through the same AVFoundation path an app uses.
  - NFC demonstrates session lifecycle, cancellation/error states, and reading
    the configured mock or passthrough tag through CoreNFC rather than through
    a provider-specific shortcut.
  - Simulacrum shows representative Contacts, Calendar, Reminders, and Photos
    queries from their public frameworks; Health shows authorization state,
    historical samples, workouts, and observed live heart rate. Fall events
    arrive through `SimulacrumClientKit` and are explicitly labelled simulated
    semantic events rather than HealthKit/Core Motion records.

  **Authorization and automation:**

  - Do not swizzle or forge Health authorization. HealthKit's store and consent
    UI are system-owned; a process-local fake would hide integration failures
    and would not authorize real reads. Request the exact read types used by
    the showcase and expose a useful not-authorized state in the UI.
  - Reuse the proven semantic XCUITest approach from Simulacrum for development
    setup: locate the Health sheet's named "Turn On All"/"Select All" and
    "Allow" controls, never coordinate-tap the Simulator. Tests must also pass
    deterministically when a simulator has already granted access.
  - Give every interactive control and observable result a stable accessibility
    identifier. UI tests should select provider modes through the suite's
    control surface or a supported test setup path, then exercise the real iOS
    framework APIs and assert visible results.

  **Definition of done:** a fresh recursive clone can build and launch the Mac
  suite plus the showcase through documented `make` targets; a booted supported
  Simulator can demonstrate all four products without editing the showcase's
  source; mock-mode UI tests cover one representative success and failure path
  per provider; live Health playback and its optional fall event can be started
  and stopped cleanly; standalone provider sample apps still build; and no test
  leaves an active capture session, scan, NFC session, workout, client socket,
  or temporary simulator behind.
