# Muse — iOS prototype

SwiftUI app implementing the full core loop: **face scan → brief (occasion + vibe + live weather) → AI-directed look cards → step-by-step guided tutorial**.

## Build & run (on a Mac)

```bash
brew install xcodegen          # one-time
cd Muse
xcodegen generate              # creates Muse.xcodeproj from project.yml
open Muse.xcodeproj
```

In Xcode: select the `Muse` target → *Signing & Capabilities* → pick your team, then run.

- **On a real iPhone** (recommended): live camera scan — TrueDepth face mesh on Face ID devices, Vision landmarks otherwise.
- **On the simulator**: no camera, so the scan screen offers a one-tap **sample face profile**; the rest of the flow works fully.

> No XcodeGen? Create a new iOS App project named `Muse` in Xcode, delete its template sources, drag the `Muse/Muse` folder in, and add the two Info.plist keys listed in `project.yml` (`NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`).

## Live AI looks (optional — mock mode works without this)

The app runs in **demo mode** out of the box, with rich canned looks. To get real Claude-directed looks:

```bash
cp Secrets.plist.example Muse/Resources/Secrets.plist
# edit Muse/Resources/Secrets.plist and paste your Anthropic API key
xcodegen generate              # re-generate so the plist joins the bundle
```

`Secrets.plist` is gitignored. **Prototype only:** a shipping app must never embed an API key — route calls through a backend proxy (see `docs/PRODUCT_PLAN.md`, Phase 3).

## How it works

| Piece | File | Notes |
|---|---|---|
| Face scan | `Muse/Services/FaceScanService.swift` | ARKit TrueDepth mesh (band-width ratios) or Vision landmarks; all on-device. Trait labels are heuristics and **user-correctable** on the summary card. |
| Weather | `Muse/Services/WeatherService.swift` | CoreLocation + Open-Meteo (free, no key): humidity, precipitation, UV, temperature. |
| Look direction | `Muse/Services/ClaudeLookDirector.swift` | Claude Messages API (`claude-opus-4-8`) with **structured outputs** — the response is schema-guaranteed JSON decoded straight into `LookSet`. The prompt carries only abstract face attributes, never images. |
| Mock mode | `Muse/Services/LookDirector.swift` | `MockLookDirector` returns 3 full looks; used automatically when no key is configured, and offered as a fallback if the API call fails. |
| Tutorial | `Muse/Views/TutorialView.swift` + `FaceZoneOverlay` | Step cards with product/shade/technique/pro-tip and a face diagram highlighting the active zone. Live AR zone projection is the Phase 2 headline. |

## Known prototype limitations

- Scan-derived trait labels are rough; correcting them on the summary card is part of the intended UX (and future training signal).
- The tutorial face diagram is stylized/proportional, not yet projected onto your live face mesh.
- Undertone is self-reported (wrist-vein check) — camera-based estimation lands in Phase 1.
- Look generation is a single non-streaming request and can take ~1–2 minutes on Opus; a streaming/progress UX is a fast follow.
