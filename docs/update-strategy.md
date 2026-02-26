# Update Strategy (Offline-First)

This document compares update delivery options for Chronicle while preserving the offline-first privacy promise.

## Constraints

- Chronicle should not require cloud account/login.
- User data must remain local.
- Update checks should be user-initiated by default.
- Release artifacts must be verifiable and reproducible.

## Options Comparison

## Option A: GitHub Releases only (manual)

- Flow: user opens Releases page, downloads DMG, drags app to `/Applications`.
- Pros:
  - Simple and transparent.
  - No background updater process.
  - Lowest integration risk.
- Cons:
  - Manual steps for every update.
  - No in-app delta patching.

## Option B: Sparkle (automatic appcast checks)

- Flow: app periodically checks appcast, downloads and applies update.
- Pros:
  - Better UX (in-app updates).
  - Supports signatures and versioned feeds.
- Cons:
  - Adds network behavior in app runtime.
  - Higher release pipeline complexity (appcast + signing + hosting).
  - More privacy communication burden.

## Option C: Sparkle in manual-check mode

- Flow: app checks only when user clicks "Check for Updates".
- Pros:
  - Better UX than pure GitHub manual flow.
  - Keeps checks user-initiated.
  - Retains signed update metadata path.
- Cons:
  - Still requires appcast infrastructure and signing workflow.
  - Additional maintenance overhead.

## Recommended Path

Current recommendation:

1. Keep Option A as default shipping path (already implemented with "Check for Updates" + "Open Releases Page" actions that open GitHub URLs).
2. Keep release signing/notarization + checksum verification documented in release process.
3. Re-evaluate Option C after stable `v0.x` if update friction becomes a top user pain.

This keeps Chronicle aligned with the current offline-first product promise while preserving a future migration path to in-app updater UX.

## Decision Trigger To Revisit

Revisit update strategy if one of the following holds:

- A significant share of support requests are "stuck on old version".
- Critical fixes need faster adoption than manual update provides.
- The team has capacity to maintain signed appcast + QA matrix.

