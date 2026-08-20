---
target: Spendly app — primary flows (Home, Quick Add, Budget Setup, Categories)
total_score: 26
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
p2_count: 2
timestamp: 2026-08-20T07-32-52Z
slug: imary-flows-home-quick-add-budget-setup-categories
---
Method: dual-agent (A: a85b63d5289d7ca83 · B: a4e4515502047c804)

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 2 | Quick Add's Save button has no disabled/loading state — double-tap can double-submit |
| 2 | Match Between System and Real World | 4 | "Today"/"Yesterday", time-of-day greeting, ₹ en_IN formatting throughout |
| 3 | User Control and Freedom | 2 | Quick Add's close (X) pops instantly with zero unsaved-changes guard |
| 4 | Consistency and Standards | 3 | Tokens used pervasively; `_AddBudgetButton` hand-rolls a pill instead of reusing `OutlinedButton` |
| 5 | Error Prevention | 2 | Typing "0" on a category budget silently deletes it — no distinct clear affordance |
| 6 | Recognition Rather Than Recall | 4 | Last-used category, auto-tagged trip, current picks always shown as chips |
| 7 | Flexibility and Efficiency of Use | 2 | No "repeat last expense," no shortcuts; categories past top-7 cost a sheet round-trip |
| 8 | Aesthetic and Minimalist Design | 3 | System discipline is real; `_BudgetCard` packs 7 elements into one card |
| 9 | Error Recovery | 3 | Blocked category-delete dialog is exemplary; Quick Add's validation SnackBar is generic |
| 10 | Help and Documentation | 1 | No contextual help; "Ignore in totals" is a real behavior with zero in-UI explanation |
| **Total** | | **26/40** | **Acceptable — significant improvements needed before users are happy** |

## Design Specificity Verdict

**LLM assessment:** Grounded in Spendly specifically, not a re-skinned shell. The FX "freeze rule" in Quick Add (don't silently re-convert an untouched amount if a trip's rate later changes, preserving a month the user already reconciled), date-range trip auto-tagging, the 90-day backdate window, and the per-category "ignore in totals" toggle are all specific product logic, not boilerplate CRUD. Visually, DESIGN.md's Named Rules are honored with real discipline: gradient appears only at Home's hero/FAB, Quick Add's save CTA, the budget sheet's CTA, and the category sheet's save CTA — never as chip fill or decoration — and every rupee figure is set in Sora without exception. This could not be re-skinned onto an unrelated app without rewriting real logic.

**Deterministic scan:** The bundled detector (`detect.mjs`) returned exit 0 / `[]` on every target — but it's built for HTML/CSS/JSX markup patterns and this is pure Dart/Flutter, so the empty result is the detector having nothing in its grammar to match, not a quality signal. Treat it as inapplicable, not "clean." A supplementary grep pass found zero raw hex-color literals outside `tokens.dart` in these 6 files (the token system holds), but 42 hardcoded `fontSize:` literals across the 6 files instead of routing through `Theme.of(context).textTheme` roles — a real, countable pattern worth a consistency pass, though not a blocking issue on its own. No TODO/FIXME markers, no single-line copy over 60 characters, though several `AlertDialog` bodies use 2-3 segment string concatenation that reads as edited-for-length copy (Carry-forward warning, blocked-category-delete dialog) rather than a red flag.

**Visual overlays:** Not applicable — Spendly is a native mobile app with no dev server or browser target to inject into. No fallback screenshot exists for this platform; this critique is source-grounded only.

## Overall Impression

Spendly's design system is more disciplined than its interaction design. The visual layer (tokens, gradient restraint, Sora-for-money, dark-mode parity) is executed with real rigor — but the app's single most-used screen, Quick Add, exposes five simultaneous decision surfaces at once and gives zero feedback at the moment its core habit-forming action completes. The biggest opportunity: the product principle "fast entry beats completeness" is true of the visual chrome but not yet true of the interaction sequence.

## What's Working

1. **The FX freeze rule** (`quick_add_screen.dart:798-835`) — a specific, carefully-reasoned business rule documented directly in code, not a generic feature.
2. **Blocked category-delete flow** (`category_edit_sheet.dart:620-715`) — states the exact blocking count and offers "Archive instead," turning PRODUCT.md's "archive over delete" principle into an actual interaction, not just policy.
3. **Bottom-pinned keypad+save with keyboard collapse** (`quick_add_screen.dart:202-232`) — a deliberate one-thumb-reachability decision that holds up under Casey's persona test.

## Priority Issues

**[P1] No unsaved-changes guard on Quick Add's close button**
- Why it matters: an interrupted or reconsidering user (a call, a notification — Casey's exact scenario) loses a typed amount and picked category with zero warning. This is the app's highest-frequency screen and its escape hatch is also its biggest data-loss risk.
- Fix: confirm-if-dirty on close (skip the dialog when the form is untouched), matching the confirmation discipline already used everywhere else in the app (delete flows, carry-forward).
- Suggested command: `/impeccable harden`

**[P1] Typing "0" on a category budget silently deletes it**
- Why it matters: contradicts the app's own established pattern — every other destructive action (delete expense, delete category, carry-forward overwrite) gets an explicit confirmation, but clearing a budget by accident while reconsidering an amount does not.
- Fix: require a distinct "Clear budget" action instead of overloading zero, or add a confirm step when saving a zero over an existing non-zero budget.
- Suggested command: `/impeccable harden`

**[P1] Quick Add exposes 5 simultaneous decision surfaces; fails 4 of 8 cognitive-load checks**
- Why it matters: amount, category, date, trip, and note are all live and interactive at once on the app's single most-repeated screen; the category grid alone shows 8 tiles, double the ≤4 working-memory guideline, before "More" even appears.
- Fix: default date=today and trip=auto-tag silently (already computed), surfacing them as edit affordances only — cut the default-path decision count from 5 to 2 (amount, category), consistent with the stated "fast entry beats completeness" principle.
- Suggested command: `/impeccable distill`

**[P2] No success feedback after saving an expense**
- Why it matters: the core habit-forming action ends in a silent `Navigator.pop()` — no toast, haptic, or animation marks the moment an expense is actually logged, giving a daily-use app no peak moment to reinforce the habit it depends on.
- Fix: a one-line post-save confirmation (e.g. "₹450 logged to Food · ₹1,230 left this month").
- Suggested command: `/impeccable delight`

**[P2] Generic validation message on Quick Add**
- Why it matters: "Enter an amount and pick a category" doesn't say which of the two is actually missing, forcing the user to re-scan the whole form.
- Fix: split into field-specific inline validation, or name the specific missing field in the SnackBar.
- Suggested command: `/impeccable clarify`

## Persona Red Flags

**Alex (Power User):** Gets last-used-category default and a fast custom keypad, but every entry lands with zero tactile/visual confirmation — no haptic anywhere in the reviewed code, and Save is a bare `GestureDetector` rather than a Material button with ripple feedback. No "repeat last expense" shortcut exists despite being the highest-value efficiency win for someone logging many similar entries. Reaching any category past the top 7 costs a full sheet round-trip.

**Casey (Distracted Mobile User):** The pinned keypad+save and keyboard-collapse genuinely serve one-thumb use. But the close (X) button offers no "discard changes?" prompt — exactly the interruption scenario (call, notification) where a habitual tap on X loses a real entry. The backdate picker also breaks the custom-UI flow entirely: `showDatePicker` opens a full native Material calendar dialog, a precision-demanding context switch dropped into an otherwise single-thumb-optimized screen.

## Minor Observations

- 42 hardcoded `fontSize:` literals across the 6 reviewed files instead of `Theme.of(context).textTheme` roles (`budget_setup_screen.dart` alone has 14) — doesn't break anything today, but bypasses the type-role system DESIGN.md documents and will drift if the scale ever changes centrally.
- `_BottomNav`'s `soon()` "coming soon" SnackBar helper (`home_screen.dart:286-288`) looks like dead code — every nav item now passes an explicit `onTap`.
- The FX rate-edit pill on Quick Add reuses `AppColors.accent` (amber) for a neutral "tap to edit rate" affordance — same color family as the budget-warning state elsewhere on the same screen, risking visual conflation between "neutral, tap to edit" and "warning."
- `budget_setup_screen.dart` hand-rolls a hairline pill button (`_AddBudgetButton`) that duplicates the stock `OutlinedButton` used two screens over for the same visual pattern — two code paths, one look.
- Semantics coverage, cross-checked against Assessment B's raw tappable-widget counts: the low raw ratios in `home_screen.dart` (0/3) and `category_manager_screen.dart` (1/3) are not real gaps — those are `IconButton(tooltip:)` instances, which already carry an accessible name without needing an explicit `Semantics` wrapper. Flagging this so the ratio isn't misread as an accessibility deficiency; it isn't one.

## Questions to Consider

1. If "fast entry beats completeness" is a stated product principle, why does Quick Add expose five simultaneous decision surfaces instead of defaulting date/trip silently and surfacing them only on demand?
2. The over-budget state is entirely pull-based (color + text, seen only when the app is opened) — for a user whose whole reason to use this app is staying under budget, is the absence of any push signal at the moment an expense crosses 100% a deliberate offline-first constraint, or an oversight worth revisiting?
3. Would a one-line post-save confirmation do more for the daily habit loop this app depends on than the current instant, silent pop-to-dashboard?
