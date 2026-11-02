#!/usr/bin/env bash
# =============================================================================
# Genera la pantalla de arranque (icon/logo/Splash.png, 1920 × 1080) con la
# versión de project.godot: así el splash nunca se queda en una versión vieja.
# Lo ejecuta el GitHub Action «Release» antes de exportar; a mano:
#   tools/make_splash.sh            (necesita ImageMagick 7: `magick`)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
YEAR="$(date +%Y)"
BG="#f4f5fb"          # = boot_splash/bg_color en project.godot
F=assets/fonts
OUT=icon/logo/Splash.png
IM="$(command -v magick || echo convert)"
"$IM" -size 1920x1080 "xc:$BG" \
  \( icon/app/vectopen_app_icon.png -resize 232x232 \) -gravity center -geometry +0-150 -composite \
  -font "$F/Inter-SemiBold.ttf" -pointsize 72 -fill "#17151f" -annotate +0+18 "Vectopen" \
  -font "$F/Inter-Regular.ttf" -pointsize 25 -fill "#6a6e80" -annotate +0+82 "Editor vectorial libre y de código abierto" \
  \( -size 132x40 xc:none -fill "#1b1a21" -draw "roundrectangle 0,0 131,39 20,20" \
     -font "$F/Inter-SemiBold.ttf" -pointsize 20 -fill white -gravity center -annotate +0+0 "v$VERSION" \) \
  -gravity center -geometry +0+152 -composite \
  -gravity south -font "$F/Inter-Regular.ttf" -pointsize 17 -fill "#9a9db0" \
  -annotate +0+46 "© 2025–$YEAR Casimiro Ondo Obiang · Licencia MIT · github.com/malabo1990/-Vectopen" \
  -strip "$OUT"
echo "Splash v$VERSION → $OUT"
