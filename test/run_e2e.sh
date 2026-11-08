#!/usr/bin/env bash
# =============================================================================
# Prueba e2e CON VENTANA (en la Huion, pantalla 1) SIN tocar los ajustes del
# usuario: copia user://*.cfg antes y la repone al terminar (las pruebas
# eligen estilos, grosores, presión… y el pincel los guarda).
#   test/run_e2e.sh brush_ui_zoom_e2e [más pruebas…]
# Log de cada una en ~/.cache/vectopen_tests/<prueba>.log
# =============================================================================
set -u
cd "$(dirname "$0")/.."
LOG_DIR="$HOME/.cache/vectopen_tests"
mkdir -p "$LOG_DIR"
USERDATA="$HOME/.var/app/org.godotengine.Godot/data/godot/app_userdata/Vectopen"
SNAP="$LOG_DIR/userdata_snapshot_e2e"
rm -rf "$SNAP"; mkdir -p "$SNAP"
cp -p "$USERDATA"/*.cfg "$SNAP"/ 2>/dev/null
restore() {
	for f in "$USERDATA"/*.cfg; do
		[ -e "$SNAP/$(basename "$f")" ] || rm -f "$f"
	done
	cp -p "$SNAP"/*.cfg "$USERDATA"/ 2>/dev/null
}
trap restore EXIT
for t in "$@"; do
	t="${t%.gd}"
	timeout 450 flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
		-s "res://test/e2e/$t.gd" 2>&1 | head -c 60000 > "$LOG_DIR/$t.log"
	echo "== $t: $(grep -cE '^PASS' "$LOG_DIR/$t.log") PASS $(grep -E '^FAIL|RESULT|SCRIPT ERROR' "$LOG_DIR/$t.log" | head -4 | tr '\n' ' ')"
done
