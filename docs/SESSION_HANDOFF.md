# Muse — session handoff

Status note for picking the project up in a **local** Claude Code session
(this was built in a remote/cloud session through commit `41a12d2`).

## What Muse is
An AI makeup director iOS app (SwiftUI, iOS 17+). On-device face scan →
occasion + live-weather brief → AI-generated look options shown as a live
makeup try-on on the user's face → step-by-step guided tutorial with
makeup overlays on the live camera. Full product plan in
`docs/PRODUCT_PLAN.md`.

## How it's wired
- **Project:** XcodeGen (`Muse/project.yml`). The generated `Muse.xcodeproj`
  is gitignored. Signing team `447768FX9F` is baked into the target.
- **Run:** `cd Muse && xcodegen generate && open Muse.xcodeproj`, then Run.
  A git hook (`scripts/install-dev-hooks.sh`) auto-runs `xcodegen generate`
  after pulls — irrelevant once working locally.
- **AI:** `ClaudeLookDirector` calls the Claude Messages API
  (`claude-opus-4-8`) with structured outputs → `LookSet`. Falls back to
  `MockLookDirector` (3 rich canned looks) when no `Secrets.plist` key is
  present, so the whole flow demos without a key.
- **Camera features need a real device.** The simulator has no camera, so
  scan/preview/tutorial fall back to a sample profile + card UI + diagram.

## Key files
- `Muse/Muse/Services/FaceScanService.swift` — ARKit/Vision on-device scan.
- `Muse/Muse/Services/ClaudeLookDirector.swift` — Claude call + JSON schema.
- `Muse/Muse/Services/LookDirector.swift` — protocol + mock looks.
- `Muse/Muse/Views/Components/MakeupFilterView.swift` — Core Image live
  makeup try-on (skin smoothing + blended color + crisp lash pass). Tuning
  knobs: `previewAlpha`, `smoothed()`, `applyMakeup()` feather factors.
- `Muse/Muse/Views/Components/LiveTutorialFaceView.swift` — tutorial coach
  overlay + shared `zonePath` face-zone geometry (incl. the lash fan).
- `Muse/Muse/Views/LookOptionsView.swift` — live try-on selector + detail sheet.
- `Muse/Muse/Views/TutorialView.swift` — step-by-step tutorial.

## Recently done (most recent first)
- Lashes/mascara as a distinct zone with a fanned lash-stroke overlay,
  kept crisp in the preview via a dedicated low-feather pass.
- Sharper preview (1080p), more pigmented makeup, lighter skin smoothing.
- Core Image filtered try-on replacing flat ellipse overlays.
- Per-step `colorHex` + `finish` added to the look schema (and mocks).

## Open / next ideas
- Optional **simulator preview mode**: run the makeup pipeline on a bundled
  still selfie (`SampleFace` asset) so looks can be tuned without a device.
- On-device tuning of estimated zones (cheeks/forehead/lashes) and makeup
  opacity/blend per product.
- Phase 1+ in `docs/PRODUCT_PLAN.md` (undertone from camera, look history,
  AR 3D mesh projection, monetization).

## To continue locally
1. `git checkout claude/makeup-recommendation-app-uog70w && git pull` (last time).
2. Open Claude Code in this repo folder on your Mac.
3. Build/run from Xcode as above; edits now write straight to local files.
