# Ambit

Automatic time tracker for macOS. Records what you worked on without being told, keeps
every byte on the machine, and costs one payment instead of a subscription.

App 2 of the three app portfolio. Plan: `../mac-apps/02-tally.md` (written under the old
working name Tally). Portfolio: `../mac-apps/README.md`. Findings: `KNOWLEDGE-BASE.md`.

## How we work

The skill `build-macos-apps` governs this project. It is installed at
`~/.claude/skills/build-macos-apps/SKILL.md`. Invoke it for any lifecycle task. The
principles below are the parts that apply on every single turn, restated here because a
skill body only loads when it is invoked.

**The user is the product owner. Claude is the developer.** The user describes what they
want and judges whether the result is acceptable. Claude implements, verifies, reports.

1. **Prove, don't promise.** Never say "this should work". Run `./Tools/test.sh`. Build
   the app, launch it, read the log. If you did not run it, you do not know it works.
2. **Tests for correctness, eyes for quality.** Logic gets a test. Anything visual gets
   launched and looked at by the user.
3. **Report outcomes, not code.** "Fixed the truncated timeline; the dump now survives
   exit" beats "refactored the logging queue".
4. **Small steps, always verified.** Change, verify, report, next. Never batch.
5. **Ask before, not after.** Unclear requirement, several valid approaches, or a big
   refactor: ask first.
6. **Always leave it working.** Every stopping point has tests passing and the app
   launching.

**Claude runs the builds on this project.** This overrides the standing
`user-builds-not-claude` preference, which is scoped to the day-job repositories.

**There is an Xcode project, and it overrides the skill's "CLI-only, no Xcode" rule.**
`swift build` and `Tools/test.sh` stay the fast loop, but `Ambit.xcodeproj` is what carries
the entitlements, the signing and the archive, and it is the only way to debug in Xcode.
Entitlements are the product here, so they cannot live outside a real target.

## Commands

```bash
open Ambit.xcodeproj            # debug and run in Xcode (scheme "Ambit", shared)
./Tools/test.sh                 # build, test, lint. The one command.
./Tools/make-app.sh             # wrap the spike in a signed .app bundle
open build/ambit-spike-ax.app   # run it (NEVER run the binary directly, see below)
tail -f ~/Library/Logs/Ambit/spike-ax.log
pkill -INT -f ambit-spike-ax    # stop it and print the folded timeline
```

## Rules that are easy to get wrong

- **Launch with `open`, never the bare binary.** A binary started from the shell inherits
  the Terminal's Accessibility grant. It will appear to work and prove nothing.
- **`AmbitCore` stays pure.** No system frameworks, no I/O, no clock reads. It takes its
  inputs as arguments so the whole history can be replayed cheaply. This is what makes
  retroactive rules possible and it is a real differentiator. Anything touching
  Accessibility, `NSWorkspace` or Core Graphics belongs in `AmbitCapture`.
- **Events are append only.** The timeline is derived by folding, never edited in place.
  A user correction appends a correcting event; it does not mutate a row.
- **No network entitlement, ever.** The product claim is that the app is structurally
  incapable of sending anything anywhere. Do not add a dependency that needs a socket.
- **Design from Apple's Human Interface Guidelines.** Native AppKit and SwiftUI idiom,
  no invented visual language.

## Style

Six line header on every file, matching Quiet:

```swift
//
//  FileName.swift
//  Ambit
//
//  Created by Zain Najam on 07/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//
```

Doc comments explain **why**, in full sentences, not what the code already says. No force
unwraps. Private outlets and stored properties unless something outside needs them.
