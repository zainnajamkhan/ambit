# Decisions waiting on you

Written 8 September 2026, overnight. Nothing here is urgent, and nothing here blocks the
app from running. Everything is a product call rather than an engineering one, so it was
left rather than guessed at.

---

## 1. Provisional calls I made to keep moving

These are implemented and reversible. Each took a decision, so each is listed rather than
buried in a commit message. Say the word on any of them and it changes.

| Decision | What I chose | The alternative |
|---|---|---|
| **Excluded time** | Counted, but stripped of everything identifying. The timeline shows "Excluded, 45m". | Drop it entirely, so the day has an unexplained hole in it. The plan's wording ("out of the database entirely") leans this way; I went the other way because a day that does not add up is a tracker people stop trusting, and nothing identifying is stored either way. |
| **Rule ordering** | Ordered list, first match wins, the user controls the order. | Score rules by specificity and pick the "best" one. Rejected because a tracker that silently reranks your rules is one you cannot predict or debug. |
| **Screen lock** | Its own state, separate from idle. | Fold it into idle. Kept separate because it is certain where idle is inferred, and because it means the app never asks "what was that gap?" about the night. |
| **Raw titles in export** | Withheld unless explicitly requested. | Always include. Withheld because the raw title is kept so the cleaning rules can improve, not so it can be mailed to an accountant. |
| **Project colours** | Closed palette of nine system colours. | Free colour picking. Closed because system colours stay legible in both appearances and under increased contrast, and because two projects cannot end up indistinguishable. |
| **Idle threshold** | 120 seconds default. | The plan says test this on real data before committing. It is in settings and easy to change. |
| **No Dock icon** | Menu bar only. | A regular app with a Dock icon. |

---

## 2. Open questions I did not answer

**Editing the timeline. Partly built, and a decision made for you to overrule.**

Reassigning a block is done: right click any block in the day view and send it to a project,
mark it not work, or hand it back to the rules. Corrections are appended, never edits, so
what Ambit observed and what you say about it stay separable, and rewriting a rule later
does not discard corrections made under the old one. Blocks you set by hand carry a small
marker so a correction reads as deliberate.

I chose a **context menu** over dragging block edges. Dragging is nicer and is the thing to
build once the interaction has been lived with; reassigning is the correction people
actually need and offering it now beat offering nothing. Say the word and it becomes direct
manipulation.

**Still not built:** splitting one block into two, and merging adjacent ones. Both need a
decision about what the split point means when the underlying observation says otherwise.

**Idle on return: prompt or stay quiet.** Section 15 of the plan leaves this open and says
to test it on yourself during S1. Right now idle gaps are recorded silently. Prompting is
more accurate and more annoying, and the honest answer comes from you running it for a
fortnight, not from me picking.

**~~What the free tier is.~~ Settled 8 September 2026: there is a permanent free tier.**

The line is **"where did my time go" is free, "which client do I bill" costs money.**

- **Free, forever:** capture, the day timeline, where the day went by application, and
  export. Genuinely useful on its own, builds the habit, and gives the App Store a free app
  to rank.
- **$39 once:** projects, rules, billable tracking, the week summary.

Export stays free on both, because `02-tally.md` says "no paywall on your own data" and that
principle is the same one as the no network claim. The wall is on the *organising*, never on
the data.

Not implemented yet. Licensing is S6 and needs `IndieKit` bringing over from Quiet. The
onboarding is built so the paywall drops in at the last step, which is exactly where someone
has just watched their own day sort itself and understands what they would be buying.

**The app icon.** Nothing exists. Note from Quiet's knowledge base: the SF Symbols licence
forbids using SF Symbols in an app icon, so it has to be drawn. The menu bar icon is a
symbol, which is allowed.

---

## 3. What is not built yet

Ranked by what stands between here and something you could run for a fortnight.

1. **Licensing and the free tier gate** (S6). The line is decided but nothing enforces it.
   Needs `IndieKit` bringing over from Quiet.
2. **The Safari extension** (S4). Lower risk than the plan assumed; Quiet already proves the
   pipeline. `FocusTarget.url` and the URL rule types are in place waiting for it.
3. **Sandboxing and the App Group move.** The store is at
   `~/Library/Application Support/Ambit/`; sandboxed it has to move into the App Group
   container so the extension's handler can write to the same log.
4. **Encryption at rest** (S7), key in the Keychain.
5. **Splitting and merging blocks**, per the open question above.
6. **App icon, store assets, comparison pages.**

---

## 4. One thing to do when you sit down

The app has its own bundle identity, separate from the spike, so **it needs its own
Accessibility grant**. Until you give it one, Ambit records which applications you use but
no window titles. Open the menu bar item and it will say so, with a button.

```
open ~/Desktop/Non-Work/ambit/build/Ambit.app
```

There is a **placeholder project** in your settings called "Ambit itself", with one rule, put
there so the interface has something in it when you first open it. Delete it in Settings and
make your own. Settings is reachable from the menu bar item, since there is no Dock icon.

Then look at it and tell me what is wrong with it. I built the whole interface without ever
seeing it render, because your screen was locked all night. Every layout decision in there
is unverified.
