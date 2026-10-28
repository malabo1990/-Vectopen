#!/usr/bin/env bash
# =============================================================================
# Pasa TODOS los tests de interfaz (clics reales) en la pantalla Huion.
# - Cada test se cierra solo (vigilante interno) y, si aun así se cuelga, se
#   mata SU proceso godot-bin por PID (`timeout` solo mataba el lanzador de
#   flatpak y Godot seguía vivo: ventana negra + /tmp lleno).
# - Registros en ~/.cache/vectopen_tests/ (no en /tmp), con tope de tamaño.
# Uso: test/e2e/run_all.sh [--all]    (desde la raíz del proyecto)
# =============================================================================
set -u
cd "$(dirname "$0")/../.."
LOG_DIR="$HOME/.cache/vectopen_tests"
mkdir -p "$LOG_DIR"
TESTS=(
	panels_open_e2e
	tool_panels_dock_e2e
	modern_shapes_flow_e2e
	stroke_paint_e2e
	resize_shapes_e2e
	bounding_box_e2e
	middle_scroll_e2e
	full_panels_modern_pro_e2e
	assets_ui_e2e
	layers_children_e2e
	mode_switch_panels_e2e
	layers_view_e2e
	panel_resize_e2e
)
# --all: todos los *_e2e.gd del proyecto (no solo la lista de arriba).
if [ "${1:-}" = "--all" ]; then
	TESTS=()
	for f in test/e2e/*_e2e.gd; do TESTS+=("$(basename "$f" .gd)"); done
fi
# La app guarda los ajustes del usuario en user:// (temas, capas, modo de
# UI…). Algunos tests los cambian (p. ej. «Restablecer» de Capas): se copia
# TODO antes de cada test y se repone después, aunque el test se cuelgue.
USERDATA="$HOME/.var/app/org.godotengine.Godot/data/godot/app_userdata/Vectopen"
SNAP="$LOG_DIR/userdata_snapshot"
snapshot_userdata() {
	rm -rf "$SNAP"; mkdir -p "$SNAP"
	cp -p "$USERDATA"/*.cfg "$SNAP"/ 2>/dev/null
}
restore_userdata() {
	for f in "$USERDATA"/*.cfg; do
		[ -e "$SNAP/$(basename "$f")" ] || rm -f "$f"   # creado por el test
	done
	cp -p "$SNAP"/*.cfg "$USERDATA"/ 2>/dev/null
}
trap restore_userdata EXIT
fails=0
for t in "${TESTS[@]}"; do
	snapshot_userdata
	log="$LOG_DIR/$t.log"
	before=$(pgrep -x godot-bin | sort)
	flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
		-s "res://test/e2e/$t.gd" 2>&1 | head -c 5000000 > "$log" &
	pipe=$!
	for _ in $(seq 1 270); do
		kill -0 "$pipe" 2>/dev/null || break
		sleep 1
	done
	# Solo los godot-bin que han aparecido con ESTE test (nunca el editor).
	for pid in $(comm -13 <(echo "$before") <(pgrep -x godot-bin | sort)); do
		if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "test/e2e/$t.gd"; then
			kill "$pid" 2>/dev/null
		fi
	done
	wait "$pipe" 2>/dev/null
	restore_userdata
	pass=$(grep -c '^PASS' "$log")
	fail=$(grep -c '^FAIL' "$log")
	result=$(grep -oE 'RESULT[: ].*' "$log" | tail -1)
	printf '%-26s %3d PASS %3d FAIL  %s\n' "$t" "$pass" "$fail" "${result:-SIN RESULTADO}"
	grep '^FAIL' "$log" | head -5 | sed 's/^/    /'
	if [ "$fail" -gt 0 ] || ! grep -qE 'RESULT(:)? (OK|PASS|DONE)' "$log"; then
		fails=$((fails + 1))
	fi
done
echo "Tests con fallos: $fails"
exit $fails
