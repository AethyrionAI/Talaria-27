# App icons (`tools/appicons/`)

Tooling for the alternate home-screen icons behind the in-app **App Icon picker**
(issue #25). The picker is **data-driven** — it renders whatever
`AppIconCatalog.all` lists — so this stays a mechanical "add art + one entry + one
plist key" job no matter how many icons pile up.

## What's here

- `generate_app_icons.py` — renders the current **placeholder** icons: an
  arc-reactor glyph in each theme's hero palette (values copied verbatim from
  `Shared/ThemePaletteCore.swift`) on that theme's screen gradient, plus a picker
  preview per icon. Output lands in `Talaria/Resources/AppIcons/`. Requires
  Pillow (`pip install Pillow`); run from the repo root:

  ```sh
  python3 tools/appicons/generate_app_icons.py
  ```

- `render_gallery_icons.py` — rasterizes the **curated gallery icons** (Lane K
  batch: the Neon Arcade Collection + Seasonal sets) straight from the SVGs in
  `design/themes/app-icons.html` into the same three flat PNGs per icon.
  Requires cairosvg + Pillow (`pip install cairosvg Pillow`); run from the
  repo root:

  ```sh
  python3 tools/appicons/render_gallery_icons.py
  ```

## Files each icon needs

All are **loose, flat (no-alpha) PNGs** in `Talaria/Resources/AppIcons/` (iOS
rejects alpha in app icons):

| File | Size | Role |
| --- | --- | --- |
| `Icon-<Name>@2x.png` | 120×120 | OS alternate-icon file (60 pt @2x) |
| `Icon-<Name>@3x.png` | 180×180 | OS alternate-icon file (60 pt @3x) |
| `IconPreview-<id>.png` | 240×240 | in-app picker thumbnail (`UIImage(named:)`) |

The **primary** icon keeps its art in the asset catalog
(`Assets.xcassets/AppIcon.appiconset`); it only needs a picker preview
(`IconPreview-Default.png`, baked from `AppIcon.png` by the script).

## Add or replace an icon (checklist)

1. **Art** — drop the three PNGs above into `Talaria/Resources/AppIcons/`. To
   swap the current placeholders for the real Open Design concepts, just
   overwrite the files at the same paths — no code change. To add a brand-new
   icon, either extend `generate_app_icons.py` or rasterize your own (remember:
   flat, no alpha, exact sizes).
2. **Info.plist** — add a `CFBundleAlternateIcons` key in `project.yml` under
   `targets.Talaria.info.properties.CFBundleIcons.CFBundleAlternateIcons`:

   ```yaml
   <Name>:
     CFBundleIconFiles:
       - Icon-<Name>
     UIPrerenderedIcon: false
   ```

   `<Name>` is the string passed to `setAlternateIconName(_:)`. `CFBundleIconFiles`
   lists the **base name** (no `@2x`/`.png`); iOS finds the scaled files.
3. **Catalog** — add one `AppIconOption` to `AppIconCatalog.all`
   (`Talaria/Models/AppIconCatalog.swift`): `alternateIconName: "<Name>"`,
   `previewImageName: "IconPreview-<id>"`.
4. **Regenerate** — `xcodegen generate` (new resources + the plist change), then
   build. The picker shows the new icon automatically.

## Notes

- iPad-specific alternate sizes (152/167 px) aren't generated — the app is
  iPhone-portrait-first. Add them here + to `CFBundleIconFiles` if iPad needs
  bespoke icon art.
- The four themed icons are **placeholders** matched to the app themes, pending
  the curated art. They're committed so the picker is exercisable on device today.
