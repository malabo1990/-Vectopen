#!/usr/bin/env bash
# =============================================================================
# Empaqueta una versión de Vectopen para Windows, macOS y Linux a partir de
# las exportaciones de Godot en build/ (ver export_presets.cfg):
#   build/windows/Vectopen.exe (+ vectopen_text.dll)
#   build/macos/Vectopen.zip   (Vectopen.app universal: Intel + Apple Silicon)
#   build/linux/vectopen.x86_64 (+ libvectopen_*.so)
# Resultado en dist/<versión>/:
#   Windows  .zip
#   macOS    .dmg (imagen híbrida, se abre en macOS) y .zip
#   Linux    .deb · .rpm · .tar.gz · .AppImage (si hay appimagetool)
# Uso: tools/package_release.sh [versión]   (por defecto la de project.godot)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)}"
NUM="${VERSION%%-*}"                 # 0.2.0
# Autor y avisos legales (MIT): se copian LICENSE y THIRD_PARTY_NOTICES.txt en
# todos los paquetes, como exige la licencia MIT y las de terceros.
AUTHOR="$(sed -n 's/^Copyright (c) [0-9-]* //p' LICENSE | head -1)"
EMAIL="malabo1990@gmail.com"
HOMEPAGE="https://malabo1990.github.io/vectopen-web/"
LEGAL=(LICENSE THIRD_PARTY_NOTICES.txt)
PRE="${VERSION#"$NUM"}"; PRE="${PRE#-}"   # alpha
DIST="dist/$VERSION"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
rm -rf "$DIST"; mkdir -p "$DIST"
ICON_SRC="icon/logo/logo_vectopen.png"
echo "Vectopen $VERSION → $DIST"

# Icono cuadrado 256 px para Linux (el logo no es cuadrado).
python3 - "$ICON_SRC" "$WORK/vectopen.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGBA")
im.thumbnail((240, 240), Image.LANCZOS)
c = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
c.paste(im, ((256 - im.width) // 2, (256 - im.height) // 2), im)
c.save(sys.argv[2])
PY

# ── WINDOWS ──────────────────────────────────────────────────────────────────
W="$WORK/Vectopen-$VERSION-windows-x64"
mkdir -p "$W"
cp build/windows/Vectopen.exe build/windows/*.dll "${LEGAL[@]}" "$W"/
cat > "$W/LEEME.txt" <<EOF
Vectopen $VERSION (versión ALFA) — Windows 10/11 de 64 bits

Abre Vectopen.exe (deja vectopen_text.dll en la misma carpeta).
Windows puede avisar "Windows protegió su PC" porque el programa no está
firmado todavía: "Más información" → "Ejecutar de todas formas".
En esta alfa la pestaña Vectorizar no está disponible en Windows.
EOF
(cd "$WORK" && zip -qr9 "$OLDPWD/$DIST/Vectopen-$VERSION-windows-x64.zip" "$(basename "$W")")
echo "  ✓ Windows zip"

# ── macOS ────────────────────────────────────────────────────────────────────
M="$WORK/mac"
mkdir -p "$M/dmg"
cp build/macos/Vectopen.zip "$DIST/Vectopen-$VERSION-macos-universal.zip"
(cd "$M/dmg" && unzip -q "$OLDPWD/build/macos/Vectopen.zip")
cp "${LEGAL[@]}" "$M/dmg/"
zip -qj "$DIST/Vectopen-$VERSION-macos-universal.zip" "${LEGAL[@]}"
ln -s /Applications "$M/dmg/Aplicaciones"
cat > "$M/dmg/LEEME.txt" <<EOF
Vectopen $VERSION (versión ALFA) — macOS 10.15+ (Intel y Apple Silicon)

Arrastra Vectopen a la carpeta Aplicaciones.
La app aún no está notarizada por Apple: la primera vez, clic derecho sobre
Vectopen → Abrir → Abrir. (O en Terminal:
  xattr -dr com.apple.quarantine /Applications/Vectopen.app )
En esta alfa la pestaña Vectorizar no está disponible en macOS.
EOF
# Imagen híbrida ISO9660/HFS: macOS la monta como un .dmg normal.
genisoimage -quiet -V "Vectopen $VERSION" -D -R -apple -no-pad \
	-o "$DIST/Vectopen-$VERSION-macos-universal.dmg" "$M/dmg"
echo "  ✓ macOS dmg + zip"

# ── LINUX: árbol común (/opt/vectopen) ───────────────────────────────────────
L="$WORK/linuxroot"
mkdir -p "$L/opt/vectopen" "$L/usr/bin" "$L/usr/share/applications" "$L/usr/share/icons/hicolor/256x256/apps"
cp build/linux/vectopen.x86_64 build/linux/*.so "${LEGAL[@]}" "$L/opt/vectopen/"
mkdir -p "$L/usr/share/doc/vectopen"
{ echo "Vectopen — $HOMEPAGE"; echo "Copyright: $AUTHOR"; echo "License: MIT"; echo; cat LICENSE; echo; cat THIRD_PARTY_NOTICES.txt; } > "$L/usr/share/doc/vectopen/copyright"
chmod 755 "$L/opt/vectopen/vectopen.x86_64"
ln -s /opt/vectopen/vectopen.x86_64 "$L/usr/bin/vectopen"
cp "$WORK/vectopen.png" "$L/usr/share/icons/hicolor/256x256/apps/vectopen.png"
DESKTOP='[Desktop Entry]
Type=Application
Name=Vectopen
GenericName=Editor vectorial
Comment=Editor de gráficos vectoriales
Exec=vectopen %F
Icon=vectopen
Terminal=false
Categories=Graphics;VectorGraphics;
StartupWMClass=Vectopen'
echo "$DESKTOP" > "$L/usr/share/applications/vectopen.desktop"
SIZE_KB=$(du -sk "$L" | cut -f1)

# .tar.gz portátil
T="$WORK/Vectopen-$VERSION-linux-x86_64"
mkdir -p "$T"
cp build/linux/vectopen.x86_64 build/linux/*.so "$WORK/vectopen.png" "${LEGAL[@]}" "$T"/
echo "$DESKTOP" | sed "s|^Exec=.*|Exec=./vectopen.x86_64|" > "$T/vectopen.desktop"
(cd "$WORK" && tar -czf "$OLDPWD/$DIST/Vectopen-$VERSION-linux-x86_64.tar.gz" "$(basename "$T")")
echo "  ✓ Linux tar.gz"

# .deb (Debian / Ubuntu / Mint…) — construido a mano (ar + tar), sin dpkg-deb
D="$WORK/deb"
mkdir -p "$D/control"
DEBVER="$NUM${PRE:+~$PRE}-1"
cat > "$D/control/control" <<EOF
Package: vectopen
Version: $DEBVER
Section: graphics
Priority: optional
Architecture: amd64
Installed-Size: $SIZE_KB
Maintainer: $AUTHOR <$EMAIL>
Homepage: $HOMEPAGE
Description: Editor de gráficos vectoriales (versión alfa)
 Vectopen: editor vectorial con modos Smart, Modern y Pro.
EOF
(cd "$L" && find . -type f -exec md5sum {} + | sed 's| \./| |') > "$D/control/md5sums"
(cd "$D/control" && tar --owner=0 --group=0 -czf ../control.tar.gz .)
(cd "$L" && tar --owner=0 --group=0 -cJf "$D/data.tar.xz" .)
echo "2.0" > "$D/debian-binary"
(cd "$D" && ar rc "$OLDPWD/$DIST/vectopen_${DEBVER}_amd64.deb" debian-binary control.tar.gz data.tar.xz)
echo "  ✓ Linux deb"

# .rpm (Fedora / openSUSE / RHEL…)
R="$WORK/rpm"
mkdir -p "$R"/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}
cat > "$R/SPECS/vectopen.spec" <<EOF
Name:           vectopen
Version:        $NUM
Release:        0.1${PRE:+.$PRE}
Summary:        Editor de graficos vectoriales (version alfa)
License:        MIT
URL:            $HOMEPAGE
Packager:       $AUTHOR <$EMAIL>
AutoReqProv:    no
%description
Vectopen: editor vectorial con modos Smart, Modern y Pro.
%install
mkdir -p %{buildroot}
cp -a $L/. %{buildroot}/
%files
/opt/vectopen
/usr/bin/vectopen
/usr/share/applications/vectopen.desktop
/usr/share/icons/hicolor/256x256/apps/vectopen.png
/usr/share/doc/vectopen
EOF
rpmbuild --quiet --define "_topdir $R" --define "_build_id_links none" -bb "$R/SPECS/vectopen.spec" >/dev/null 2>&1
cp "$R"/RPMS/x86_64/*.rpm "$DIST"/
echo "  ✓ Linux rpm"

# .AppImage (cualquier distribución)
AIT="${APPIMAGETOOL:-$HOME/.local/bin/appimagetool}"
if [ -x "$AIT" ]; then
	A="$WORK/Vectopen.AppDir"
	mkdir -p "$A/usr/bin"
	cp build/linux/vectopen.x86_64 build/linux/*.so "$A/usr/bin/"
	cp "$WORK/vectopen.png" "$A/vectopen.png"
	echo "$DESKTOP" > "$A/vectopen.desktop"
	printf '#!/bin/sh\nHERE="$(dirname "$(readlink -f "$0")")"\nexec "$HERE/usr/bin/vectopen.x86_64" "$@"\n' > "$A/AppRun"
	chmod 755 "$A/AppRun"
	ARCH=x86_64 "$AIT" --appimage-extract-and-run "$A" "$DIST/Vectopen-$VERSION-x86_64.AppImage" >/dev/null 2>&1 \
		&& echo "  ✓ Linux AppImage" || echo "  ✗ AppImage (falló appimagetool)"
else
	echo "  · AppImage omitido (no hay appimagetool en $AIT)"
fi

(cd "$DIST" && sha256sum * > SHA256SUMS.txt)
ls -lh "$DIST"
