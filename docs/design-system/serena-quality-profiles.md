# SDS — Per-Repository Quality Profiles (M1 instantiation)

Instantiates the frozen SDS §15 Quality Profiles (RFC-QUALITY-PROFILE) for each repo and binds them to the inherited AIEO gates (`REV-1` self-then-adversarial review · `AUD-1` consolidation audit · `RDY-1` readiness on the shipped surface → `RDY-2` release-equivalent transition) and to the M1 substrate's CI gates.

**Assurance classes:** **Critical** → independent verification + `AUD-1` sampling + `RDY-1` gate · **Elevated** → independent review + spot audit · **Baseline** → self-review + lint/CI.

**M1 substrate assurance = Elevated** (foundational, high-leverage): the automated gates (drift-guard + `dart/flutter analyze` + tokenization lint + golden) carry the heavy verification; a human `REV-1` reviews the generator + the binding.

## CI gate bindings (all repos)
| Gate | Mechanism (this substrate) | Blocks |
|---|---|---|
| Token drift | `dart run tools/drift_guard.dart` (byte-parity to `serena.tokens.json`) | merge |
| Valid tokens | `dart analyze generated/serena_tokens.g.dart` + `flutter analyze` (binding) | merge |
| Tokenization | `tools/token_lint.sh lib` (0 `Colors.*`/`Color(0x…)`/inline `GoogleFonts` in `screens/`+`features/`) — *enforced on redesigned files; legacy tallied as debt burn-down* | merge (redesigned scope) |
| Render drift | `flutter test` goldens (`goldens/*.png`) | merge |
| Both-theme · 3-breakpoint · states · security · perf · docs | per-surface checklist (frozen spec §15) attached to each freeze report | `RDY-1` |

## TrainerHQ (coach · mobile · seed)
| Area | Class | Notes |
|---|---|---|
| Membership/money surfaces · the attention cockpit (Home/Clients/Client-Detail) | **Critical** | trust of "who needs you"; `RDY-1` on shipped surface |
| Plan builders · chat · check-ins | **Elevated** | |
| Library/exercise/food content · legal/settings | **Baseline** | |
| **SDS substrate** (tokens/binding/generator) | **Elevated** | seed = SoR home; drift-guard + analyze + golden gate it |

## AlphaSerena (member · mobile)
| Area | Class | Notes |
|---|---|---|
| First-run + purchase funnel (auth/join/checkout) · nutrition persistence · Check-In submission | **Critical** | the theme-blind funnel is the M1 flagship (later step); money paths CF-owned |
| Home daily loop · workout session · progress | **Elevated** | |
| Profile/settings · static | **Baseline** | |
| **SDS substrate** | **Elevated** | highest token debt (940 lint hits today) — burn down as screens migrate |

## AlphaSerena Admin (founder · web)
| Area | Class | Notes |
|---|---|---|
| Payments (money truth) · Admins moderation · coupon data-contract fix | **Critical** | web keyboard/focus SC in scope |
| Dashboard · Subscriptions · Trainers/Clients | **Elevated** | |
| Static/settings | **Baseline** | |
| **SDS substrate** | **Elevated** | adds `consoleBg`; 4 stale screens are the M4 reskin target |

**Gate ownership:** the token-substrate PR in each repo carries the Elevated bindings (drift-guard + analyze + golden green, generator + binding `REV-1`-reviewed); each later screen-reskin PR carries its surface's assurance-class bindings.
