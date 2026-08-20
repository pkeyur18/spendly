---
name: Spendly
description: Offline-first personal expense tracker for iOS & Android
colors:
  ledger-indigo: "#6366F1"
  indigo-soft: "#818CF8"
  indigo-deep: "#4F46E5"
  amber-accent: "#F59E0B"
  signal-pink: "#EC4899"
  teal: "#14B8A6"
  alert-red: "#EF4444"
  paper-light: "#F5F5F7"
  card-light: "#FFFFFF"
  ink-light: "#14141C"
  ink-light-dim: "#6B6B7B"
  hairline-light: "#ECECF1"
  void-dark: "#0B0B12"
  card-dark: "#16161F"
  card-dark-2: "#1D1D28"
  ink-dark: "#F4F4F8"
  ink-dark-dim: "#8B8B9C"
  hairline-dark: "#26262F"
  nav-plum-light: "#1B1533"
  nav-plum-dark: "#201A3D"
typography:
  display:
    fontFamily: "Sora"
    fontSize: "36px"
    fontWeight: 700
    letterSpacing: "-0.5px"
  headline:
    fontFamily: "Sora"
    fontSize: "20px"
    fontWeight: 600
    letterSpacing: "-0.5px"
  title:
    fontFamily: "Sora"
    fontSize: "18px"
    fontWeight: 600
    letterSpacing: "-0.5px"
  body:
    fontFamily: "Inter"
    fontSize: "15px"
    fontWeight: 400
  label:
    fontFamily: "Inter"
    fontSize: "11px"
    fontWeight: 500
rounded:
  chip: "100px"
  card: "22px"
  hero: "26px"
  button: "16px"
  icon: "13px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "24px"
components:
  button-primary:
    backgroundColor: "{colors.ledger-indigo}"
    textColor: "#FFFFFF"
    typography: "{typography.title}"
    rounded: "{rounded.button}"
    padding: "16px 24px"
  card:
    backgroundColor: "{colors.card-light}"
    rounded: "{rounded.card}"
    padding: "20px"
  chip-selected:
    backgroundColor: "{colors.ledger-indigo}"
    textColor: "#FFFFFF"
    rounded: "{rounded.chip}"
  chip-ghost:
    backgroundColor: "{colors.card-light}"
    textColor: "{colors.ink-light-dim}"
    rounded: "{rounded.chip}"
---

# Design System: Spendly

## Overview

**Creative North Star: "The Midnight Ledger"**

Spendly reads as a well-kept ledger under lamp light: dark, confident surfaces — near-black indigo (`#0B0B12`) in dark mode, a cool off-white (`#F5F5F7`) in light — punctuated by exactly one recurring warm signature, the indigo→pink brand gradient, reserved for the moments that matter (the hero total, the primary save action, the FAB). Everything else stays quiet: flat neutral cards with hairline borders, Sora for numbers and section titles, Inter for everything read at length. The bottom navigation breaks from both the card surface and the background entirely into its own deep indigo-plum (`#1B1533` / `#201A3D`), a small deliberate departure that gives the app a "home base" distinct from its content screens.

The mood serves the product's actual user: someone actively trying to stay under budget, not idly browsing a ledger. Gradient and shadow are earned by significance (money owed, money saved, the one action that commits an entry) rather than spent everywhere.

**Key Characteristics:**
- One brand gradient (indigo → pink), used sparingly on hero cards, the primary CTA, and the FAB — never as decoration.
- Flat, hairline-bordered cards at rest; the gradient hero is the one deliberately "lifted" surface per screen.
- Sora (display/numbers) paired with Inter (body/labels) — a confident geometric face over a quiet workhorse.
- A dedicated navy-plum bottom nav surface, distinct from card and background.
- Full light/dark parity — every token has a light and dark value, not a dark-mode afterthought.

## Colors

Dark, confident neutrals with one warm gradient signature spent only where money moves.

### Primary
- **Ledger Indigo** (#6366F1): the single brand identity color — icon mark, links, selected states, primary text accents, seed color for Material's `ColorScheme.fromSeed`.
- **Indigo Deep** (#4F46E5): the dark end of both gradients; also `colorScheme.primary`'s darker anchor.
- **Indigo Soft** (#818CF8): lighter brand tint, used sparingly for hover/soft states.

### Secondary
- **Signal Pink** (#EC4899): the warm end of the brand gradient (paired with indigo); also `colorScheme.secondary`. Never used solo as a flat fill — it exists to gradient against indigo.
- **Amber Accent** (#F59E0B): budget-warning threshold color (80% of budget) and the "over budget" recap state.
- **Alert Red** (#EF4444): over-budget / destructive state (100%+ of budget, delete actions, `colorScheme.error`).

### Tertiary
- **Teal** (#14B8A6): reserved accent, available in the curated category/tag swatch palette (18-swatch picker) but not part of the core UI chrome.

### Neutral
- **Paper** (light #F5F5F7 / dark void #0B0B12): `scaffoldBackgroundColor`.
- **Card** (light #FFFFFF / dark #16161F, secondary dark surface #1D1D28): the base surface for `AppCard` and all content containers.
- **Ink** (light #14141C / dark #F4F4F8): primary text.
- **Ink Dim** (light #6B6B7B / dark #8B8B9C): secondary/caption text — section-title trailing links, dim body text, labels.
- **Hairline** (light #ECECF1 / dark #26262F): the border on every flat card; never a shadow-only edge.
- **Nav Plum** (light #1B1533 / dark #201A3D): the bottom navigation's own surface — deliberately distinct from Card, not a darker/lighter step of it.

### Named Rules
**The One Gradient Rule.** The brand gradient (indigo → pink) appears in exactly three places per screen at most: the month-total hero, the primary save/CTA button, and the FAB ring. It is never used as a section background, a chip fill, or general decoration — its rarity is what makes the hero card read as important.

## Typography

**Display Font:** Sora (with system sans-serif fallback)
**Body Font:** Inter (with system sans-serif fallback)

**Character:** Sora's geometric, slightly condensed forms carry every number and section title with quiet confidence; Inter recedes underneath for anything read at length (transaction notes, dialog copy, labels). The pairing never mixes mid-sentence — a given text run is one or the other.

### Hierarchy
- **Display** (700, 36px, -0.5 letter-spacing, Sora): the single largest number on screen — currently unused for a dedicated display moment beyond the type scale's ceiling; reserved for a future large money figure.
- **Headline** (600, 20px, -0.5 letter-spacing, Sora): the home-screen greeting ("Good morning, [Name]").
- **Title** (600, 18px, Sora): app-bar titles, dialog titles (700 weight), section headers via `titleMedium` (16px).
- **Body** (400, 14–15px, Inter): transaction rows, dialog content, form fields.
- **Label** (500, 11px, Inter, dim color): captions, chip labels, nav item labels.

### Named Rules
**The Sora-For-Money Rule.** Any text presenting a currency amount or a section/screen-level heading is Sora. Anything the user reads rather than scans is Inter. Never render a monetary figure in Inter.

## Layout

Single-column, edge-padded (16–20px horizontal) scrolling screens; no multi-column grid. Section rhythm follows the spacing scale strictly: 24px above a section title, 12px below it, before content begins. Cards stack with consistent vertical spacing rather than being packed edge-to-edge. The FAB is center-docked over the bottom nav (`FloatingActionButtonLocation.centerDocked`), notched by a 4px ring in the scaffold background color so it visually punches through the nav bar rather than sitting on top of it.

## Elevation & Depth

Hybrid, intentional: cards are flat at rest (hairline border + a whisper shadow — 10px blur, 4% black, 2px vertical offset — just enough to lift off the background, not enough to read as "elevated"). Exactly one surface per screen is deliberately heavier: the gradient hero card (30px blur, 35% brand-indigo-tinted shadow, 12px offset) and the primary CTA button (20px blur, 40% indigo, 8px offset). The FAB carries no independent shadow of its own — its 4px background-color ring against the gradient fill is what separates it from the nav bar beneath it.

### Shadow Vocabulary
- **Card whisper** (`0 2px 10px rgba(0,0,0,0.04)`): default state for every `AppCard` and content container.
- **Hero lift** (`0 12px 30px rgba(99,102,241,0.35)`): the month-total hero card only.
- **CTA lift** (`0 8px 20px rgba(99,102,241,0.4)`): the primary gradient button (Save expense, Save changes).

### Named Rules
**The One Lift Per Screen Rule.** A screen earns exactly one heavier, colored shadow — its hero or its primary CTA, never both loudly at once, and never a second competing lifted card.

## Shapes

Generously rounded throughout, scaled to the surface's importance: chips and pills are fully stadium-shaped (100px), the hero card is the softest rectangle (26px), standard cards and sheets sit at 22px, buttons at 16px, small icon containers at 13px, and the brand icon mark and FAB are true circles. No sharp corners appear anywhere in the system; the smallest radius in active use is 13px.

## Components

Confident and tactile: bold gradient CTAs, generous radius, soft depth — built for fast, satisfying one-thumb entry, not for a dense information-dashboard feel.

### Buttons
- **Shape:** 16px radius (`AppRadius.button`), except the FAB which is a true circle.
- **Primary:** brand gradient fill (indigo deep → indigo → pink, 135°), white Sora 15px/600 label, 16px vertical padding, CTA-lift shadow. Used for the single primary commit action per screen (Save expense, Save changes).
- **FAB:** brand gradient circle, white icon, zero elevation of its own, wrapped in a 4px scaffold-background ring so it reads as "docked into" the nav bar rather than floating over it.
- **Icon buttons (app bar, nav):** transparent by default, `Colors.white.withValues(alpha: 0.08)` fill when active/selected, no border.
- **Secondary / Ghost:** not gradient-filled — a card-colored `ActionChip` with a hairline stadium border (`StadiumBorder` + hairline color) is the system's ghost-button equivalent.

### Chips
- **Selected filter chip:** indigo fill, white Sora-weight (600) label, stadium shape.
- **Ghost / overflow chip** ("+N more"): card-colored background, hairline stadium border, no fill — used for overflow/expand affordances, never for a primary action.

### Cards / Containers
- **Corner Style:** 22px radius (`AppCard`), 26px for the hero variant.
- **Background:** Card neutral (light #FFFFFF / dark #16161F).
- **Shadow Strategy:** Card whisper at rest (see Elevation & Depth); hero variant uses Hero lift instead.
- **Border:** 1px hairline, always present even where a shadow also exists — the border, not the shadow, is what defines the card's edge.
- **Internal Padding:** 20px (`AppSpacing.xl`) default.

### Navigation
- **Style:** dedicated Nav Plum surface (not a card-colored bar), five compact (40×40) icon buttons, 0.08-alpha white fill on the active item, transparent otherwise, tooltip = label. No text labels shown by default — icon-only with semantic tooltips.
- **Typography:** N/A (icon-only); any nav copy elsewhere uses Label (11px/500 Inter).

## Do's and Don'ts

### Do:
- **Do** reserve the brand gradient for the month-total hero, the primary save CTA, and the FAB — nowhere else.
- **Do** give every card a hairline border regardless of whether it also carries a shadow.
- **Do** render every monetary figure in Sora, never Inter (The Sora-For-Money Rule).
- **Do** keep the bottom nav on its own Nav Plum surface, distinct from Card and Background.
- **Do** define both a light and a dark value for every new token — this system has no dark-mode afterthoughts.

### Don't:
- **Don't** add a second heavy colored shadow to a screen that already has a hero or lifted CTA (The One Lift Per Screen Rule).
- **Don't** introduce Cupertino-styled controls to differentiate iOS — the incumbent system is one unified Material-based language across iOS and Android by deliberate choice (see PRODUCT.md Capabilities and Constraints); route any platform-conformance work through `/impeccable adapt` or `/impeccable audit` rather than silently forking the look.
- **Don't** use Teal, or any swatch-palette color beyond Indigo/Pink/Amber/Red, as a core UI chrome color — those 18 swatches are for user-chosen category/tag colors only, not system chrome.
- **Don't** fill a chip solid unless it represents an active/selected filter; unselected and overflow chips stay ghost (card background + hairline border).
