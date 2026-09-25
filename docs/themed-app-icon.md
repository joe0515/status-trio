# Themed app icon

Status Trio ships three icon surfaces, and macOS asks a different one of each:

| Surface | Source | Follows the system's icon style |
| --- | --- | --- |
| Menu bar | `StatusIconRenderer`, drawn per appearance at render time | yes |
| Dock while running | `DockIconRenderer` via `AppIconController` | yes — the app resolves the background itself |
| Dock while not running, Finder, Launchpad, Spotlight | the bundle icon | **only** through `Assets.car` |

The third row is the one that used to be wrong.

## Why a `.icns` cannot do this

A `.icns` is a list of sizes of **one** image. It carries no appearance, so the
Finder, Launchpad and the Dock (while the app is not running) showed the same
tile whatever the system's icon style was. Because the artwork itself was the
dark tile, those surfaces stayed dark in light mode, while the running Dock icon
— which the app draws with a background resolved from the system — was light.
That is the "the app has two different icons" report.

Since macOS 26 the system themes an app icon only when the bundle carries an
asset catalog with an **icon stack** that has one rendition per appearance
(`NSAppearanceNameAqua`, `NSAppearanceNameDarkAqua`, `ISAppearanceTintable`).
The format that produces one is Icon Composer's `.icon`, compiled by `actool`.

A plain `AppIcon.appiconset` is **not** enough on macOS: adding
`{"appearance": "luminosity", "value": "dark"}` entries to one compiles without
an error and then silently drops the dark rendition. That was verified against
this project's own artwork — the catalog came back with a single `Icon Image`
and no appearance, at both a 15.0 and a 26.0 deployment target, with a
one-image and a full twenty-image size matrix.

## What the bundle ships

- `Support/AppIcon.icon/` — the icon document. `icon.json` plus `Assets/`,
  which must be spelled with a capital A; a lowercase `assets/` is not found and
  `actool` reports only `the layer references an image … that does not exist`.
- `Support/Assets.car` — the compiled catalog. **Committed**, not rebuilt on
  every app build, so the release workflow does not depend on one Xcode's
  `actool`. `actool` has had `.icon` regressions across Xcode releases.
- `Support/AppIcon.icns` is still generated at build time and still shipped: it
  is the icon for macOS 15, and the DMG volume icon.

`Support/Info.plist` sets `CFBundleIconName` to `AppIcon`, which is what makes
macOS look in `Assets.car`. Both keys stay: `CFBundleIconFile` for the `.icns`
and `CFBundleIconName` for the catalog.

## Regenerating

The two tiles are produced by the app's own renderer, not drawn by hand, so the
static icon and the running one cannot drift apart:

```bash
# 1. Write both appearance variants from the renderer
STATUS_TRIO_APP_ICON_VARIANTS_DIR=/tmp/app-icons \
  swift test --filter AppIconPreviewTests

# 2. Review them, then update the committed artwork
cp /tmp/app-icons/AppIcon.png       Support/AppIcon.png
cp /tmp/app-icons/AppIcon-Light.png Support/AppIcon-Light.png
cp Support/AppIcon-Light.png screenshots/status-trio-app-icon-light-preview.png

# 3. Recompile the catalog (copies the tiles into AppIcon.icon/Assets first)
bash scripts/build-app-icon.sh

# 4. Confirm it carries both appearances without invoking actool
bash scripts/build-app-icon.sh --check
```

`AppIconPreviewTests` pins `Support/AppIcon.png` to
`screenshots/status-trio-app-icon-preview.png` byte for byte, and the light tile
to its own preview, so a change to the artwork has to be made deliberately in
both places.

## Verification

`scripts/build-app-icon.sh --check` fails unless the catalog contains an
`IconImageStack` **and** both appearance names. `scripts/build-app.sh` runs that
check before compiling, and asserts on the assembled bundle that
`CFBundleIconName` is `AppIcon` and that `Resources/Assets.car` is present. All
three failures otherwise ship an icon that silently never changes.

To inspect a catalog by hand:

```bash
assetutil --info Support/Assets.car | grep -E 'IconImageStack|Appearance'
```

## Known limits

- The layers are the same opaque tiles the app draws, so the **Clear** and
  **Tinted** icon styles show this artwork rather than adapting to them. Giving
  those styles a real rendition would mean re-authoring the artwork as
  transparent glyph layers over the system fill, which is a design change rather
  than a bug fix.
- The catalog is about 1.4 MB, because it stores both appearances at every size
  the system can ask for.
