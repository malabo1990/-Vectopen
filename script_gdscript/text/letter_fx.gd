# =============================================================================
# RUTA: res://script_gdscript/text/letter_fx.gd
# EFECTOS AVANZADOS DE LETRAS (panel "Letras avanzadas"), paramétricos:
#   · letter_proportions   {mode, start, mid, mid2, end}  escala por letra
#                          (curva de 4 puntos: Aaa, aaA, aAa, AaA o propia)
#   · letter_wave          {mode: "wave"|"arc", amount, cycles, phase}
#                          desplazamiento vertical por letra (px, + = arriba)
#   · letter_tracking_ramp {start, end}  interletra que va de start a end (px)
# Se guardan como metas del texto (los runs del usuario NO se tocan) y se
# "materializan" en runs por letra SOLO para dibujar: tamaño, baseline_shift
# y letter_spacing, que el motor nativo VectorRichText ya sabe pintar. Así
# funcionan con la extensión nativa (antes las proporciones solo se veían en
# el modo sin extensión) y el overlay vectorial usa las mismas curvas.
# =============================================================================
extends RefCounted

const TextRuns = preload("res://script_gdscript/text/text_runs.gd")

const META_PROP := "letter_proportions"
const META_WAVE := "letter_wave"
const META_RAMP := "letter_tracking_ramp"
const METAS := [META_PROP, META_WAVE, META_RAMP]

const PRESETS := {
	"Aaa": {"start": 1.6, "mid": 1.2, "mid2": 0.8, "end": 0.4},
	"aAa": {"start": 0.4, "mid": 1.4, "mid2": 1.4, "end": 0.4},
	"aaA": {"start": 0.4, "mid": 0.8, "mid2": 1.2, "end": 1.6},
	"AaA": {"start": 1.5, "mid": 0.5, "mid2": 0.5, "end": 1.5},
}

static func _meta(node: Object, key: String) -> Dictionary:
	if node == null or not node.has_meta(key):
		return {}
	var v = node.get_meta(key)
	return v if v is Dictionary else {}

static func proportions(node: Object) -> Dictionary:
	var p := _meta(node, META_PROP)
	return p if String(p.get("mode", "")) != "" else {}

static func wave(node: Object) -> Dictionary:
	var w := _meta(node, META_WAVE)
	return w if String(w.get("mode", "")) in ["wave", "arc"] and absf(float(w.get("amount", 0.0))) > 0.001 else {}

static func ramp(node: Object) -> Dictionary:
	var r := _meta(node, META_RAMP)
	return r if absf(float(r.get("start", 0.0))) > 0.001 or absf(float(r.get("end", 0.0))) > 0.001 else {}

static func has_fx(node: Object) -> bool:
	return not proportions(node).is_empty() or not wave(node).is_empty() or not ramp(node).is_empty()

## Posición normalizada 0..1 de la letra `i` de `n`.
static func t_of(i: int, n: int) -> float:
	return float(i) / float(n - 1) if n > 1 else 0.0

## Escala de la letra en t: curva lineal por tramos de 4 puntos.
static func scale_at(p: Dictionary, t: float) -> float:
	if p.is_empty():
		return 1.0
	var a := float(p.get("start", 1.0))
	var b := float(p.get("mid", 1.0))
	var c := float(p.get("mid2", b))
	var d := float(p.get("end", 1.0))
	if t <= 1.0 / 3.0:
		return lerpf(a, b, t * 3.0)
	elif t <= 2.0 / 3.0:
		return lerpf(b, c, (t - 1.0 / 3.0) * 3.0)
	return lerpf(c, d, (t - 2.0 / 3.0) * 3.0)

## Desplazamiento vertical (px, + = arriba) de la letra en t.
static func wave_at(w: Dictionary, t: float) -> float:
	if w.is_empty():
		return 0.0
	var amount := float(w.get("amount", 0.0))
	if String(w.get("mode", "wave")) == "arc":
		var u := 2.0 * t - 1.0
		return amount * (1.0 - u * u)
	var cycles := float(w.get("cycles", 1.0))
	var phase := deg_to_rad(float(w.get("phase", 0.0)))
	return amount * sin(TAU * cycles * t + phase)

## [mín, máx] del desplazamiento de la onda sobre `n` letras.
static func wave_range(w: Dictionary, n: int) -> Vector2:
	if w.is_empty() or n <= 0:
		return Vector2.ZERO
	var lo := INF
	var hi := -INF
	for i in n:
		var v := wave_at(w, t_of(i, n))
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return Vector2(lo, hi)

## Desplazamiento DIBUJADO (px, + = arriba): la onda se baja entera para que
## ninguna letra suba por encima de la caja; la caja crece `wave_extent`.
static func wave_shift(w: Dictionary, i: int, n: int, rng: Vector2) -> float:
	return wave_at(w, t_of(i, n)) - maxf(rng.y, 0.0)

## Alto extra que ocupa la onda (lo que la caja debe crecer hacia abajo).
static func wave_extent(node: Object, n: int) -> float:
	var rng := wave_range(wave(node), n)
	return maxf(rng.y, 0.0) - minf(rng.x, 0.0)

## Interletra extra (px) de la letra en t.
static func ramp_at(r: Dictionary, t: float) -> float:
	if r.is_empty():
		return 0.0
	return lerpf(float(r.get("start", 0.0)), float(r.get("end", 0.0)), t)

## Runs para DIBUJAR: los del usuario con los efectos aplicados letra a
## letra (y fusionados donde coinciden). Sin efectos devuelve los mismos.
static func derive_runs(shape: Object, base_runs: Array, text: String) -> Array:
	var n := text.length()
	if n == 0 or not has_fx(shape):
		return base_runs
	var p := proportions(shape)
	var w := wave(shape)
	var r := ramp(shape)
	var fs := float(shape.get_meta("font_size", 24))
	var wrng := wave_range(w, n)
	var runs := base_runs if TextRuns.runs_len(base_runs) == n else [{"length": n}]
	var out: Array = []
	var i := 0
	for run in runs:
		var ln := int(run.get("length", 0))
		for j in ln:
			if i >= n:
				break
			var t := t_of(i, n)
			var d: Dictionary = (run as Dictionary).duplicate()
			d["length"] = 1
			var sz := float(run.get("size", 0.0))
			if sz <= 0.0:
				sz = fs
			d["size"] = maxf(2.0, roundf(sz * scale_at(p, t)))
			d["baseline_shift"] = float(run.get("baseline_shift", 0.0)) + (wave_shift(w, i, n, wrng) if not w.is_empty() else 0.0)
			d["letter_spacing"] = float(run.get("letter_spacing", 0.0)) + ramp_at(r, t)
			out.append(d)
			i += 1
	return merge(out)

## Como TextRuns.merge_runs pero respetando baseline_shift / letter_spacing.
static func merge(runs: Array) -> Array:
	var out: Array = []
	for r in runs:
		if not out.is_empty():
			var last: Dictionary = out[out.size() - 1]
			if is_equal_approx(float(last.get("baseline_shift", 0.0)), float(r.get("baseline_shift", 0.0))) \
					and is_equal_approx(float(last.get("letter_spacing", 0.0)), float(r.get("letter_spacing", 0.0))) \
					and TextRuns.merge_runs([last.duplicate(), (r as Dictionary).duplicate()]).size() == 1:
				last["length"] = int(last["length"]) + int(r.get("length", 0))
				continue
		out.append((r as Dictionary).duplicate())
	return out
