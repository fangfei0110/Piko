# Piko App Icon

## Little Lookout

Piko is a compact, local system observer, not an aggressive cleaner or a speed booster. The resting bird expresses quiet alertness and gives the app a recognizable identity beyond its first letter. Its broad silhouette stays readable in the Dock; a jade wing and small apricot beak give it character without requiring text or tiny interface details. Shallow satin lighting replaces the old inflated letterform.

`AppIcon.icon/Assets/Piko.png` is the opaque, full-bleed 1254-by-1254 source, created with the built-in image generation tool on 2026-09-06. The source has no rounded-square mask or transparent perimeter. The menu-bar template symbol and all UI palettes are unchanged.

`Scripts/generate-icon.swift` compiles `AppIcon.icon` with Xcode's `actool`, shipping both `Assets.car` (native icon stack and appearance variants) and `AppIcon.icns` (legacy fallback). `CFBundleIconName` and `CFBundleIconFile` both reference `AppIcon`. Do not replace this with ICNS-only packaging or bake a second rounded tile into the artwork: that produced an inset icon on a white system plate in the user's macOS 26 Dock.

Apple documents the format and automatic legacy generation in [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).

## Generation Prompt

Use case: logo-brand.
Create one finished macOS app-icon artwork for Piko, a small, quiet local system monitor that watches CPU, memory and disk without interrupting work. A radically new identity, not a lettermark: "the little lookout".
Design a beautiful original abstract kingfisher-like bird at rest, facing right, as a compact sculptural emblem. Not a flying Twitter bird, not an owl, not a robot. Use only a few precisely composed broad shapes. A unified deep petrol-teal silhouette forms the round head, short upright chest and gently tapered body. A single elegant pale-jade wing inset sweeps diagonally down the body; its lower edge resolves into three subtle broad feather steps, suggesting discrete readings without drawing a bar chart. One small ivory eye with a dark pupil expresses quiet alertness, not huge cartoon eyes. A short restrained apricot-orange beak points right, giving a single memorable warm focal point. A very short broad tail balances the left-bottom silhouette; no skinny feet, no branch.
Aesthetic: refined independent Mac utility, thoughtfully designed tactile object, crisp graphic silhouette first, soft satin enamel second. Broad mostly flat color faces, very subtle shallow edge lighting and a short soft contact shadow. NOT glossy plastic, not a plush toy, no thick extrusion, no photorealistic feathers or realistic bird detail. Use calm strong proportions and warm character without becoming childish. The bird should be clean enough to identify instantly at 32 pixels and feel carefully made at 256 pixels.
Composition: front-facing flat orthographic artwork, subject centered optically at about 58% canvas height and 54% canvas width, plenty of breathing room. Full-bleed OPAQUE square 1024x1024 canvas, every edge and corner filled with a very pale cool celadon color (#E2EEEA) with only subtle natural illumination, not a bright gradient. The OS supplies the app icon's rounded mask: DO NOT draw any rounded-square tile, outside border, extra container, white frame, inset plate, exterior shadow or transparent padding. The bird sits directly in the full-bleed celadon field.
Palette: deep petrol #123D3C body, muted jade #78C1AE wing, small soft apricot #EFAB6B beak, tiny ivory eye. Keep navy/electric blue and purple completely out.
No text, no P, no wordmark, no caption, no watermark, no grid, no charts, no heartbeat, no circuitry, no magnifying glass, no multicolor decoration. One icon only, not a concept board or device mockup.
