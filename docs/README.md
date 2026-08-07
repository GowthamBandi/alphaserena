# AlphaSerena — Documentation Index

## Path convention

Reports in this tree were written at the **workspace root** (`flutter_works/`) and were
relocated here on 2026-08-07. Any repository-qualified path inside them — `alphaserena/lib/…`,
`trainersHQ/lib/…`, `trainershq-backend/functions/…`, `shared/…` — is **relative to the
workspace root**, not to this folder. Nothing in these documents uses relative markdown links,
so no link was rewritten and none is broken.

Cross-references between reports are by **bare filename** (e.g. ``NUTRITION_CTO_FORENSIC_AUDIT.md``).
Use this index to locate the named file.

## Layout

| Folder | Holds |
|---|---|
| `audits/` | Investigation-only passes — nothing was implemented or fixed |
| `root-cause/` | Root-cause proofs and runtime divergence investigations |
| `certifications/` | Certifications, freeze reports, production GO / NO-GO verdicts |
| `reports/` | Delivery, redesign, inventory and product-bug reports |
| `screenshots/` | Device captures referenced by the reports |
| `certification/` | Pre-existing device captures (workout / nutrition) |
| `design-system/` | Serena design system and quality profiles |
| `superpowers/` | Plans and specs |

Files directly in `docs/` predate this reorganization and were left in place.

## audits/

- `HOME_MYPLANS_CTO_FORENSIC_AUDIT_2026-08-04.md` — Home + My Plans forensic audit
- `LIFESTYLE_CTO_FORENSIC_AUDIT.md` — Lifestyle module, tri-repo scope
- `NUTRITION_CTO_FORENSIC_AUDIT.md` — Nutrition module, zero-implementation pass
- `PROGRESS_CTO_DISCOVERY_AUDIT.md` — Progress module discovery

## root-cause/

- `LIFESTYLE_ROOT_CAUSE_PROOF.md` — why the member app never received updates
- `LIFESTYLE_RUNTIME_DIVERGENCE_REPORT.md` — "everything writes, nothing reads back"

## certifications/

- `LIFESTYLE_FIX_CERTIFICATION.md` — defects A & B
- `LIFESTYLE_REMEDIATION_CERTIFICATION.md` — remediation of the forensic audit
- `MY_PLANS_CTO_FREEZE_REPORT_2026-08-04.md` — My Plans freeze
- `MY_PLANS_PRODUCTION_FREEZE_REPORT.md` — My Plans production freeze
- `NUTRITION_FIX_CERTIFICATION.md` — Nutrition remediation
- `NUTRITION_HISTORY_CTO_FREEZE_REPORT_2026-08-04.md` — Diet tab history
- `NUTRITION_PRODUCTION_ACCEPTANCE.md` — freeze gate, NOT APPROVED
- `NUTRITION_PRODUCTION_FREEZE_REPORT.md` — final production freeze audit
- `NUTRITION_RUNTIME_CERTIFICATION.md` — live runtime validation
- `PROGRESS_PRODUCTION_FREEZE_REPORT.md` — superseded by the FINAL revision
- `PROGRESS_PRODUCTION_FREEZE_REPORT_FINAL.md` — supersedes the above

## reports/

- `ALPHASERENA_PRODUCT_BUG_REPORT.md` — product bug hunt, phase 2 (partial)
- `MY_PLANS_CTO_PRODUCTION_REPORT.md` — My Plans production report
- `MY_PLANS_FIELD_INVENTORY.md` — backing-data inventory; cited by `lib/screens/dashboard/plans/`
- `MY_PLANS_PRODUCTION_COMPLETION_REPORT.md` — final polish pass
- `MY_PLANS_REDESIGN_REPORT.md` — foundation delivery
- `NUTRITION_N17_RESOLUTION.md` — N17 resolution
- `UX_COMPLETION_REPORT.md` — loading, empty states, perceived performance
- `UX_FREEZE_ANIMATION_REPORT.md` — premium UX freeze, pass 2

## screenshots/

- `ux_before_home_blanked.png` / `ux_after_home_retained.png` — the Home-blanking
  regression fixed in `reports/UX_COMPLETION_REPORT.md`
