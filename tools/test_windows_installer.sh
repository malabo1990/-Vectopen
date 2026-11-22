#!/usr/bin/env bash
# =============================================================================
# Prueba el instalador NSIS de Windows con Wine en un prefijo NUEVO y aislado
# (sin menús de Wine ni enlaces a las carpetas del usuario): instala en
# silencio, comprueba archivos / registro / accesos, reinstala encima
# (actualización) y desinstala.
# Uso: tools/test_windows_installer.sh <Vectopen-…-setup.exe>
# =============================================================================
set -uo pipefail
SETUP="$(realpath "$1")"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export WINEPREFIX="$T/prefix" WINEDEBUG=-all DISPLAY=
export WINEDLLOVERRIDES="mscoree,mshtml=;winemenubuilder.exe=d"
fails=0
ok() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
timeout 240 wineboot -i >/dev/null 2>&1
# las carpetas del usuario de Wine apuntan a las reales: se cortan
for d in "$WINEPREFIX"/drive_c/users/*/*; do
	[ -L "$d" ] && rm "$d" && mkdir "$d"
done
P="$(ls -d "$WINEPREFIX"/drive_c/users/*/ | grep -v Public | head -1)AppData/Local/Programs/Vectopen"
q() { timeout 60 wine reg query "$1" 2>/dev/null | tr -d '\r'; }
timeout 240 wine "$SETUP" /S >/dev/null 2>&1
ok "instala sin administrador en Programs\\Vectopen" '[ -f "$P/Vectopen.exe" ] && [ -f "$P/Uninstall.exe" ]'
ok "copia las DLL" 'ls "$P"/*.dll >/dev/null 2>&1'
ok "registra el desinstalador" 'q "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Vectopen" | grep -q QuietUninstallString'
ok "asocia los .vtp" 'q "HKCU\\Software\\Classes\\Vectopen.Document\\shell\\open\\command" | grep -q "%1"'
ok "acceso en el menú Inicio" 'ls "$WINEPREFIX"/drive_c/users/*/AppData/Roaming/Microsoft/Windows/Start\ Menu/Programs/Vectopen/Vectopen.lnk >/dev/null 2>&1'
timeout 240 wine "$SETUP" /S >/dev/null 2>&1
ok "reinstala encima (actualización)" '[ -f "$P/Vectopen.exe" ]'
timeout 120 wine "$P/Uninstall.exe" /S >/dev/null 2>&1; sleep 3
ok "desinstala: sin archivos" '[ ! -d "$P" ]'
ok "desinstala: sin claves" '! q "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Vectopen" | grep -q Vectopen && ! q "HKCU\\Software\\Classes\\.vtp" | grep -q Vectopen'
echo "RESULT: $([ $fails = 0 ] && echo OK || echo "$fails FAIL")"
exit $fails
