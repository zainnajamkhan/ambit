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

**Editing the timeline.** The plan's S2 includes manual editing, splitting and merging
blocks. Not built. The architecture is ready for it: a correction appends a correcting
event rather than mutating a row, so the original observation survives. What is undecided
is the interaction. Drag block edges directly on the timeline, or a small inspector panel?
Direct manipulation is nicer and considerably more work.

**Idle on return: prompt or stay quiet.** Section 15 of the plan leaves this open and says
to test it on yourself during S1. Right now idle gaps are recorded silently. Prompting is
more accurate and more annoying, and the honest answer comes from you running it for a
fortnight, not from me picking.

**What the free tier is.** The plan says $39 one time with a fourteen day trial. It does
not say whether there is a permanently free tier, which the portfolio README says all three
apps should have for App Store discovery. Those two documents disagree.

**The app icon.** Nothing exists. Note from Quiet's knowledge base: the SF Symbols licence
forbids using SF Symbols in an app icon, so it has to be drawn. The menu bar icon is a
symbol, which is allowed.

---

## 3. What is not built yet

Ranked by what stands between here and something you could run for a fortnight.

1. **A settings window. This is the biggest gap.** Projects, rules and exclusions all work
   and are all tested, and there is no way to create any of them except by editing
   `~/Library/Application Support/Ambit/settings.json` by hand. The engine is done; the
   surface is missing.
2. **Timeline editing**, per the open question above.
3. **Onboarding**, including the Accessibility permission walkthrough. The plan calls this
   out as where the category loses users, and the menu bar currently shows a bare warning
   with two buttons.
4. **The Safari extension** (S4). Lower risk than the plan assumed; Quiet already proves the
   pipeline. `FocusTarget.url` and the URL rule types are in place waiting for it.
5. **Sandboxing and the App Group move.** The store is at
   `~/Library/Application Support/Ambit/`; sandboxed it has to move into the App Group
   container so the extension's handler can write to the same log.
6. **Encryption at rest** (S7), key in the Keychain.
7. **Launch at login** via `SMAppService`.
8. **App icon, store assets, comparison pages.**

---

## 4. One thing to do when you sit down

The app has its own bundle identity, separate from the spike, so **it needs its own
Accessibility grant**. Until you give it one, Ambit records which applications you use but
no window titles. Open the menu bar item and it will say so, with a button.

```
open ~/Desktop/Non-Work/ambit/build/Ambit.app
```

Then look at it and tell me what is wrong with it. I built the whole interface without ever
seeing it render, because your screen was locked all night. Every layout decision in there
is unverified.
