# Oort NX app icon artwork

`scripts/brand_icons.py` draws a cross-section of the Oort cloud in SVG.
Regenerate the icons on macOS with Xcode 26 or later (`actool`, `ictool`):

```sh
out="$PWD/work/oort/icons"
ictool="$(dirname "$(xcode-select -p)")/Applications/Icon Composer.app/Contents/Executables/ictool"
python3 scripts/brand_icons.py "$out"
rm -rf design/Icons/AppIcon.icon design/Icons/AppIconParticles.icon
cp -R "$out/AppIcon.icon" "$out/AppIconParticles.icon" design/Icons/
for look in Default:Light Dark:Dark; do
  "$ictool" design/Icons/AppIconParticles.icon --export-image --output-file "$out/p.png" \
    --platform macOS --rendition "${look%%:*}" --width 824 --height 824 --scale 1
  sips --padToHeightWidth 1024 1024 "$out/p.png" --out "design/Icons/AppIcon-Particles-${look##*:}.png"
done
xcrun actool design/Icons/AppIcon.icon --compile "$out" --platform macosx --minimum-deployment-target 13.0 \
  --app-icon AppIcon --include-all-app-icons --output-partial-info-plist "$out/partial.plist"
cp "$out/AppIcon.icns" apps/mac/AppIcon.icns
"$ictool" design/Icons/AppIcon.icon --export-image --output-file design/Icons/AppIcon-Light.png \
  --platform macOS --rendition Default --width 512 --height 512 --scale 2  # README
```

`AppIcon.icon` is the bundle icon: `build_app.sh` compiles it into `Assets.car`
and sets `CFBundleIconName`, so macOS 26+ draws it natively (light, dark, tinted,
clear) instead of placing the `.icns` inside a grey squircle. The 824-point
particle renders keep the 100-point margin of the macOS icon grid.

Inspect the installed app in Finder and the Dock after quitting and reopening
it; the running app can retain its previous icon until it restarts.

`IconArtwork.png` preserves the original upstream Arcane crystal artwork
(created with AI by the owner on 2026-11-18). The upstream `make_icons.swift`
replaces the same output files with the legacy crystal, not the Oort NX icons.
