# Section 1.5 — Coach Communication Entry Certification

- **Date:** 2026-07-28
- **Scope:** the Home communication entry only. Not the chat screen, not the
  identity resolver, not trainer assignment.
- **Backend changed:** **none.** Every field used here already existed.
- **Nothing committed.**

---

## 1. Architecture

```
member or coach sends a message
        │
        ▼
chats/{clientId}/messages/{msgId}
        │  onMessageCreated  (Cloud Function, already deployed)
        ▼
chats/{clientId}                       ← THE THREAD DOCUMENT
   lastMessage { text, type, senderId, senderName, senderRole, at }
   unread      { member, staff }
   lastReadAt  { member, staff }
   updatedAt
        │  ChatService.watchConversation()   ← one listener
        ▼
CoachConversation  (pure: unread, preview, lastAt, lastSender)
        │
        ▼
HeaderView coach row   ── avatar · name · preview · age · badge
```

**One listener on one document** serves the count, the preview, the sender and
the timestamp — the same document the unread count already required. The richer
entry costs **zero additional reads**.

---

## 2. The correction that made this possible

The Section 1 certification stated:

> *"Last-message preview. The thread document carries no `lastMessage` snippet…
> Correct fix: denormalise a snippet onto the thread on write."*

**That was wrong.** `lastMessage` has been written by `onMessageCreated` since the
chat subsystem shipped — text, type, sender id, sender name, sender role and
timestamp. The error came from reading the *member-side service* (which never
read the field) and concluding the field did not exist, instead of reading the
*writer*.

So a preview, a timestamp and sender attribution were available all along and
were deferred as "needs backend" for no reason. Everything in this section is
built from data that was already there.

**Also already available, verified this pass:** `lastReadAt.member` and
`lastReadAt.staff`. A "Seen" indicator is therefore derivable — deliberately not
used (§7).

---

## 3. UX decisions

### 3.1 The "Message" pill is gone

The entry was a coach row plus a `[💬 Message]` pill.

**A verb carrying no information.** It told the member what tapping does — which
a row containing a person's face and name already says — while occupying the one
position on the row that could have told them whether tapping was *worth it*.

It also created a false affordance: the pill looked like the button, but the
**whole row** was already the tap target. Members aim at the small thing.

### 3.2 A conversation row, not a button

```
┌──────────────────────────────────────────────────┐
│ (◕)  Ravi Kumar                              2m  │
│      Check your macros before Friday          ②  │
└──────────────────────────────────────────────────┘
```

This is where WhatsApp, Apple Messages and every mail client independently
converged, because it answers **who / what / when / how many** in one fixation.
The member can now decide whether to open the thread *without opening it* —
which is the entire job of an entry point.

**It costs no vertical space.** The row was already two lines (`COACH` caption +
name). It is still two lines (name + conversation). Two low-information elements
were replaced by one high-information line.

### 3.3 The `COACH` caption is gone

Once the secondary line carries a conversation, a caption stating the obvious
above a human face is noise. The role has not been lost — when there is no
conversation yet, the secondary line states it (`Your coach`).

### 3.4 The unread signal is layered, not singular

Three cues, all conventional, all free:

| Cue | Why |
|---|---|
| **Count badge** in the trailing column | the precise fact |
| **Name in w700** | weight is pre-attentive — read before any glyph is parsed |
| **Preview in full-contrast text** rather than muted | the row visibly "lifts" |

A member with tired eyes at 6 a.m. registers the row differently *before*
reading a character. One badge alone would be a single point of failure.

### 3.5 The count, never a dot

`1 · 5 · 25 · 99+`. A dot says "something happened"; a number says whether this
is a ten-second read or a real conversation. Capped at `99+` so a neglected
thread cannot widen the row and push the name into an ellipsis.

### 3.6 Preview text is byte-identical to the push notification

`messagePreview` is a deliberate mirror of the backend's function, emoji
included. A member who taps a notification reading **"📷 Photo"** must not land
on a row reading "Image" — two descriptions of one event is exactly the sort of
seam that makes a product feel assembled rather than designed.

### 3.7 "You:" when the member spoke last

The cheapest possible signal that the ball is in the coach's court, and the
reason a member does not re-open a thread merely to check whether they already
replied.

An **admin**-sent message reads as the coach, not as the member: a solo owner
sends as an admin, and to the member they are simply *their coach*.

---

## 4. Engineering fixes

1. **`ChatService.watchConversation`** — one thread listener returning a typed
   `CoachConversation`. `watchUnread` is kept as a projection of it, so there is
   never a second subscription. Errors and a missing thread resolve to
   `CoachConversation.empty`: this drives a header, and **a header must never be
   able to break**.
2. **A defect I introduced, caught by the existing tests.** The new secondary
   line printed `Your coach` while the primary line *already* printed
   `Your coach` for an unnamed coach — the same words twice in one row. The
   secondary line now yields `Tap to message` in that state.
3. **A defect I introduced in the semantics label.** Interpolating
   possibly-empty segments produced doubled spaces, which some screen readers
   announce as an extra pause. The label is now assembled from non-empty parts
   only.
4. **Clock-skew guard.** Firestore server timestamps routinely land milliseconds
   *ahead* of the handset. `conversationAge` returns `now` for any
   non-positive age — `-1m` would look like a bug on a premium surface.
5. **Tabular figures** on the age and the badge, so a row does not reflow as
   `9m` becomes `10m` or `9` becomes `10`.
6. **Thread-tolerance.** `calls.ts` can create `chats/{clientId}` *without* a
   `lastMessage`. That state now renders as "no conversation yet" rather than a
   blank preview line.

---

## 5. Micro-interactions

Restrained by intent. The header is seen 4–8 times a day for one to two seconds
— anything theatrical becomes irritating by week two.

| Moment | Behaviour |
|---|---|
| Badge appears | scale 0.85 → 1 with fade, 180 ms `easeOutBack`, **keyed on the count** so it re-plays only when the number actually changes |
| Badge disappears | **no animation** — an exit would draw the eye back to something just dealt with |
| Row pressed | existing `InkWell` ripple across the full row |
| Coach photo | cached; initials render underneath as the loading *and* error state, so the avatar is never blank or a spinner |
| Age text | plain swap — animating a clock is noise |

**Not built:** pulsing badges, bouncing, shimmer, sound. Each fails the
"one million members, every day" test.

---

## 6. Verification matrix

`test/coach_conversation_test.dart` — **26 tests**, plus 30 in the existing
header suite.

| Case | Result |
|---|---|
| Unread **0** | no badge, muted row, preview retained | ✅ |
| Unread **1 / 5 / 9** | exact count | ✅ |
| Unread **25 / 99** | exact count, no premature truncation | ✅ |
| Unread **100 / 4821** | `99+` | ✅ |
| Negative stored count | clamped to 0, never rendered | ✅ |
| Text message | passes through | ✅ |
| **Image, no caption** | `📷 Photo` — identical to the push | ✅ |
| Image with caption | `📷 form check` | ✅ |
| **Voice note** | `🎤 Voice message` | ✅ |
| Multi-line message | collapsed to one row | ✅ |
| 400-character message | truncated at 117 + `…` | ✅ |
| Member spoke last | `You: …` | ✅ |
| Coach spoke last | no prefix | ✅ |
| **Admin** spoke last | reads as coach | ✅ |
| Unknown sender role | not attributed; no preview | ✅ |
| **No thread document** | quiet entry, no placeholder | ✅ |
| Thread from the **call subsystem**, no `lastMessage` | no false preview | ✅ |
| Corrupt `lastMessage` | ignored, unread still shown | ✅ |
| Age: <1m / 5m / 59m / 3h / 2d / 6d / older | `now` `5m` `59m` `3h` `2d` `6d` `2 Mar` | ✅ |
| **Server clock ahead of device** | `now`, never negative | ✅ |
| No timestamp | no age, no placeholder | ✅ |
| Coach changed / photo changed | live via Section 1's `getMyTraining` channel | ✅ |
| Offline | last thread snapshot from cache; header never errors | ✅ |
| Reconnect | listener resumes; badge and preview update in place | ✅ |
| Cold start | empty until the first snapshot — never a stale number | ✅ |
| Home refresh / notification tap | row re-renders from the same listener | ✅ |
| **Dark mode** | goldens regenerated, both themes | ✅ |
| **Large text (1.6×)** | no overflow (existing layout test) | ✅ |
| Long coach name at 320 px | ellipsis, no overflow | ✅ |
| Touch target | whole row; ≥44 dp (existing test) | ✅ |
| Accessibility label | unread **first**, then who, then what and when | ✅ |

### Suites

| Suite | Result |
|---|---|
| `flutter analyze` | **No issues found** |
| `flutter test` | **269 / 269** (243 + **26 new**) |
| Header goldens | regenerated for the intentional redesign; 6 images, both themes |
| `flutter build apk --debug` | **Built** |

---

## 7. Already supported vs. future

**Already implemented (this pass):** unread count, unread emphasis, last-message
preview, type-aware preview, sender attribution, relative timestamp, coach name,
coach photo, correct destination after reassignment.

**Available but deliberately unused:** `lastReadAt.staff` makes a **"Seen"**
indicator derivable — comparing it against the member's last message timestamp.
Not used because on a *home* surface it answers a question the member is not
asking yet, and it belongs inside the thread where they are actually waiting on
a reply. Recorded so it is not re-investigated as "needs backend".

**Genuinely absent — no backend exists, deliberately not faked:**
- **Typing indicator** — no typing or presence document.
- **Online / last-seen status** — no presence system in either app.
- **Per-message delivered/read receipts** — messages carry no `readAt`.

Each would require new infrastructure. A fabricated presence dot is a lie the
member can catch, and it would undermine the trust this row exists to build.

**Future enhancement:** a quick-reply affordance on long-press; per-thread mute.

---

## 8. Certification

**1 · Does the member always know who they are messaging?**
**Yes.** The coach's real name and face, resolved live by Section 1's
`getMyTraining` channel, with initials as an honest fallback and the role stated
whenever a name cannot be claimed. The photo is suppressed with the name, so the
face and the name can never come from different generations of data.

**2 · Are unread messages impossible to miss?**
**Yes.** Three independent, conventional cues — a counted badge, a bolder name,
and a full-contrast preview — plus the count spoken **first** by screen readers.
Missing it requires missing all three.

**3 · Does the button feel premium?**
**It is no longer a button, and that is the improvement.** It is a conversation
row of the kind every messaging product the member already trusts has converged
on, showing what was said, by whom and when — in the same vertical space the old
caption-and-pill occupied.

**4 · Does it remain simple?**
**Yes.** One row, one tap target, one listener, one document. Nothing was added
to the backend and nothing new is fetched. Two elements were removed.

**5 · Would I personally approve this communication entry for production?**
**Yes.** It answers *who / what / when / how many* in a single fixation, it
degrades honestly at every edge — no thread, corrupt thread, offline, clock
skew, 4,821 unread — and it invents nothing. The one caveat I will not paper
over: like the sections before it, **this has not been driven against live
Firestore by a human.** Every state is covered by test and by golden, but the
composed live experience is unobserved.

---

*Verified 2026-07-28: analyze clean · 269/269 · goldens regenerated · debug APK
built. No backend change. Nothing committed.*
