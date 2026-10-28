#!/usr/bin/env bash
# =============================================================================
# Batería unitaria (gdUnit4, sin ventana) SIN tocar los ajustes del usuario:
# copia user://*.cfg antes y la repone al terminar (algunos tests guardan
# idioma, tema o ajustes de Capas). Uso: test/run_unit.sh [ruta de test]
# =============================================================================
set -u
cd "$(dirname "$0")/.."
LOG_DIR="$HOME/.cache/vectopen_tests"
mkdir -p "$LOG_DIR"
USERDATA="$HOME/.var/app/org.godotengine.Godot/data/godot/app_userdata/Vectopen"
SNAP="$LOG_DIR/userdata_snapshot_unit"
rm -rf "$SNAP"; mkdir -p "$SNAP"
cp -p "$USERDATA"/*.cfg "$SNAP"/ 2>/dev/null
cp -p project.godot "$SNAP"/project.godot.bak
restore() {
	for f in "$USERDATA"/*.cfg; do
		[ -e "$SNAP/$(basename "$f")" ] || rm -f "$f"
	done
	cp -p "$SNAP"/*.cfg "$USERDATA"/ 2>/dev/null
	cp -p "$SNAP"/project.godot.bak project.godot   # el test de idioma lo reescribe
}
trap restore EXIT
timeout 300 flatpak run --command=godot org.godotengine.Godot --headless --path . --import > /dev/null 2>&1
timeout 1500 flatpak run --command=godot org.godotengine.Godot --headless --path . \
	-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a "res://${1:-test}" -c 2>&1 \
	| sed 's/\x1b\[[0-9;]*m//g' | head -c 30000000 > "$LOG_DIR/gdunit.txt"
grep -E "Overall Summary|FAILED" "$LOG_DIR/gdunit.txt" | head -20
# Sin resumen = la batería no llegó a correr (p. ej. error de sintaxis al
# escanear): que se vea, en vez de parecer que no hay fallos.
if ! grep -q "Overall Summary" "$LOG_DIR/gdunit.txt"; then
	echo "ERROR: la batería no llegó a terminar. Primeros errores:"
	grep -E "Parse Error|SCRIPT ERROR" "$LOG_DIR/gdunit.txt" | head -5
	exit 1
fi
grep -q "0 failures" "$LOG_DIR/gdunit.txt" && grep -q "0 errors" "$LOG_DIR/gdunit.txt"
