# Section 1 — Final Completion & Messages Parity Certification

- **Date:** 2026-07-28
- **Scope:** the three remaining Section 1 visual items, plus messaging parity
  against TrainerHQ as the reference implementation.
- **Backend, Firestore, Cloud Functions:** untouched.
- **Nothing committed.**

---

## 1. Section 1 — the three items

### 1.1 Organisation name → brand red

`p.accent` — `#D50000`, the app's single accent value. **Not a brighter
variant**, and no second red introduced.

The colour works *because* the org is an eyebrow: 10.5 px small caps in brand red
reads as considered branding. The same hue at headline size would shout, and
would compete with the send button and the unread badges, which are the only
other saturated elements in the app.

The logo was **not** reinstated.

### 1.2 Coach information — the real bug

**Reported:** the card read `Gowtham` / `d`.

**Cause, and it was mine.** The previous pass put the last-message preview on the
coach's secondary line. When the last message was literally the character `d`,
the card rendered a person as *"Gowtham / d"*. Technically accurate; completely
wrong for an identity card.

**The lesson, recorded:** identity must not fluctuate with chat traffic. A
preview is live content; an identity card is a stable fact. Putting content into
an identity slot means every message the coach sends re-writes who they appear to
be. Unread now lives only on the message badge, where it cannot corrupt the
person.

**Final layout — role above name**, matching the eyebrow pattern one level up, so
the whole card reads consistently: *small muted qualifier, then the thing
itself.*

```
Assigned Coach          10.5 / w500 / muted
Gowtham                 15   / w600 / primary
```

**States — no placeholder, no null, no stray characters, ever:**

| Condition | Label | Name |
|---|---|---|
| Coach resolved | `Assigned Coach` | the real name |
| Assigned, name unresolved | `Assigned Coach` | `Your coach` |
| No coach at all | `Coach` | `Not assigned yet` |

Pinned by test, including explicit assertions that `null` never renders and that
the retired preview line is gone.

### 1.3 Icon spacing

| Gap | Before | After |
|---|---|---|
| Name block → first icon | 8 | **12** |
| Between the two icons | 6 | **10** |

**Why 10 and not 8:** the tiles are 40 px and the badge overhangs its top-right
corner by 4 px. At 6 px the notification badge visually touched the message
tile — the two controls read as one segmented widget rather than two independent
actions. 10 px clears the overhang with margin at every count width.

Unchanged and re-verified: 40 px drawn tile, 44 px tap target, `99+` cap, tabular
figures, 1.5 px card-coloured ring, entry-only animation keyed on the value.

---

## 2. Messaging parity with TrainerHQ

TrainerHQ's chat screen states its own contract:

> *"V1 coaching messenger — a focused TEXT chat. Composing photos, voice notes
> and calls was removed from the coach UI (V1 is not a WhatsApp replacement);
> media the MEMBER sends from the client app is still received and displayed
> here… media compose can return in V2 by re-adding the input affordances."*

AlphaSerena had drifted: it still offered all three. **A member-side affordance
the coach cannot reciprocate is worse than none** — the member records a voice
note, or places a call, into a surface the other party no longer has.

### Removed

| Affordance | Where | Now |
|---|---|---|
| **Call button** | app bar action | app bar has **no actions at all** |
| **Photo attach** | composer, `Icons.add_photo_alternate_outlined` | gone |
| **Voice record** | composer, `Icons.mic_none_rounded` | gone |
| Recording bar, amplitude meter, waveform downsampler | composer state | gone |
| Image-source bottom sheet (gallery / camera) | modal | gone |
| `_attachImage`, `_startRecording`, `_stopRecording`, `_recordingBar`, `_attachSheet` | ~200 lines | deleted |
| `image_picker`, `record`, `path_provider`, `call_service` imports | file header | deleted |

### Retained — deliberately

**Every received-media render path.** Images, voice notes and call records that
already exist still display exactly as before, in both apps. Removing the
*renderers* would have silently blanked real conversation history.

The send / idempotency / offline / upload architecture is untouched, matching
TrainerHQ's stated approach, so V2 can restore compose on both sides at once.

### No empty padding left behind

The app bar's `actions:` list is **removed entirely**, not emptied — an empty
list still reserves trailing inset. The composer's text field now begins at the
container's own 12 px inset rather than behind two ghost slots. Verified by
golden.

### Composer, side by side

Both apps are now: `[ rounded text field (1–5 lines, 2000 max) ] [ gradient send ]`.
Identical structure, identical order, no third element.

---

## 3. Parity report — full audit

| Area | TrainerHQ | AlphaSerena | Verdict |
|---|---|---|---|
| **Conversation list** | inbox of many clients | **none** — one coach, one thread | ✅ member-specific: a one-row list is a worse home than going straight in |
| **App bar** | title + avatar, no actions | title + avatar, no actions | ✅ matched |
| **Composer** | text + send | text + send | ✅ matched |
| **Message bubble** | text / image / voice / call rendering | same | ✅ matched |
| **Failed-send bubble** | retry affordance | same | ✅ matched |
| **Load-older row** | paginated history | same | ✅ matched |
| **Date chips** | day separators | same | ✅ matched |
| **Empty conversation** | prompt to start | same | ✅ matched |
| **Unread** | thread `unread.staff` | `unread.member` + Home badge | ✅ symmetric |
| **Offline** | queued sends, cached history | same | ✅ matched |
| **Calls** | removed | **removed** | ✅ now matched |
| **Voice compose** | removed | **removed** | ✅ now matched |
| **Photo compose** | removed | **removed** | ✅ now matched |

**Remaining differences, all intentional:**

1. **No conversation list on the member side.** A member has exactly one
   coaching thread; a list containing one row is pure friction.
2. **Member-side voice *playback* keeps its own bubble widget.** Same behaviour,
   separate file — the two apps have no shared package.

---

## 4. Member experience — the challenge questions

| Question | Answer |
|---|---|
| Who am I talking to? | Name + photo in the app bar; `Assigned Coach` + name on Home |
| Are there unread messages? | Counted badge on the Home message icon, and the count is spoken first |
| Which conversation is newest? | N/A — one thread |
| Did the coach reply? | Thread ordering + the unread badge clearing on read |
| Can I send quickly? | Home message icon → thread → field is the widest element on the row |
| Does it feel lightweight? | The composer is now two elements instead of four |

**"What would still make this feel like an old Flutter app?"** — the answers I
acted on: a stray character rendered as identity; two icons close enough to read
as one segmented control; a default-white org name with no brand presence; and a
composer carrying three actions where the reference product ships one.

---

## 5. Verification

| Case | Result |
|---|---|
| Org name renders in `#D50000` | asserted by test | ✅ |
| Coach: `Assigned Coach` over the real name | asserted | ✅ |
| Coach empty state: `Coach` / `Not assigned yet` | asserted | ✅ |
| No `null`, no stray preview line | asserted | ✅ |
| Unread 0 / 1 / 9 / 99+ on both icons | ✅ |
| Badge never overlaps the adjacent tile | 10 px gap clears a 4 px overhang | ✅ |
| Touch targets ≥ 44 dp, both icons | ✅ |
| Screen reader: both icons announced, count first | ✅ |
| Card height | **< 136 px**, enforced | ✅ |
| Small phone (320 px), long org + coach names | ellipsis, no overflow | ✅ |
| 1.6× accessibility text | no overflow | ✅ |
| Light + dark goldens | regenerated | ✅ |
| Chat: no call action, no attach, no mic | ✅ |
| Chat: received image / voice / call still render | ✅ |
| Chat: no leftover padding where actions were | golden | ✅ |

**Suites:** `flutter analyze` clean · **`flutter test` 273 / 273** · debug APK
built.

---

## 6. Certification

**1 · Is Section 1 visually complete?**
**Yes.** Organisation in brand red as an eyebrow, coach as `Assigned Coach` over
a real name with an honest empty state, two properly separated badged actions,
membership stating a date on its own row. Under 136 px, enforced. Every state
covered by test and golden.

**2 · Does AlphaSerena now match TrainerHQ messaging?**
**Yes.** Calls, photo compose and voice compose are removed on both sides; the
composer is text-plus-send in both; received media still renders in both; no
padding was left where the actions used to be. The one structural difference —
no conversation list — is correct for a member with a single coach.

**3 · Would I personally approve this for production?**
**Yes.** The defect that reopened this section — `Gowtham / d` — was mine, and
its cause is now closed by rule rather than by patch: **identity slots hold
identity, never live content.** The messaging surfaces of the two apps offer the
same things, which matters more than either one being individually clever.

**The standing caveat, unchanged:** goldens are machine-rendered. **No human has
seen these screens on a physical device.** I can prove the card measures under
136 px, that nothing overflows at 1.6× text, and that every state renders — but
whether the spacing *feels* right in the hand is your call, and Section 1 should
not be frozen until you have looked at it.

---

*Verified 2026-07-28: analyze clean · 273/273 · goldens regenerated · debug APK
built. No backend change. Nothing committed.*
