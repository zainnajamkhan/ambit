# Ambit: knowledge base

Everything needed to pick this project back up cold, plus the platform facts that were
expensive to learn.

Last updated 8 September 2026. State: **S0 in progress. Spike 1 partially proven.**

Companion to `../quiet/KNOWLEDGE-BASE.md`, which holds the sandbox, App Group, Safari
extension, StoreKit and app lifecycle facts. Those are not repeated here. Read both.

---

## 1. What Ambit is

A Mac app that records what you actually worked on without you touching it, keeps every
byte of it on your machine, and costs one payment instead of a hundred dollars a year.

Aimed at freelancers, consultants and contractors who bill by time. Explicitly not at
teams, managers, or anyone monitoring someone else.

Full plan: `../mac-apps/02-tally.md`, written under the old working name.

---

## 2. The name

"Tally" was rejected by its own plan: it collides with accounting software. Ten candidates
were checked against the Mac App Store on 7 September 2026. **Nine were dead.**

| Candidate | Verdict |
|---|---|
| Tally | Accounting software, plus category collision |
| Ledger | Ledger SAS, major mark in crypto hardware |
| Cadence | Cadence Design Systems, major software mark |
| Trace | Generic and heavily contested |
| Passage | Generic, acquired by 1Password |
| Hours On | Awkward, and Hours exists |
| Daybook | Live Mac App Store app, plus several on iOS |
| Docket | Pocket Docket Time Tracker, Docket Work Simplified |
| Steno | Steno Notes on the store, plus stenovoice.app |
| Hindsight | Hindsight Time Tracker, exact category collision |
| Sundial | Sundial Mobile Punch (timekeeping), Screen Time Sessions |
| **Ambit** | **Clear.** No Mac App Store app, nothing in time tracking |

Residual risk on Ambit: a trademark held by Ambit Group LLC covering IT consulting
*services*, and an unrelated Indian ERP firm. Neither is consumer Mac software, which is
the class that matters for App Review and for the store display name.

Lesson for Redact: common English words in a crowded category are gone. Budget an hour
for name clearance and expect to burn most of a shortlist.

---

## 3. Layout

```
Package.swift              SwiftPM. No Xcode project yet; the skill mandates CLI only.
Sources/
  AmbitCore/               PURE. No frameworks, no I/O, no clock. Swift 6 language mode.
    ActivityEvent.swift    the append only event model
    Timeline.swift         the fold from events to blocks
  AmbitCapture/            the system edge. Swift 5 language mode, see section 5.
    AccessibilityAuthorization.swift
    FocusWatcher.swift     NSWorkspace + AXObserver
    IdleMonitor.swift      CGEventSource
  ambit-spike-ax/          spike 1 runner
Tests/AmbitCoreTests/      14 tests, all against the pure fold
Tools/
  test.sh                  build, test, lint. The one command.
  make-app.sh              wrap an executable in a signed .app bundle
```

---

## 4. Spike status

| Spike | State |
|---|---|
| 1. Accessibility plus window title observation | **Proven, except revocation.** Application switching, idle detection, window title reading, the event pipeline and the fold all verified on a real machine with the permission granted. Revocation handling is written and still untested. |
| 2. Native messaging, extension to sandboxed container app | **Not started.** Much lower risk than the plan assumed. Quiet already does exactly this, in the same direction, see section 6. |
| 3. Mac App Store review with no network entitlement | **Blocked** on the $99 membership. Not a code blocker: dropping an entitlement is a one line change at the end. Build as if it will pass. |

---

## 5. Platform facts that cost real time

### TCC judges the launcher, not the binary

**A binary run from a shell inherits the Terminal's Accessibility grant.** It will appear
to work perfectly and prove nothing. The spike must be a real `.app` bundle launched with
`open`, so that launchd is the responsible process and TCC judges the bundle on its own
signature. This is why `Tools/make-app.sh` exists.

### Ad hoc signing throws away the permission on every build

TCC keys the grant to the code directory hash. `codesign -s -` produces a new hash every
build, so every rebuild is a new stranger and Accessibility has to be granted again.

**A free personal team is enough to fix this.** An `Apple Development` certificate already
exists on this machine (team `TEAMID`) and gives a stable identity across rebuilds. No
paid membership needed. `make-app.sh` prefers it automatically and falls back to ad hoc
with a warning.

### Accessibility, beyond what Quiet already learned

Quiet's knowledge base covers the once per app prompt, the System Settings deep link, and
re checking on `didBecomeActive`. New here:

- **Only `AXError.apiDisabled` means the permission is gone.** Everything else is ordinary
  life: windows close, applications quit mid query, and plenty of processes expose no
  title at all. Treating those as permission failures puts a false warning in front of the
  user several times an hour.
- **`AXObserver` callbacks are bare C function pointers** and cannot capture context. Pass
  `self` through the refcon with `Unmanaged.passUnretained`. Retaining would be a cycle,
  because the watcher owns the observer.
- **The observer does not retry by itself.** One created while untrusted stays dead after
  the user grants permission. Poll the trust state and re attach explicitly.
- **`kAXFocusedWindowChangedNotification` and friends already import as `String`.** Writing
  `as String` in a switch is a no op the compiler warns about. `as CFString` when passing
  them back into the API is a real conversion and is still needed.
- **`CFTypeRef` does not bridge to `AXUIElement` through `as?`.** Check
  `CFGetTypeID(value) == AXUIElementGetTypeID()` first, then cast.
- **Idle detection needs no permission at all.** `CGEventSource.secondsSinceLastEventType`
  keeps working when Accessibility has been refused, so a degraded install still records
  something honest rather than nothing.

### Swift 6 language mode and Accessibility do not mix

`AmbitCore` is Swift 6 mode: it is all value types and trivially `Sendable`. `AmbitCapture`
is Swift 5 mode, because the C function pointer plus run loop plumbing around `AXObserver`
does not model cleanly under strict concurrency. Revisit once the capture engine settles;
do not fight it during a spike.

---

## 6. Spike 2 is smaller than the plan thinks

The plan treats native messaging as unproven risk. Quiet already ships it:
`Extension/Resources/background.js` calls `sendNativeMessage`, and
`Shared (Extension)/SafariWebExtensionHandler.swift` answers out of App Group storage.

Ambit needs the same pipe running the other way: the handler writes URL events into the
App Group container and the main app drains them. The plan's worry about "the app not
running when the browser starts" dissolves, because Safari launches the *app extension* on
demand and the main app is never in that path.

---

## 7. Bugs the spike found by being run

Both were invisible to the tests and would have shipped.

1. **The timeline dump was truncated on every run.** Log writes go through an async queue
   and `exit(0)` does not wait for it. The queue has to be drained explicitly.
2. **The starting health state was never reported.** `didSet` stays silent when the value
   has not changed, and the initial state usually equals the property's default. The result
   was that "I am running but I cannot see window titles", the single most important thing
   the app has to say on a fresh install, was never delivered to the interface.

This is the argument for section 1 of the skill in one paragraph. Fourteen passing tests
said nothing about either.

---

## 8. Open questions and findings to act on

- **Screen lock is recorded as work.** When the screen locks, `loginwindow` becomes the
  frontmost application and Ambit currently logs it as an active block. The plan does not
  mention this at all. Screen lock has to count as away. Watch for
  `com.apple.screenIsLocked` on the distributed notification centre.
- **The permission dialog records itself.** `universalAccessAuthWarn` is the TCC prompt
  process and it shows up as a focus event. System permission dialogs need excluding, and
  the exclusion list is a shipping feature anyway.
- **Window titles carry volatile noise that will shred the timeline.** The first real
  title captured was:

  ```
  ... | LinkedIn - High memory usage - 1.2 GB - Google Chrome - zain
  ```

  Chrome appends a live memory reading and the profile name to its window title. That
  figure changes on its own schedule, with no user action behind it, and every change looks
  to the capture engine like a new window and therefore a new block. Left alone this would
  split a single hour of browsing into dozens of fragments and make the day view unusable.

  Titles need normalising before they reach the event log: strip the trailing application
  name and profile, strip browser chrome such as memory warnings and unread counts, and
  collapse whitespace. This belongs in `AmbitCore` as a pure function so it is testable and
  so the raw title can still be kept alongside the cleaned one. It is also an argument for
  landing spike 2 early, because a URL from the Safari extension is a far more stable
  identity than a title string.

  Worth noting what else that line demonstrates: a single window title exposed a named
  company and what the user was reading about it. That is precisely the payload Timing,
  Rize and RescueTime upload, and the reason the no network entitlement is the product.

- **Idle threshold.** Currently 60s in the spike, 120s default in `IdleMonitor`. The plan
  says test this on real data before committing.
- **Prompt on return, or silently mark idle?** Unresolved. Test during S1.
- **The store.** Not written. Plan calls for SQLite through GRDB, since this is a time
  series with many small rows and a lot of range queries.

---

## 9. Sequencing note

The portfolio plan says Ambit starts only once Quiet is on the store with its rule loop
running unattended. **That condition is not met**: Quiet is feature complete and unshipped,
blocked on the $99 membership. Work here is deliberately ahead of that gate, and the
membership remains the highest leverage purchase in the whole portfolio.
