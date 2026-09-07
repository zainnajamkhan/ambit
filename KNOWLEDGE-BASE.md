# Ambit: knowledge base

Everything needed to pick this project back up cold, plus the platform facts that were
expensive to learn.

Last updated 8 September 2026. State: **S1, S2, S3 and S5 built. The app runs, records and
shows a day and a week. No settings window yet, so projects and rules can only be created
by editing JSON by hand. Product decisions waiting in `DECISIONS.md`.**

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
    WindowTitleNormalizer  strips titles that change on their own
    ExclusionPolicy.swift  what must never be written down
    Project.swift          projects and the closed colour palette
    RuleSet.swift          ordered rules, first match wins
    Summary.swift          totals per project, and the unsorted list
    Export.swift           CSV and JSON, RFC 4180 escaped
  AmbitStore/              SQLite through GRDB. Append and read only. Swift 6 mode.
    EventStore.swift       the protocol, so nothing above knows about SQLite
    SQLiteEventStore.swift flat columns, not a serialised blob, so the file stays readable
  AmbitCapture/            the system edge. Swift 5 language mode, see section 5.
    AccessibilityAuthorization.swift
    FocusWatcher.swift     NSWorkspace + AXObserver
    IdleMonitor.swift      CGEventSource
  AmbitApp/                SwiftUI. Menu bar, day timeline, week summary, export.
  ambit-spike-ax/          spike 1 runner
Tests/                     60 tests across the core and the store
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
3. **Every application switch produced a throwaway titleless block.** `attach` emitted on
   the application name alone *before* trying to read the title, so each switch wrote a
   junk block a few milliseconds ahead of the real one. The reasoning behind that emit was
   sound (an install with no Accessibility should still record something) but the placement
   was not: it now fires only when a title is genuinely unavailable. A short session went
   from 8 events and 5 blocks to 6 events and 3 blocks.

4. **Quitting while idle silently discarded the next session.** `.stopped` closed the open
   segment but left the state machine set to `idle`. Every `focused` event in the next run
   then took the "note it but open nothing" branch, forever. A full day of work after a
   restart folded to nothing.
5. **Reopening in the same application lost everything until the first app switch.** Same
   root cause, second symptom: `.stopped` also had to forget what was frontmost. Held on
   to, the first focus event of the new session matched the last one of the old session and
   was deduplicated away. Quit in Xcode, come back in Xcode, and the hours until you next
   switched applications recorded as nothing.

Neither of the last two could exist before this week, because until the store was written
a log could not span two runs of the app. On the real database that had accumulated during
testing, fixing them took the same 14 events from 5 blocks to 8, and tripled the recorded
active time.

This is the argument for section 1 of the skill in one paragraph. Fourteen passing tests
said nothing about the first two, and fifty six said nothing about the next two. Every one
of them was found by running the thing and reading the output.

---

## 7a. Bugs the interface found by being launched

The pattern held all the way through. Every one of these passed its tests first.

6. **The app recorded nothing at all.** Capture was started from the day view's `.task`, and
   Ambit is a menu bar app with no Dock icon whose window may never be opened. It sat at
   zero per cent processor doing nothing until someone happened to open a window. Long lived
   objects now live outside the view tree and start from the application delegate, which
   also means quitting from anywhere closes the open block rather than only the menu item
   doing so.
7. **Health was only ever written on failure.** After the user granted Accessibility and
   titles started flowing, the state stayed on "waiting for permission" for the rest of the
   run, so the interface would have gone on asking for something it already had.
8. **The lock monitor assumed the user was present at startup.** The notifications only
   announce changes. Ambit is meant to launch at login and at login the screen is often
   still locked, so every morning began by recording the lock screen as work. It now asks
   `CGSessionCopyCurrentDictionary` where it actually is before listening for changes.

## 7b. The app has its own TCC identity

`com.zainnajamkhan.ambit` and `com.zainnajamkhan.ambit.spike` are different applications as
far as the permission system is concerned. Granting Accessibility to one does nothing for
the other. Expect to grant it again for each new bundle identifier, including whatever the
final shipping one turns out to be.

## 8. Open questions and findings to act on

- **Screen lock is recorded as work.** When the screen locks, `loginwindow` becomes the
  frontmost application and Ambit currently logs it as an active block. The plan does not
  mention this at all. Screen lock has to count as away. Watch for
  `com.apple.screenIsLocked` on the distributed notification centre.
- **The permission dialog records itself.** `universalAccessAuthWarn` is the TCC prompt
  process and it shows up as a focus event. System permission dialogs need excluding, and
  the exclusion list is a shipping feature anyway.
- **Window titles carry volatile noise. Handled, and it keeps turning up.** Three
  self-changing titles were found within ten minutes of running the capture engine on a
  real machine:

  | Application | Noise it writes into its own title |
  |---|---|
  | Chrome | a live memory figure, an unread count, the profile name |
  | Terminal | the window's dimensions, so a resize looks like new work |
  | VS Code and friends | an unsaved-changes dot that toggles on every keystroke |

  `WindowTitleNormalizer` in `AmbitCore` strips these. It is a pure function, so the rules
  are testable against real strings and can be improved later.

  **Both titles are stored.** `FocusTarget` carries the cleaned title and the raw one.
  `==` is written by hand and **deliberately ignores the raw title**, which is the entire
  mechanism preventing noise from splitting blocks. Deleting that operator in favour of the
  synthesised one silently restores the bug, so it is commented accordingly.

  Cleaning happens *before* the comparison that decides whether to record an event, so the
  store never fills with noise. The cost is that observations today's rules consider pure
  noise are never written, so a future improvement to the rules can only be replayed over
  what was kept. That is the right trade: the discarded rows are the ones with no
  information in them.

  Expect to keep adding rules here. Every application invents its own noise.

- **Idle threshold.** Currently 60s in the spike, 120s default in `IdleMonitor`. The plan
  says test this on real data before committing.
- **Idle ends up to one poll interval late.** `IdleMonitor` polls every five seconds, so a
  block boundary can be that far out. Harmless for billing at hour granularity, worth
  revisiting if the day view ever shows seconds.
- **Focus changes during idle keep the time attributed to the older application.** Correct
  when an application steals focus while the user is away. In normal use a switch requires
  input, which ends idle on the next poll, so this is rarely visible.
- **Prompt on return, or silently mark idle?** Unresolved. Test during S1.
- **The store is written**, GRDB 7.11.1, at
  `~/Library/Application Support/Ambit/ambit.sqlite`. Two things still owed on it: it moves
  into the App Group container once sandboxed, because the Safari extension's handler has
  to write into the same log, and it is not encrypted yet (S7, key in the Keychain).
- **Writes are one row at a time on the main thread.** Fine at a handful of events a
  minute, and it means a crash loses at most the event in flight. Batch on quit and on
  sleep if the volume ever justifies it.

---

## 9. Sequencing note

The portfolio plan says Ambit starts only once Quiet is on the store with its rule loop
running unattended. **That condition is not met**: Quiet is feature complete and unshipped,
blocked on the $99 membership. Work here is deliberately ahead of that gate, and the
membership remains the highest leverage purchase in the whole portfolio.
