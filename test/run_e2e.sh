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
	# Cada prueba parte de los ajustes de FÁBRICA (como test/run_unit.sh):
	# el estilo, grosor o presión que el usuario dejó guardados no deben
	# cambiar el resultado. Al terminar se reponen los suyos.
	rm -f "$USERDATA"/*.cfg
	t="${t%.gd}"
	# E2E_TIMEOUT (s) y E2E_ENV («VAR=valor VAR2=valor») para pruebas largas
	# o parametrizadas (p. ej. el benchmark de documentos grandes).
	ENVARGS=()
	for kv in ${E2E_ENV:-}; do ENVARGS+=("--env=$kv"); done
	# E2E_ARGS: argumentos extra para Godot (p. ej. «--rendering-method gl_compatibility»)
	# shellcheck disable=SC2086
	timeout "${E2E_TIMEOUT:-450}" flatpak run "${ENVARGS[@]}" --command=godot org.godotengine.Godot --path . --screen 1 ${E2E_ARGS:-} \
		-s "res://test/e2e/$t.gd" > "$LOG_DIR/$t.log" 2>&1
	# Antes «| head -c 60000»: al llegar a 60 KB la tubería se cerraba y Godot
	# moría por SIGPIPE a mitad de la prueba (text_advanced_e2e salía «sin
	# resultado»). Ahora el registro entero; si pasa de 5 MB, principio + final.
	if [ "$(stat -c %s "$LOG_DIR/$t.log")" -gt 5000000 ]; then
		{ head -c 1000000 "$LOG_DIR/$t.log"; echo; echo "…[registro recortado]…"; tail -c 4000000 "$LOG_DIR/$t.log"; } > "$LOG_DIR/$t.log.tmp"
		mv "$LOG_DIR/$t.log.tmp" "$LOG_DIR/$t.log"
	fi
	grep -E '^BENCH' "$LOG_DIR/$t.log"
	echo "== $t: $(grep -cE '^PASS' "$LOG_DIR/$t.log") PASS $(grep -E '^FAIL|RESULT|SCRIPT ERROR' "$LOG_DIR/$t.log" | head -4 | tr '\n' ' ')"
	restore   # cada prueba parte de los ajustes del usuario, no de los de la anterior
done
