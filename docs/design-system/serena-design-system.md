# Serena Design System (SDS) — Reference

**Status:** v1.0 — implemented + adopted across the TrainerHQ ecosystem (M1–M4). **Recommended for FREEZE (M5).**
**Distribution:** Option B (RFC-DISTRIBUTION) — spec-first, **per-repo** implementation, **Design Tokens = single source of truth**, drift-guarded. **No shared package** until the repo toolchains are intentionally reconciled.
**Brand:** black-&-red (RFC-BRAND) — accent `#D50000` on black (dark) / white (light). Orange is **not** core (secondary/semantic only). Colored glow retired.

This document reflects the **implementation as it exists in the repositories** (M5 reconstruction, 5 Jul 2026). It is identical across the three repos; per-app specifics are called out inline.

---

## 1. Architecture (layers)

```
serena.tokens.json          ← canonical Source of Truth (colors, type, space, radius, elevation, motion…)
        │  dart run tool/serena/generate_tokens.dart   (deterministic, byte-stable)
        ▼
serena_tokens.g.dart        ← generated Flutter-free raw layer (const int ARGB, double scales)  [DO NOT EDIT]
        │  consumed by
        ▼
serena_palette.dart         ← SerenaPalette (ThemeExtension) + SerenaTextStyles/Radii/Shadows/Motions/Accents
        │  registered additively in
        ▼
app_theme.dart              ← ThemeData.extensions: [AppPalette, SerenaPalette]   → context.serena
        │  + consumed by
        ▼
core/widgets/serena/serena_ui.dart   ← SDS UI kit (SerenaStatus, serenaStatusColor, SerenaStatusPill)
```

**Verified invariant (M5):** `serena.tokens.json`, `serena_tokens.g.dart`, and `serena_palette.dart` are **byte-identical across all three repositories** (md5-confirmed). The drift-guard asserts the generated layer matches the source in every repo + in CI.

## 2. Token source of truth

- **Edit only** `lib/core/theme/serena/serena.tokens.json`, then regenerate: `dart run tool/serena/generate_tokens.dart`.
- **Never hand-edit** `serena_tokens.g.dart` — the drift-guard (`tool/serena/drift_guard.dart`) fails CI on any drift.
- Colors carry theme-invariant brand/status hues + light/dark surface/text. Error is de-collided (`#E5484D`/`#F2555A`) from the brand red and from dark `accentText` (`#FF8A8A`). Status: `statusActive #1D9E75` (green), `statusPending #F5A623` / `statusWarning #E0A100` (amber), `statusBlocked #E5484D` (red).

## 3. Theme foundation

- **`SerenaPalette`** (`ThemeExtension`) — surface/role palette resolved per theme. Registered **additively** alongside each app's existing `AppPalette` (no screen forced to migrate).
- **`context.serena`** (`SerenaX` extension in `serena_ui.dart`) — the accessor. Falls back to the app's **default-theme** palette if the extension is absent.
- **Fonts are deferred** (SDS names Space Grotesk + Inter; apps keep their live fonts — TrainerHQ Inter, AlphaSerena/Admin Teko+Poppins). Font migration is a Phase-2B decision.

## 4. Component inventory (`core/widgets/serena/serena_ui.dart`)

| Symbol | Kind | Canonical spec |
|---|---|---|
| `SerenaX.serena` | extension | `Theme.of(context).extension<SerenaPalette>() ?? SerenaPalette.<defaultTheme>()` |
| `SerenaStatus` | enum | `active · pending · warning · blocked · info · neutral` (complete vocabulary; a new status can never be un-mapped) |
| `serenaStatusColor(context, status)` | fn | maps `SerenaStatus` → SDS token via `context.serena` |
| `SerenaStatusPill` | widget | dot/icon in the status hue + tinted fill + hairline border; **label in `textPrimary`** (high-contrast — amber hues are too light as small text); wrapped in `Semantics(label: 'Status: …')`. Styling: padding `H10×V5`, radius `20`, dot `7×7`, label `w600 / 11.5 / ls 0.1`. |

**Canonical styling is identical across all three repos** (M5 normalized the Admin pill, which had drifted to `V6/w700/ls0.2`). The **only** intentional per-repo difference is the `SerenaX` fallback theme (TrainerHQ/Admin `light`, AlphaSerena `dark`) — matching each app's default `themeMode`.

> **Extension guidance:** add new components here (per-repo, mirrored) only when consumed. Keep the label in a high-contrast tone and route color through `serenaStatusColor` so status stays legible + accessible. Do **not** extract a shared package yet (Option B — blocked on toolchain reconciliation: Admin Dart SDK `^3.10.1`/`google_fonts ^8.1.0` vs mobile `^3.8.1`/`^6.3.2`).

## 5. Adoption status (per app)

| App (repo) | Consumes | Highlights |
|---|---|---|
| **TrainerHQ** (coach, `trainers_hq`) | Full **token bridge** (`AppPalette`/`BrandColors` re-sourced from `SerenaColor`) + `SerenaPalette` + kit | Home/Dashboard/Clients/Client-Detail: SDS semantic status (green/amber/red), a11y labels. Commit `9473e90`. |
| **AlphaSerena** (member, `alphaserena`) | Additive `SerenaPalette` + kit (**no** surface bridge — dark palette intentionally differs from SDS) | Shell nav drift fixed → SDS accent; Check-In "done"=green; a11y from zero → 6. Commit `348b455`. |
| **Admin Portal** (`alphaserena_admin_portel`) | Additive `SerenaPalette` + kit | Trainers/Clients status chips + KPIs → SDS tokens (removed a `!` crash); nav a11y. Commit `dc4bcc3`. |

## 6. Quality gates

- **drift-guard** — `dart run tool/serena/drift_guard.dart` (byte-parity; **in CI**).
- **serena tests** — `test/serena/serena_foundation_test.dart`: frozen-token values, the **M0 WCAG ≥3:1 contrast exit gate** (both themes), accent/error separation, palette binding, a swatch golden. Run by `flutter test`.
- **token-lint** — `bash tool/serena/token_lint.sh lib`: flags `Colors.*` / `Color(0x…)` / inline `GoogleFonts` / raw `fontSize` in the UI layer. **Informational** in CI (debt is tracked; burns down in Phase 2B).
- **CI** — TrainerHQ `ci.yml` (analyze + test + functions + rules, drift-guard added M5); AlphaSerena + Admin `.github/workflows/serena.yml` (M5).

## 7. Known debt / deferred (Phase 2B)

- **Tokenization debt** (token-lint): TrainerHQ **529** · AlphaSerena **938** · Admin **77** — pre-existing UI-layer hardcoded values; burn down as screens migrate.
- **Font migration deferred** (Space Grotesk + Inter) + `google_fonts` 6↔8 reconciliation.
- **Surface convergence** — AlphaSerena/Admin surfaces not force-bridged to SDS (evidence-based restraint; a possible SDS `borderDark` erratum to review).
- **Accessibility** — primary controls labeled; a full sweep (all tappables, dialogs, focus order, keyboard nav — web-critical for Admin) is Phase-2B.
- **Shared package** — not extracted (Option B); revisit when toolchains reconcile.

---
*M5 finalization. The SDS is stable, consistent, drift-guarded, tested, documented, and recommended for freeze.*
