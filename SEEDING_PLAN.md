# Simulacrum — a fourth Simsalabim module for seeding personal data

> **Status (2026-08-24): All six steps done.** Published at
> [github.com/mickeyl/Simulacrum](https://github.com/mickeyl/Simulacrum)
> (public, `master`) and wired into the Simsalabim suite as its fourth
> module (commit `4ea4050`). One click — in the standalone app or now the
> suite itself — seeds a booted simulator with real Contacts/Calendar/
> Reminders/Photos data, confirmed independently at every layer by querying
> the simulator's own data stores directly rather than trusting either
> app's self-report. One correction surfaced
> while implementing Step 2, folded into §3–§5 below:
> `SeedAgent` does **not** link `SimBridgeShell` — SimBridgeKit's manifest is
> macOS-only, so `SeedAgent` hand-rolls the `AF_UNIX`/NDJSON client instead,
> matching how NFCromancer's simulator-side shim (`NFRConnection.m`) is also
> hand-rolled BSD sockets, for the identical reason. "Simulacrum" is the
> final product name (wordplay on *simulate* + *a copy standing in for the
> real thing*, matching the family's illusion/magic theme — ImpossiBLE,
> CAMouflage, NFCromancer) — confirmed before publishing the GitHub repo.

## 1. Problem

A fresh iOS Simulator has an empty Contacts, Calendar, Reminders, and Photos
library. Any app that reads from `Contacts`/`EventKit`/`Photos` — which is
most apps with a "pick a contact", "add to calendar", or "attach a photo"
flow — starts from nothing every time a simulator is erased or newly created.
Today that means manually typing in fixture contacts/events by hand in the
Simulator UI before every test/screenshot session, which nobody does
consistently. This is a one-shot data-loading problem, not a live bridge —
structurally different from the other three modules, which intercept a
framework call *while the app under test runs* and forward it somewhere.
That difference drives most of the design below.

**Target UX: one click.** Click "Seed" and everything else is automatic —
find the booted simulator (ask only if more than one is booted), install and
launch the seed agent on it, hand it the fixture, and report what got
written. No manual UDID lookup, no path fiddling, no separate install step
exposed to the user.

## 2. Constraints (carried over from the suite's existing invariants)

1. Stays individually installable, like the other three products; the suite
   embeds it the same way, via a git submodule + `<Name>ProviderKit` path
   dependency.
2. **Dependency arrows only point downward** — this module must not be
   depended on by the suite's other modules or by SimBridgeKit.
3. No simulator-side library to link this time (see §3) — no `+load`
   swizzle, no simulator-side SPM product, nothing for the app under test to
   embed. That simplifies the iOS-side story to zero: the app under test
   needs no changes at all, unlike the other three.
4. Never touches the app-under-test's own data — only the simulator's shared
   system stores (Contacts/Calendar/Reminders) and Photos library, which are
   sandboxed per-simulator, not per-app.

## 3. Mechanism

**Device resolution** — `simctl list devices --json`, filtered to
`state == "Booted"`. Exactly one → use it, no prompt. Zero → panel shows
"No simulator booted." More than one → the panel asks which one (this is the
only module that needs to pick a target explicitly; the other three are
socket-passive and don't care which simulator connects).

**Photos** — `xcrun simctl addmedia <udid> <files…>` imports straight into
the simulator's Photos library from the host, no agent involved and no
permission grant needed (`addmedia` bypasses Photos' own consent flow). This
one is essentially free and runs as its own step alongside the agent flow
below, folded into the same combined result.

**Contacts / Calendar / Reminders** — no `simctl` equivalent exists for
these, and writing `AddressBook.sqlitedb`/`Calendar.sqlitedb` directly would
be exactly the undocumented-schema fragility this plan is trying to avoid.
Instead, a tiny bundled **seed agent** app runs *inside* the simulator and
writes through `CNContactStore`/`EKEventStore` (events and reminders both go
through EventKit, distinguished by entity type) — the same public frameworks
a real app would use, so it keeps working across iOS SDK bumps.

Getting the fixture *into* the agent and the result back *out* reuses the
family's existing shape rather than inventing a new one: **the seed agent is
a socket client, exactly like the shims in ImpossiBLE/CAMouflage/NFCromancer
— just a dedicated small app instead of a swizzle embedded in the app under
test.** The host runs `SeedServer`, binding `/tmp/simulacrum.sock` the same
way `TagServer` binds `/tmp/nfcromancer.sock`; the agent dials that socket on
launch (Simulator processes share the host's `/tmp`/Unix-socket namespace,
which is exactly why the existing shims can do this too — **confirmed
empirically in Step 2**), sends `hello`, and waits for a `seed` command
carrying the fixture over an NDJSON envelope matching `ProtocolServer`'s
framing. The agent writes each record, streaming a `progress` message per
record so the panel can show live counts, then a final `result` message
(counts + per-record errors) before exiting. No file drop, no container-path
lookup, no polling with a timeout.

One correction from the original draft: **the agent side does not link
SimBridgeKit.** SimBridgeKit's manifest declares `platforms: [.macOS("15.0")]`
only — it's not buildable for an iOS Simulator destination at all, so
`SeedAgent` hand-rolls the `AF_UNIX`/NDJSON client directly (see
`SeedSocketClient.swift` in the Simulacrum repo), the same way NFCromancer's
simulator-side shim (`NFRConnection.m`) hand-rolls BSD sockets rather than
linking a shared client library. `SeedServer` (the host side) still uses
SimBridgeServer normally — only the agent-side "reuse SimBridgeKit's
transport" idea was wrong; the *wire format* (NDJSON, `hello` shape) is still
shared by hand-matching what `ProtocolServer` expects, just not through a
linked dependency. The socket-ownership guard is still SimBridgeServer's, on
the host side, so it still applies unmodified: standalone `Simulacrum-Mac.app`
and the suite can't both bind the socket at once, same as the other three.

**One-click sequence**, triggered by a single "Seed" click:
1. Resolve the target simulator (prompt only if ambiguous).
2. `simctl privacy grant all <bundle-id> <udid>` — pre-grant Contacts/
   Calendar/Reminders access so no interactive TCC prompt appears. (Verify
   in Step 2 below whether Contacts and EventKit need separate grant calls —
   they're distinct TCC services even though Reminders shares `EKEventStore`
   with Calendar.)
3. `simctl install <udid> SeedAgent.app` (a prebuilt bundle shipped as a host
   resource, like the module icons the suite already bundles) followed by
   `simctl launch <udid> <bundle-id>`.
4. Agent connects to `/tmp/simulacrum.sock`, host pushes the fixture, agent
   streams progress, host receives the final result.
5. Host runs `simctl terminate <udid> <bundle-id>` once `result` arrives —
   explicit termination instead of relying on the agent's own `exit(0)`,
   since simulator apps that just exit can still linger in the app switcher.
6. Panel shows the combined result (agent counts + `addmedia` photo count).

## 4. Target architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Simsalabim.app                                               │
│   SimulacrumSection: device picker (auto, asks only if >1    │
│   booted), fixture editor, "Seed" action, last-result line   │
│   ("✓ 12 contacts · 6 events · 3 reminders · 8 photos")       │
├─────────────────────────────────────────────────────────────┤
│ Modules/Simulacrum  (new product repo, git submodule)        │
│   Sources/Simulacrum-Mac/ProviderKit/                        │
│     Fixture (Codable: contacts/events/reminders/photo refs)  │
│     FixtureStore (JSON persistence, mirrors NFCromancer's    │
│       TagStore)                                              │
│     SeedServer (binds /tmp/simulacrum.sock via               │
│       SimBridgeServer, same shape as TagServer)              │
│     SeedRunner (simctl orchestration: resolve device →       │
│       privacy grant → install → launch → drive SeedServer    │
│       session → simctl terminate)                            │
│     SimulacrumSection (SwiftUI: device picker + fixture       │
│       editor, modeled on NFCromancer's MockTagEditor)        │
│   Sources/SeedAgent/  (separate executable target, cross-      │
│     compiled for the iOS Simulator SDK via plain `swift        │
│     build --sdk … --triple …`, no Xcode project; installed     │
│     onto the sim via `simctl install`, never runs on the Mac) │
│     SeedSocketClient.swift: hand-rolled AF_UNIX/NDJSON client  │
│     main.swift: dial /tmp/simulacrum.sock → hello → (Step 3:   │
│       receive `seed` → CNContactStore/EKEventStore writes,    │
│       streaming `progress` → `result`)                        │
├─────────────────────────────────────────────────────────────┤
│ Host side depends on SimBridgeKit as usual (SimBridgeServer,  │
│ menu bar chrome) — SimBridgeKit is macOS-only, so the agent    │
│ side does NOT link it; it hand-rolls the socket client         │
│ instead (see the note in §3). Still no simulator-side library  │
│ for the app under test to link — the seed agent is a           │
│ standalone installed app, not something the tested app embeds. │
└─────────────────────────────────────────────────────────────┘
```

## 5. Package boundaries

- **New repo**, `Simulacrum`, same shape as the other three: standalone
  `Simulacrum-Mac.app` + `SimulacrumProviderKit` library product consumed by
  Simsalabim via `Modules/Simulacrum/Sources/Simulacrum-Mac`.
- **`SeedAgent` is a second executable target in the same repo**, cross-
  compiled for the iOS Simulator SDK (not macOS) and NOT linking
  SimBridgeKit — its manifest is macOS-only, so the agent hand-rolls its
  `AF_UNIX`/NDJSON client (`SeedSocketClient.swift`) instead, matching
  NFCromancer's `NFRConnection.m` precedent. It ships embedded in the host
  app's Resources (a prebuilt, ad-hoc-signed `.app` bundle, like a fixture
  asset) and gets `simctl install`ed on demand — it is not something the
  app-under-test links, so it stays out of the app-under-test's dependency
  graph entirely.
- `SimulacrumProviderKit` has no `ProviderMode`/`ModeTransitionController`
  — there's no Off/Mock/Passthrough here, just a fixture + an action + a
  result. The panel section should still fit the existing collapse/splitter
  chrome (AGENTS.md's "every boundary between adjacent expanded modules
  gets a drag splitter"), just without a mode picker.

## 6. Steps

1. ✅ **Done.** Scaffold the `Simulacrum` repo (README/AGENTS/PLAN/LICENSE/
   Makefile, following the other three's layout) with the `Simulacrum-Mac`
   package and standalone app shell — no functionality yet, just the menu
   bar chrome and a `SeedServer` that binds `/tmp/simulacrum.sock` via
   `SimBridgeServer` (mirrors `TagServer`'s setup). Commit `115c7a8` in
   `~/Documents/late/Simulacrum`.
2. ✅ **Done.** Build `SeedAgent`: minimal iOS-Simulator-platform executable
   (cross-compiled via plain `swift build`, no Xcode project; hand-rolled
   socket client, not SimBridgeShell — see §3/§5), dials the socket,
   completes `hello`. Verified end-to-end against the real `SeedServer`:
   `simctl install`/`simctl launch` on a booted simulator produced a `hello`
   the host actually received and parsed, confirmed via a new
   `onClientConnected` log line matching the launched process's PID.
   Commit `f9f9714`.
3. ✅ **Done.** Add the `seed`/`progress`/`result` message types and the
   `CNContactStore`/`EKEventStore` write loop in the agent. Verified
   end-to-end (`make agent-run`): agent connects, receives a canned `seed`
   fixture, writes 2 contacts + 1 event + 1 reminder with read-back
   verification per record, streams `progress`, and `SeedServer` logs the
   real final counts. Two things found empirically, not assumed:
   - `simctl privacy grant all <bundle-id> <udid>` does **not** reliably
     suppress the Contacts/Calendar/Reminders gate — confirmed against a
     full `simctl privacy reset all`. Granting each service by name
     (`contacts`/`calendar`/`reminders`) works every time; the answer to
     this step's stated open question is "yes, they need separate grants."
   - A bare `main.swift` never pumps the main run loop, so a semaphore-wait
     for `CNContactStore`/`EKEventStore`'s permission completion handler
     deadlocked forever until the work moved to a background queue with
     `RunLoop.main.run()` on the main thread.
   Info.plist needs `NSContactsUsageDescription`,
   `NSCalendarsFullAccessUsageDescription`,
   `NSRemindersFullAccessUsageDescription` (full-access, not write-only,
   since read-back verification needs read access). Commit `9a64c98`. Wire
   schema (for Step 4 to build `Fixture`/`FixtureStore` against): `seed`
   carries `contacts: [{givenName, familyName, phoneNumbers: [String],
   emails: [String]}]`, `events: [{title, startDate, endDate, notes}]`
   (ISO8601), `reminders: [{title, dueDate?, notes}]`; `progress` carries
   `{category, index, total}`; `result` carries `{counts: {contacts,
   events, reminders}, errors: [{category, index, message}]}`.
   `SeedServer`'s temporary `sendTestSeed()` dev hook (fires the canned
   fixture on every connect) should be removed once `SeedRunner` exists.
4. ✅ **Done.** Add `Fixture`/`FixtureStore` (mirroring NFCromancer's
   `MockTag`/`TagStore`) and `SeedRunner` (the one-click orchestration:
   resolve device → privacy grant → install → launch → drive the
   `SeedServer` session → `simctl terminate` → fold in the `addmedia` photo
   result). Stock fixture ships obviously-fake data (`555` phone numbers,
   `@example.com` emails, three flat-color placeholder PNGs — no real-
   looking PII, no AI-generated faces). `SeedAgent.app` now gets built,
   ad-hoc signed, and copied into the host bundle's `Resources/` as part of
   the normal build (`make mac`/`make mac-debug` → `bundle-agent` target) —
   one build produces a host app that can seed on its own.
5. ✅ **Done.** Build `SimulacrumSection`: device picker (auto when one
   simulator's booted, a real picker otherwise), a working fixture editor
   (add/delete per category), "Seed" button, live result line.
   **Verified for real, twice** — once by the implementing pass and once
   independently in a follow-up session: launched the actual built app,
   clicked the real "Seed" button (via accessibility-tree targeting, not
   guessed coordinates — worth remembering if driving this UI again: the
   panel has no `AXTitle`s, buttons must be found by position/order, and
   "Quit Simulacrum" sits right next to "Seed" at a similar height, easy to
   mis-click), watched the panel's result line read
   `✓ 2 contacts · 1 events · 2 reminders · 3 photos`, then independently
   confirmed outside the app entirely — `sqlite3` against the simulator's
   own `AddressBook.sqlitedb` turned up `Ada|Testworth` and
   `Grace|Fixtureham` for real. Commit `1dd285a`.
6. ✅ **Done.** Wire into Simsalabim per AGENTS.md's "Adding a module"
   checklist: submodule add (pinned to `1dd285a`), `Package.swift` path
   dependency, `SeedServer` started directly in `SuiteRuntime.init()` (no
   mode controller — there's nothing to control), a fixed-height tail
   pane in `SuitePanelContent` after NFCromancer's (same precedent
   NFCromancer itself set — no new splitter), no composite-icon or
   client-row contribution (no ongoing on/off state or connection to
   represent there), `Makefile`'s `bundle-agent` step cross-compiling
   `SeedAgent` from the submodule into the suite bundle. No entitlement
   changes needed — confirmed, not assumed. **Verified in the actual
   running suite app**: clicked "Seed" in `Simsalabim.app`'s own panel
   against a booted simulator, confirmed via `sqlite3` against the
   simulator's `AddressBook.sqlitedb` that the fixture data really landed;
   confirmed the other three modules still render and their mode pickers
   still work, unaffected by the addition. Commit `4ea4050`.

All six steps are done. Simulacrum is a fully working fourth Simsalabim
module: a git submodule, published, and wired into the suite panel with
the one-click Contacts/Calendar/Reminders/Photos seeding flow verified at
every layer — standalone app, and now the suite itself.

## 7. Risks

| Risk | Mitigation |
|---|---|
| ~~`simctl privacy grant` doesn't cover every TCC service~~ | **Resolved in Step 3**: confirmed — `grant all` is unreliable, `grant contacts`/`calendar`/`reminders` individually works every time |
| ~~Agent launches but never connects~~ | **Resolved in Step 2**: confirmed working, `hello` received by the real `SeedServer` |
| Agent crashes or hangs mid-write, connection drops before `result` arrives | Host-side timeout on the session; report whatever `progress` messages arrived before the drop instead of an all-or-nothing failure |
| Multiple booted simulators, no explicit target picked | Device picker required in Step 5, not optional — never silently default to "first in the list" when more than one is booted |
| ~~`SeedAgent.app` needs its own code signing~~ | **Resolved in Step 2**: it does — ad-hoc `codesign --sign -` is required even for simulator installs on this Xcode/iOS version, confirmed empirically |
| Fixture data (names, emails, photos) accidentally looks like real PII if someone reuses real contact exports | Ship only clearly-fake stock data (like NFCromancer's stock mock tags); document that user-supplied fixtures are the user's own responsibility |

## 8. Explicitly out of scope

- **Clearing/resetting seeded data.** First cut is additive only (re-running
  Seed on top of existing data). A "Clear" action that deletes only
  records the agent created (tracked by a marker field, e.g. a note/UID
  prefix) is a natural follow-up once the additive path is proven.
- **Photos beyond `simctl addmedia`'s files-on-disk model** (albums,
  favorites, metadata like location/date) — `addmedia` is a flat import;
  richer Photos fixtures would need the same agent-app approach as
  Contacts/Calendar, which is more work than the common case justifies.
- **Watching for simulator boot/erase and auto-seeding.** First cut is
  manual ("Seed" button); auto-seed-on-first-boot is a nice follow-up once
  the manual path is validated.
- **Any change to the app under test.** Confirmed as unnecessary by the
  mechanism in §3 — worth stating explicitly since all three existing
  modules require a library link; this one deliberately doesn't.
