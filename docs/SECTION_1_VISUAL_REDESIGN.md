# Section 1 — Visual Redesign

- **Date:** 2026-07-28
- **Scope:** the Home identity card only. Visual hierarchy, typography, spacing.
- **Backend, Firestore, Cloud Functions:** untouched. Every value rendered was
  already available.
- **Nothing committed.**

---

## 1. Final layout

```
┌──────────────────────────────────────────────────────┐
│ IRON TEMPLE FITNESS ✓                                │  eyebrow · context
│                                                      │
│ (◕)  Ravi Kumar                        ┌──┐  ┌──┐    │  the coach · primary
│      Check your macros before Friday   │🔔②│  │💬③│   │  actions · 40px
│ ──────────────────────────────────────────────────── │
│ Active until 12 Dec 2026                             │  standing · rarely read
└──────────────────────────────────────────────────────┘
```

**Three rows, one idea each:** where I train · who trains me · where I stand.

---

## 2. Before → after

| | Before | After |
|---|---|---|
| Card height (populated) | 147 px | **≤ 136 px**, enforced by test |
| Org logo tile | 48 × 48 | **removed** |
| Org name | 14 px, primary weight | 10.5 px small caps eyebrow, muted |
| Coach name | 13.5 px | **15 px** |
| Coach avatar | 36 px | **40 px** |
| Secondary line | `COACH` (static caption) | **live conversation preview** |
| Message affordance | `[💬 Message]` pill | 40 px badged icon |
| Notification | 44 px bordered box on the org row | 40 px filled tile on the coach row |
| Membership | sub-line of the org identity | **its own row**, under a divider |
| Membership copy | "Membership ends in 142 days" | **"Active until 12 Dec 2026"** |
| Card padding | 12/11/11/11 | 14/13/12/11 |

**More information in less height.** The card gained a conversation preview and
a second badged action while losing 11 px.

---

## 3. Every decision

### 3.1 The organisation becomes an eyebrow · *the biggest win*

A 48 px logo tile with a 14 px name beside it was the visually heaviest element
in the card — given to the party the member interacts with **least**. A member
opens this app to reach a *person*. The gym is the context that relationship sits
inside, and context belongs in an eyebrow.

Removing the tile is the single largest space saving available *and* it corrects
the hierarchy. Small caps, letterspaced 1.1, muted: at 10.5 px lowercase would
read as a forgotten label rather than a deliberate one.

The verified badge is sized to the eyebrow's cap-height (12 px), not to a
comfortable icon size — **a badge larger than the text it qualifies outranks it.**

### 3.2 "Assigned Coach" — rejected

The brief proposed this subtitle and invited challenge. Three reasons it loses:

1. **"Assigned" describes an admin process, not a relationship.** The member does
   not care that their coach was *assigned*; they care that this is their coach.
2. **A static label never changes.** It occupies a line forever to say something
   the avatar and name already say.
3. **That line has a better job.** It now carries the live conversation preview
   — real, decision-useful information in the same pixels.

**The rule applied:** preview when a conversation exists; `Your coach` when it
does not, so the role is still stated on day one; `Tap to message` when the coach
is unnamed, because the *primary* line already says "Your coach" and printing it
twice in one row is the kind of detail that makes a card look unreviewed.

### 3.3 Both actions on the coach row

Vertically centred on the avatar — the row's optical anchor. Putting them on the
eyebrow would tie the two most-used controls in the app to the least-important
line.

**One builder for both icons** (`_actionIcon`), so they cannot drift in size,
radius, badge geometry or press feedback. Two hand-maintained near-copies is
exactly how a card starts looking assembled rather than designed.

**40 px drawn, 44 px tapped.** The tile is 40 to sit level with the avatar; the
`InkWell` is padded to the platform minimum. A 44 px chrome box would have
dominated the row.

The notification control also changed from a *bordered outline* to a *filled
surface* tile, matching the message icon. An outline reads as "secondary
action"; these are peers.

### 3.4 Badge geometry

- **Count, never a dot.** A dot says something happened; a number says whether
  this is a ten-second read or a real conversation.
- **`99+` cap** so a neglected thread cannot widen the row.
- **Tabular figures** so the row does not reflow as `9` becomes `10`.
- **A 1.5 px ring in the card colour**, so the badge floats above the tile
  instead of merging with its corner.
- **Entry animation only** — 180 ms `easeOutBack`, keyed on the value so it
  replays only when the count actually changes. **No exit animation**: that would
  pull the eye back to something the member has just dealt with.

### 3.5 Membership — a date, not a countdown

Evaluated all five candidates. **`Active until 12 Dec 2026` wins**, with one
exception.

- *"142 days remaining"* / *"142 days left"* — a countdown re-states the same
  non-news every morning and manufactures urgency 142 days early.
- *"Membership • 142 days remaining"* — spends the strongest word position on a
  noun the member already knows.
- *"Active until 12 Dec 2026"* — a **calm fact to plan around**. It is what Apple,
  Whoop and every premium subscription surface state. It is also *shorter* in the
  common case.

**But the register switches by proximity**, because the information need genuinely
changes:

| State | Copy |
|---|---|
| > 7 days | `Active until 12 Dec 2026` |
| ≤ 7 days | `Ends in 3 days` · `Ends tomorrow` — here the number **is** the action |
| today | `Ends today` |
| frozen / expired / inactive / none | `Paused` · `Expired` · `Inactive` · `No membership` |

The word "Membership" is dropped throughout. This line sits inside the membership
card, directly under the organisation that issued it.

**It gets its own row under a divider.** It used to be a sub-line of the org
identity, tying a fact about the *member* to a row about the *gym* — and making
both harder to scan.

### 3.6 Separators

**One.** Between the coach and the membership, because they are genuinely
different kinds of fact. None between the eyebrow and the coach — an eyebrow is
already subordinate; a rule there would imply two peers.

### 3.7 Type scale

| Role | Size / weight | Why |
|---|---|---|
| Coach name | 15 / 600 → **700 unread** | the card's subject |
| Preview | 11.5 / 400 → **600 unread** | supporting |
| Org eyebrow | 10.5 / 700, +1.1 tracking, muted | context |
| Membership | 11.5 / 500 | standing |
| Badge | 9.5 / 700, tabular | numeral |

Weight — not colour — carries unread, because weight is read **pre-attentively**,
before any glyph is parsed, and it survives colour blindness and greyscale.

---

## 4. The bug this redesign exposed

Moving the action icons inside the coach row put them under its
`excludeSemantics: true`. **`ExcludeSemantics` drops every descendant node** — a
screen-reader user would have found **no notification control and no message
control anywhere in the header.**

Caught by an existing test (`bySemanticsLabel('Notifications')` returned
nothing). The tappable identity region now stops before the actions, so each icon
keeps its own button role and its own count. The membership row likewise gained
its own `Semantics`, since it is no longer spoken as part of the org.

**This is the argument for pure, mountable widgets.** A visual-only change
silently deleted two controls from the accessibility tree, and only a rendered
test could see it.

---

## 5. Verification

| Case | Result |
|---|---|
| Long org name | eyebrow ellipsis, no overflow | ✅ |
| Long coach name at 320 px | ellipsis, no overflow | ✅ |
| Small device (320 px) | golden | ✅ |
| **1.6× accessibility text** | no overflow | ✅ |
| Unread 0 / 7 / 250 | no badge · `7` · `99+` | ✅ |
| No notifications | no badge, control still present | ✅ |
| Coach unnamed | neutral copy, no invented name, no duplicated line | ✅ |
| Coach unassigned | honest copy, messaging still offered | ✅ |
| Org loading | 96 px skeleton, no fallback name flash | ✅ |
| Membership loading | skeleton, **no date claimed** | ✅ |
| Membership expired / paused / inactive / none | glyph + copy, never reads active | ✅ |
| Verified badge | only when the backend says true | ✅ |
| No logo rendered | asserted | ✅ |
| Touch targets | ≥ 44 dp both icons | ✅ |
| Card height | **< 136 px**, enforced | ✅ |
| Light + dark goldens | regenerated, 6 images | ✅ |
| Screen reader | unread first, then who, then what; both icons announced | ✅ |

**Suites:** `flutter analyze` clean · **`flutter test` 270 / 270** · debug APK
built.

---

## 6. Would Apple keep this spacing?

The honest test I applied at each step: *does this pixel earn its place?*

Removed because they did not: a 48 px logo, a `COACH` caption, a `Message` pill,
the word "Membership" ×6, one border, 11 px of height.

Added because they did: a live conversation preview, a second badged action, a
divider that separates two genuinely different facts.

**The card now says more, in less space, with fewer elements.** That is the only
definition of premium that survives contact with a million daily users.

**One caveat, unchanged from every section before this:** the goldens are
machine-rendered. **No human has seen this card on a physical device.** Spacing
that measures correctly can still *feel* wrong, and that judgement is yours.

---

*Verified 2026-07-28: analyze clean · 270/270 · goldens regenerated · debug APK
built. No backend change. Nothing committed.*
