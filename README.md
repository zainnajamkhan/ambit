# Ambit

A Mac app that records what you actually worked on without you touching it, keeps every
byte of it on your machine, and costs one payment instead of a hundred dollars a year.

It watches which application is in front and what its window is called, all day, and turns
that into "eighteen hours for this client" without you having remembered anything. Rules
map activity to projects, and rules run backwards, so one written today fixes last month.

**Status: S0, spikes. Not usable yet.** See [KNOWLEDGE-BASE.md](KNOWLEDGE-BASE.md).

## Why it exists

Timing costs $108 to $192 a year. Rize costs $120 to $290. RescueTime costs $84. All three
are subscriptions for software whose core loop needs no server, and all three upload your
activity history to do it.

That history is window titles: client names, document names, ticket numbers, private
message subjects. Ambit ships with **no network entitlement at all**, so the operating
system refuses to open an outbound connection no matter what the code does. That is a claim
no competitor with a backend can copy, and it is checkable:

```bash
codesign -d --entitlements - /Applications/Ambit.app
```

## Getting started

```bash
./Tools/test.sh                 # build, test, lint. 14 tests.
./Tools/make-app.sh             # wrap the spike in a signed .app bundle
open build/ambit-spike-ax.app   # run it
tail -f ~/Library/Logs/Ambit/spike-ax.log
pkill -INT -f ambit-spike-ax    # stop, and print the folded timeline
```

**Launch with `open`, never the bare binary.** A binary started from a shell inherits the
Terminal's Accessibility permission, so it will look like it works and prove nothing.

## Layout

```
Sources/AmbitCore/       pure logic: the event model and the timeline fold. No frameworks.
Sources/AmbitCapture/    the system edge: Accessibility, NSWorkspace, CGEventSource.
Sources/ambit-spike-ax/  spike 1 runner
Tests/AmbitCoreTests/    tests, all against the pure fold
Tools/                   test.sh, make-app.sh
```

`AmbitCore` takes every input as an argument and reads no clock, so the entire history can
be replayed whenever a rule changes. That is what makes retroactive categorisation possible
rather than a migration, and it is the reason the split is enforced rather than preferred.

## Not goals

No team features, no manager view, ever. No invoicing, export CSV instead. No integrations
until buyers ask repeatedly. No iOS app. No AI summaries. **No screenshots of your screen,
ever.**

## Plan

`../mac-apps/02-tally.md`, written under the earlier working name. Portfolio context in
`../mac-apps/README.md`.
