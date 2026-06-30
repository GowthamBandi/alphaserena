# AlphaSerena — Post-purchase client lifecycle + onboarding (design)

> 2026-06-28. Member-side feature. Backend (rules, Storage path, getMyTraining,
> trainer assignment, plan authoring) already exists in TrainersHQ — no deploy.

## Goal
After a member buys a membership, reflect the **real coaching lifecycle** on the
Home screen and let the member **complete the coach's onboarding questions**:

```
Active member → ① Complete onboarding → ② Coach being assigned → ③ Coach preparing plan → ④ Plan ready (full home)
```

## 1. Lifecycle state (derived; no new backend)
`ClientStage` computed in `HomeController` from already-streamed data:

| Stage | Condition |
|---|---|
| `onboarding` | active membership AND `clientProfiles.coachOnboardingDoneFor != clients.adminId` |
| `awaitingTrainer` | onboarding done AND `clients.trainerId` empty |
| `preparingPlan` | `trainerId` set AND `getMyTraining` workout==null && diet==null |
| `ready` | workout or diet present |

Detection of "onboarding done" uses a **member-owned flag** `clientProfiles.coachOnboardingDoneFor`
= the adminId the member onboarded for (handles switching coaches). Set on submit.
No reads of a possibly-missing doc (avoids the rules pitfall).

## 2. Home "Getting Started" card + gating
- When `stage != ready` (and linked + active): show a premium **3-step tracker**
  card (Onboarding · Coach · Plan) with the current step highlighted + its
  message/CTA; **hide** nutrition/progress/workout sections; show the status card
  + a motivational quote instead.
  - `onboarding` → "Complete Onboarding" button → `OnboardingFlowScreen`.
  - `awaitingTrainer` → info: "Your coach is being assigned."
  - `preparingPlan` → info: "Coach {name} is preparing your plan."
- At `ready` → card hidden, existing full home renders unchanged.
- Unlinked / inactive-membership states unchanged.

## 3. Onboarding flow (new)
- `OnboardingQuestion` model — mirrors TrainersHQ `onboarding_questions`:
  `id, question, type, options[], required, order` (types: shortText, longText,
  number, singleChoice, multiChoice, photo, document).
- `OnboardingService`:
  - `loadQuestions(adminId)` — `onboarding_questions where adminId==X`, sorted by
    `order` in Dart (no composite index).
  - `uploadFile(uid, file, filename)` — Storage `onboarding_uploads/{uid}/{ts}_{name}`
    with explicit contentType; returns URL.
  - `submit({clientId, adminId, uid, answers})` — writes `onboarding_responses/{clientId}`
    (§6.9 shape: `{clientId, adminId, authUid, submittedAt, updatedAt, answers:[{questionId, question, type, options, value}]}`)
    then sets `clientProfiles/{uid}.coachOnboardingDoneFor = adminId`.
- `OnboardingController` (GetX) — questions, answers map, per-field upload state,
  required validation, submit (busy/error).
- `OnboardingFlowScreen` — single scrollable brand form, one card per question,
  "X of Y answered" progress header, sticky Submit (disabled until required done).
  Renders all types incl. photo (image_picker) + document (file_picker) →
  thumbnail/filename + remove. Loading/empty/error states.

## 4. New deps (member app): `firebase_storage`, `image_picker`, `file_picker`.

## 5. Out of scope (already built in TrainersHQ): admin assigning `trainerId`,
trainer building/assigning workout & diet plans. Home only reflects them.

## Verification
`flutter analyze` clean; manual: onboarding renders all types, required gating,
file uploads, submit → Home advances to `awaitingTrainer`; stages reflect real data.
