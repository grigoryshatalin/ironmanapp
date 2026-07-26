# ICON_SPEC.md — Endurance

App icon specification and launch experience. The goal is a **quiet, original,
first‑party‑feeling** mark: minimal, legible at small sizes, no text, no Apple
logo, no imitation of an existing Apple app icon, and none of the generic
AI‑gradient look. Color stays restrained and secondary to form.

---

## 1. Concept direction

Three concrete concepts, in priority order. All are single‑mark, mostly‑flat,
one‑ or two‑color designs on a calm background.

### Concept A — "Continuous line" (recommended)
One unbroken stroke that reads as forward motion: a gentle rising curve that
subtly changes character across its length (a shallow wave → a smooth arc → a
slight kick up at the end), abstractly evoking **swim → bike → run** without
literal icons. A single weight, rounded caps, centered with generous margin.
- Background: a soft, near‑flat vertical wash from a slightly deeper to a
  slightly lighter tone of one calm color (e.g. a muted teal‑blue), *not* a
  saturated neon gradient — keep the two stops within a few percent luminance so
  it reads as flat at a glance.
- Stroke: white (light mode) / near‑white; the whole mark works as a pure
  two‑tone shape.
- Why it wins: instantly readable at 40px, distinctly "endurance," and it scales
  to a crisp monochrome/tinted variant trivially (it is literally one path).

### Concept B — "Three arcs"
Three concentric, evenly spaced arc segments sweeping upward‑right — three
disciplines, one direction, one finish. Equal stroke weights, one accent color,
flat background. Slightly more literal than A; still calm.

### Concept C — "Horizon to summit"
A single thin baseline (the horizon / water line) with one rising line that
crests to a small rounded peak (the arc of a long day's effort, finishing on the
run). Two‑tone, flat. Evokes the journey/finish without a mountain cliché if the
peak is kept gentle and abstract.

**Shared rules**
- Motif fills ~60–70% of the safe region; never touches the edges.
- One accent color max, plus a neutral. No text, no numerals, no photoreal
  texture, no drop shadows, no bevels.
- Must survive being reduced to a single flat silhouette (test the tinted
  variant early).

---

## 2. Asset catalog (Xcode 26 / iOS 26)

Modern iOS uses a **single 1024×1024** source image; the system scales all
sizes and applies the corner mask. Xcode 26 also supports **light / dark /
tinted** appearance variants in one `AppIcon` set.

Files:

```
Applications/iOS/Resources/Assets.xcassets/
  AppIcon.appiconset/
    Contents.json
    AppIcon-1024.png          # light (and default)
    AppIcon-1024-Dark.png     # optional dark variant
    AppIcon-1024-Tinted.png   # optional tinted (grayscale) variant
```

`Contents.json` (single‑size, appearance‑aware form):

```json
{
  "images": [
    { "filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" },
    { "filename": "AppIcon-1024-Dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
      "appearances": [{ "appearance": "luminosity", "value": "dark" }] },
    { "filename": "AppIcon-1024-Tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
      "appearances": [{ "appearance": "luminosity", "value": "tinted" }] }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

In `project.yml`, set `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. Provide the
1024 light image at minimum; dark/tinted are optional but recommended.

Requirements for the 1024 master: PNG, no alpha (fully opaque), sRGB, exactly
1024×1024, **no pre‑applied rounded corners** (the system masks it). The
tinted/dark variants may include transparency per Apple's appearance‑variant
guidance; keep the mark on a solid fill for the primary.

---

## 3. Placeholder (build now, refine later)

We cannot render final artwork in this environment, and we must not ship
trademarked or third‑party art. Create a simple **original vector placeholder**
so the project builds and installs:

Option 1 — vector by hand (recommended): draw Concept A as one path in any
vector tool (or SwiftUI `Canvas`/`Shape` exported), on a flat teal‑blue
background, export a 1024×1024 opaque PNG as `AppIcon-1024.png`.

Option 2 — quick programmatic placeholder: a tiny script/Playground that draws a
rounded rising stroke on a solid background into a 1024×1024 `CGContext` and
writes a PNG. (An SF Symbol such as `figure.mixed.cardio` may be used *only* as a
scaffolding placeholder during development — replace it before any external
distribution, since SF Symbols are not licensed for use as app icons.)

Drop the resulting PNG at
`Applications/iOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`.
Until then, Xcode shows a "missing app icon" warning only — the app still builds
and runs in the Simulator.

---

## 4. Grid, safe area, rendering

- Design on the standard 1024 grid; keep all meaningful content within a ~10%
  inset on every side so nothing clips after the system corner mask.
- Verify legibility at **40px, 60px, 120px** (Settings, Spotlight, Home Screen)
  and as the monochrome tinted variant — if the mark relies on the gradient or
  two colors to be recognizable, simplify.
- Do not bake shadows, glyphs, or borders; let the system handle the squircle,
  specular highlight, and shadow.

---

## 5. Launch experience

Use the standard **modern launch screen** — a blank screen matching the app's
first background color, **no prolonged branded splash** (brief §25). Configure it
in Info.plist with the `UILaunchScreen` dictionary rather than a storyboard:

```xml
<key>UILaunchScreen</key>
<dict>
    <key>UIColorName</key>
    <string>LaunchBackground</string>
</dict>
```

Define a `LaunchBackground` color in the asset catalog matching the Today
screen's grouped background (light/dark variants), so launch → first frame is
seamless. Do not add a logo, spinner, or animation to the launch screen. In
`project.yml`, ensure no `UILaunchStoryboardName` is set so the dictionary form
is used.
