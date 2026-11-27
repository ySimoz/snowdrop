# 05 Greenfield Android Architecture & Two-Layer Liquid Glass Spec

Clean modular architecture under `android-next/app/src/main/java/com/snowdrop/app/`.

## 1. Layering

```
com.snowdrop.app
├── domain/        # Immutable state models & formatting (Models.kt)
├── data/          # SnowdropBackend interface, LiveSnowdropBackend (Core FFI), SnowdropStore (StateFlow)
├── service/       # TransferService (FGS + onTimeout), TransferActionReceiver
└── ui/
    ├── theme/     # Light/Dark mineral-slate ColorScheme, SnowdropPalette, Typography (tnum)
    ├── components/# SnowdropGlassSurface (Haze API 31+ blur + API 26–30 frosted fallback), StatusPill, PeerRow
    ├── screens/   # MainShellScreen, Devices, Transfers, Trusted, Settings
    └── ...        # MainActivity, ShareActivity
```

## 2. Android Liquid Glass (Two-Layer System)

- **Layer 1 (Content Canvas)**:
  - Solid neutral mineral-slate Material 3 surface ramp (`#F8FAFC` / `#FFFFFF` light, `#0E1116` / `#161B22` dark).
  - Hairline 1.dp borders at 8% foreground opacity (`onBackground.copy(alpha = 0.08f)`).
  - 4.dp spacing scale (`4`, `8`, `12`, `16`, `24`), weights `400`–`500` (`600` max), sentence case labels, `Icons.Outlined.*` line icons, tabular figures (`fontFeatureSettings = "tnum"`), zero trailing ellipses on action buttons.
- **Layer 2 (Floating Chrome)**:
  - `SnowdropGlassSurface` backed by `dev.chrisbanes.haze` (`HazeState`, `Modifier.haze` on Layer 1 container, `Modifier.hazeChild` on Layer 2 floating chrome).
  - Uses real-time `RenderEffect` blur + tint on API 31+ (`HazeDefaults.style(...)`) and translucent frosted scrim fallback on API 26–30.
  - Neutral vertical specular rim highlight (`Brush.verticalGradient` white opacity only — no hue gradients, no colored glows).
  - Strictly limited to floating chrome: floating bottom navigation capsule, floating staged-files dock, floating approval HUD, floating error capsule, and `ShareActivity` sheet. Never applied to scrolling lists or stacked glass-on-glass.
