# App icon surfaces and appearance following

The app icon lives on four surfaces. Knowing which source feeds which surface
is the prerequisite for touching anything icon-related.

| Surface | Source | Follows system appearance |
|---|---|---|
| Menu bar | `StatusIconRenderer` at render time | Yes |
| Dock (running) | `DockIconRenderer` / `AppIconController` | Yes (resolved per render) |
| Dock (not running), Finder, Launchpad, Spotlight | `Support/AppIcon.icon` → `Assets.car`, fallback `AppIcon.icns` | Yes on macOS 26+; flat fallback on 15–25 |
| DMG volume icon | `Support/AppIcon.png` | No (single design) |

## Layered icon (macOS 26+)

`Support/AppIcon.icon` is an Icon Composer–style package: `icon.json` plus
`Assets/light.png` and `Assets/dark.png`. Both layers are 1024×1024 transparent
PNGs holding the same approved glyph geometry as the flat icon — the
`DockIconGlyphLayout` frame drawn by `StatusIconRenderer` — with no background
or border. Only the neutral ink differs: the light layer draws dark ink, the
dark layer draws white ink; charging green and Bluetooth blue stay colored.

`icon.json` declares a system `automatic-gradient` fill and switches layers
with **`hidden-specializations`**:

- `Light` is hidden for the `dark` appearance.
- `Dark` is hidden for the `light` and `tinted` appearances.

The system glass fill adapts to light, dark, clear, and tinted icon styles on
its own, so no per-style artwork is needed.

### Why the 1.3.3 attempt failed

Two separate mechanisms were confused:

1. **`AppIcon.appiconset` with a `luminosity: dark` appearance is silently
   dropped** by actool for macOS app icons — verified with Xcode 27.2 (also
   with byte-distinct light/dark images); the compiled catalog contains no
   dark rendition at all. This key works for iOS, not for macOS app icons.
2. The hand-written `.icon` experiments used **`is-hidden-specializations`**,
   a key name actool ignores silently. The correct key — as shipped by
   FaceGate (`FaceGate-Mac-main`) and Sparkle's `AppIcon.icon` — is
   **`hidden-specializations`** (no `is-` prefix). With it, actool emits
   appearance-aware `IconImageStack` renditions.

## Build pipeline

`scripts/build-app.sh` ships both representations:

1. `Support/AppIcon.png` → `sips`/`iconutil` → `Contents/Resources/AppIcon.icns`
   (every size up to 1024px; referenced by `CFBundleIconFile`).
2. `Support/AppIcon.icon` → `actool` → `Contents/Resources/Assets.car`
   (referenced by `CFBundleIconName`). The script fails the build unless the
   compiled car contains `IconImageStack` renditions, so a silently dropped
   specialization cannot ship.

`Support/Info.plist` declares both keys; actool's own small-size icns output is
discarded in favor of the full-size iconutil one.

On macOS 26+, LaunchServices resolves `CFBundleIconName` first, renders the
layered icon, and follows the system appearance (verified on macOS 27.2: the
resolved Dock/Finder icon switches between the light and dark stacks; under a
dark system the resolved background is a system glass gradient, not the flat
`#151517` square). On macOS 15–25 the flat icon is the fallback.

The layer PNGs are regenerated with:

```bash
STATUS_TRIO_APP_ICON_LAYERS_DIR="Support/AppIcon.icon/Assets" \
  swift test --filter AppIconPreviewTests
```

The flat dark `Support/AppIcon.png` stays the approved-preview source of truth
for the icns fallback and is byte-pinned by `AppIconPreviewTests`.

## Running Dock icon

The Dock tile while the app runs is drawn live by `DockIconRenderer` (it shows
real battery, Wi-Fi, and volume state), so it cannot reuse the layered system
icon. Two properties keep it visually consistent with that icon:

- **Footprint.** The rounded square is drawn at 858px on the 1024px canvas
  (≈83.8%, a ~83px margin), matching the system glass icon's own squircle —
  measured from `NSWorkspace.icon(forFile:)` of both Calculator and this app's
  layered icon, which resolve to the same 858px body. The earlier 896px body
  (87.5%) rendered the running tile visibly larger than its neighbours.
  `DockIconRendererTests.testDockIconBodyMatchesTheStandardMacOSFootprint`
  pins the margin against regression.
- **Live appearance switch.** `SystemIconAppearanceMonitor` now tracks the
  resolved light/dark appearance *in addition to* the icon-style preference
  string, and re-reads it on the distributed
  `AppleInterfaceThemeChangedNotification`, so a system appearance toggle
  re-renders the Dock tile immediately instead of waiting for a window
  reopen or the 2-second poll. Replacing `applicationIconImage` is a
  non-template bitmap, so this has none of the render-loop risk that once
  forced the menu bar off `NSApp.effectiveAppearance`.

## Verification

```bash
# The car must carry the appearance-aware stacks:
xcrun assetutil --info dist/StatusTrio.app/Contents/Resources/Assets.car \
  | grep -c IconImageStack   # expect 3 (aqua, dark, tintable)

# What the system actually resolves for the bundle (follows the running
# system's appearance on macOS 26+):
NSWorkspace.shared.icon(forFile: <path-to-app>)
```

`NSWorkspace.icon(forFile:)` does not honor an in-process appearance override;
it renders with the system appearance, so compare across system appearance
changes rather than by setting `NSApplication.appearance`.
