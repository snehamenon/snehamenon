# Muse — Your AI Makeup Director

*Product strategy & build plan — v0.1, June 2026*

---

## 1. The one-liner

**Muse is turn-by-turn GPS for your face.** It reads your real facial geometry, factors in where you're going and what the weather will do to your makeup, has an AI makeup director compose looks made for *you*, and then coaches you through applying real products, step by step.

## 2. Why this isn't the millionth makeup app

Every incumbent (YouCam Makeup, L'Oréal ModiFace, Perfect365, Sephora Virtual Artist) is a **filter**: it paints fake pixels on your selfie so you can preview a finished face. None of them help you actually *get there* with the products on your shelf.

Muse inverts the model — it's a **coach, not a filter**:

| | Try-on apps | Muse |
|---|---|---|
| Core artifact | AR preview of a finished face | A guided application session |
| Face understanding | Texture mapping for overlays | Geometry → technique adaptation ("hooded eyes → lift the wing higher, work the crease above the fold") |
| Context | None | Occasion + **live weather** (humidity → matte over dewy; rain → waterproof mascara; UV → SPF primer; heat → setting spray first) |
| Output | A screenshot | A real face, done well, and a skill the user keeps |

**Weather-aware formulation guidance has no incumbent.** It's cheap to build (one free API call), instantly demoable ("it's 88% humidity today, so we're skipping the cream blush"), and genuinely useful — makeup failing by lunchtime is a universal pain point.

**Privacy is a feature, not a footnote:** the face image never leaves the phone. Apple's on-device vision stack measures the face; only abstract attributes ("heart-shaped face, hooded eyes, neutral undertone") are sent to the AI.

## 3. Who it's for

Primary: women 18–40 who own makeup and watch tutorials but find generic YouTube/TikTok tutorials don't translate to *their* face ("that wing works because she has almond eyes"). Secondary: beginners intimidated by makeup; occasion-driven users (wedding guest at 4pm, panic at 1pm).

## 4. The core loop

1. **Scan** — open the front camera; 3-second scan derives face shape, eye shape, lip fullness, cheekbone prominence (on-device, ARKit TrueDepth mesh where available, Vision landmarks elsewhere). User confirms/corrects traits and answers one undertone question (wrist-vein check).
2. **Intent** — pick an occasion chip (office, date night, wedding guest…), type the vibe in free text ("soft glam but I'm in a rush"), set a subtle↔bold slider. Local weather is fetched automatically.
3. **Direct** — Claude, acting as an editorial makeup director, returns 3–4 look cards: name, palette, *why it suits your specific features*, and weather adjustments.
4. **Guide** — pick a look → step-by-step tutorial. Each step: the **zone** (highlighted on a face diagram mapped from the scan), the **product type**, **shade guidance** for the user's undertone, the **technique**, and a pro tip. Finish with an after-selfie.

## 5. Architecture: Claude brain + Apple eyes

| Layer | Tech | Why |
|---|---|---|
| Perception | ARKit `ARFaceTrackingConfiguration` (TrueDepth mesh) with Vision `VNDetectFaceLandmarksRequest` fallback | Purpose-built, on-device, free, private |
| Weather | Open-Meteo (free, no key) + CoreLocation | Humidity, precipitation, UV, temperature |
| Creative direction | Claude (`claude-opus-4-8`) via the Messages API with **structured outputs** (JSON-schema-constrained responses decoded straight into Swift models) | LLMs carry deep MUA domain knowledge (face-shape theory, eye-shape technique, undertone color matching, formulation-vs-weather behavior). Taste is the product; taste scales with model capability. |
| App | SwiftUI, iOS 17+, MVVM | Slick native feel |

**Why not Apple's on-device Foundation Models as the brain?** The on-device model (~3B params, iOS 26+, iPhone 15 Pro+) produces noticeably more generic creative output and gates the market by device. The app's `LookDirector` protocol keeps the door open for an on-device tier later (offline mode, free quick re-rolls) without UI changes — a Phase 2+ option.

**Production note:** the prototype calls the Claude API directly with a local key for development. Before any external release, calls move behind a thin backend proxy (key custody, rate limiting, abuse control, per-user quotas).

## 6. Monetization — building a sustainable business

The strategic frame: **monetize the outcome (looking great, reliably), not the AI.** "AI looks" alone gets commoditized; the durable assets are the user's face profile, their makeup-bag inventory, their look history, and trust in the recommendations. Each of those compounds with use and is painful to rebuild elsewhere — that's the moat *and* the monetization surface.

### Revenue layers, in the order to ship them

1. **Subscription (Muse+) — the backbone.** Beauty apps monetize subscriptions well because usage is habitual and occasion-driven. Free tier: ~3 look generations/week + full tutorials (the magic must be free enough to hook). Muse+ at **$6.99–9.99/mo or ~$49/yr**: unlimited looks, look history, re-rolls, "my makeup bag" mode (looks composed only from products you own), seasonal trend capsules. Annual-plan emphasis smooths churn from the occasion-driven usage pattern.
2. **Affiliate commerce — the margin kicker.** Muse is uniquely positioned at the *highest-intent moment in beauty*: the user has been told "peach-leaning concealer, half a shade lighter, for your warm undertone" and is standing at the mirror without one. Deep-link the shade guidance to matched retailer SKUs (Amazon/Sephora/Ulta affiliate programs pay roughly 5–10% on beauty). This is contextual and genuinely helpful, so it strengthens rather than erodes trust — as long as recommendations stay merit-ranked, never pay-ranked.
3. **Brand capsules — later, carefully.** Sponsored look collections ("the Glossier festival capsule"), clearly labeled, only after organic trust is established. Never let sponsorship touch the core recommendation engine; the moment users suspect the AI is shilling, the product is dead.

### Unit economics sanity check

- **Variable cost:** a look generation is roughly 1.5K input + 3–4K output tokens → ~$0.10–0.15 on Opus-tier pricing; a Sonnet/Haiku tier for free users and re-rolls cuts that ~5–10×. Caching by (profile, occasion, weather band) cuts it further. Call it **$0.50–1.50/month for an active subscriber** — under 15% of subscription price. Healthy.
- **Free-tier exposure is capped** by the 3/week limit and cheap-model routing; worst case ~$0.30/month per free user.
- **LTV math to watch:** beauty subscription benchmarks suggest 6–12 month median retention; at $7/mo that's $40–80 LTV before affiliate. Affiliate adds $5–20/yr for engaged users (beauty AOV ~$30–60, a few attributed purchases/year). CAC via organic short-form video (before/after + "the app told me my wing angle was wrong" content is natively viral) should stay well under $10.

### Sequencing

- **Phases 0–1: monetize nothing.** Optimize activation and the magic-moment rate; instrument everything.
- **Phase 3 (launch): Muse+ paywall + affiliate links** in tutorials. Two layers from day one — subscriptions for the committed, affiliate for everyone.
- **Year 1+: the inventory flywheel.** "My makeup bag" makes the app dramatically more useful (looks from what you own), feeds affiliate precision (it knows what you're missing), and raises switching costs — every product scanned in deepens lock-in.
- **Optional B2B sidecar:** the look-direction engine (face attributes + context → structured looks) is licensable to retailers for in-store/online shade-matching consultations — same API, different buyer, no consumer-trust risk.

### What *not* to do

Ads (kills the premium mirror-moment), selling face data (kills the privacy story that justifies the scan), pay-ranked recommendations (kills trust, which is the product), and aggressive paywalling of the first magic moment (kills virality before it starts).

## 7. Success metrics

- Activation: % of installs completing scan → first look generated.
- Magic-moment rate: % who start a tutorial within first session.
- Completion: median steps completed per tutorial.
- Retention: weekly look generations per active user; occasion-driven re-opens.
- Quality: thumbs-up rate on generated looks (feeds prompt iteration + MUA review).

## 8. Risks & honest caveats

- **AI is not a licensed MUA.** Output is "plausible expert" quality. Mitigation: MUA review of prompt/output before launch; never make skin-medical claims; feedback loop on looks.
- **Scan heuristics are approximate** in v0 (geometry ratios → trait labels). Mitigation: user-correctable traits at scan summary (also great training signal later).
- **Per-look API cost** (a few cents on Opus). Mitigation: cache by (profile, intent, weather-band); Sonnet/Haiku tiering for re-rolls; subscription covers heavy use.
- **App Store camera/AI policy**: clear consent copy, on-device face processing disclosure (already our architecture).

## 9. Roadmap — built with Claude Code

Estimates assume iterative Claude Code sessions with the developer testing on-device between sessions.

| Phase | Scope | Estimate |
|---|---|---|
| **0 — Prototype (this session)** | Product plan + working SwiftUI app: scan → intent+weather → Claude-generated looks (structured output) → guided tutorial with zone diagrams; mock mode without a key | 1 session |
| **1 — MVP polish** | On-device ARKit tuning with real-device feedback, undertone estimation from camera frames, animations/haptics/empty-states, look history, prompt iteration with MUA review | ~1–2 weeks |
| **2 — Differentiators** | Live AR application-zone projection on the actual face mesh (the "GPS" moment), shade matching (Delta-E vs. product DB), "my makeup bag" inventory, Apple on-device tier for offline re-rolls | ~2–4 weeks |
| **3 — Launch** | Backend proxy + auth, TestFlight beta, before/after share cards, paywall, App Store submission | ~3–4 weeks |

Total: a credible TestFlight beta in roughly **6–8 weeks** of part-time Claude Code-driven development; App Store submission within ~10.

## 10. What exists today (Phase 0 deliverable)

See [`Muse/README.md`](../Muse/README.md) — a build-ready Xcode project (XcodeGen) implementing the full core loop, with mock mode so the flow demos without an API key.
