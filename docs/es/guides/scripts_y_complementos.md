# Scripts y complementos

Pestaña **Efectos → Script**. Tiene dos módulos.

## Scripts

Escribe GDScript y pulsa **▶ Ejecutar** (Ctrl+Intro o F5). `api` es Vectopen.

```gdscript
# Modo rápido: sin extends ni func, el código se envuelve solo.
var s := api.add_star(api.artboard_size() / 2.0, 80, 5)
api.set_fill(s, Color.GOLD)
print("Creada: ", s.name)
```

```gdscript
extends VectopenScript

func run() -> void:
	for s in api.selection():
		api.set_fill(s, Color.from_hsv(randf(), 0.6, 0.95))
```

- Cada ejecución es **un solo paso de deshacer**: Ctrl+Z deshace el script entero.
- Si el script falla, lo que llegó a hacer se deshace y la consola indica la línea (clic para ir).
- La sintaxis se comprueba mientras escribes; `api.` + Ctrl+Espacio autocompleta.
- El botón **API** muestra la referencia completa (`VectopenAPI.REFERENCE`).
- **Guardar** (Ctrl+S) los deja en `user://scripts/`; hay plantillas de ejemplo.
- `run()` puede usar `await api.wait(0.2)`.

La API cubre: crear figuras, texto, imágenes y artboards; propiedades del Inspector;
selección; orden de capas, alinear, distribuir y booleanas; efectos, filtros y
**shaders**; importar SVG, exportar (.svg .png .jpg .webp .pdf) y vectorizar imágenes.

```gdscript
# Cada estrella de la selección con un shader de la biblioteca, en UN paso.
for s in api.selection():
	api.apply_shader(s, "Mi shader")          # o el nombre de una plantilla, o código
api.add_effect(api.selection()[0], "Drop Shadow", {"blur": 12.0})
```

Coordenadas: las del artboard (origen arriba-izquierda); las figuras se colocan por su **centro**.

## Complementos

Como los add-ons de Blender. **Instalar…** acepta un `.zip`, una carpeta o un `.gd`.
Casilla = activar/desactivar (se recuerda). Menú `⋯`: recargar código, abrir carpeta, desinstalar.

Incluidos (`res://plugins/`): **Colores**, **Repetir**, **Hola Vectopen** (ejemplo mínimo).
Instalados por el usuario: `user://addons/<id>/`.

### Estructura

```
mi_complemento/
  addon.cfg
  main.gd
```

```ini
[addon]
name="Mi complemento"
version="1.0.0"
author="Yo"
description="Qué hace"
category="Objeto"
api="1.0"
main="main.gd"
```

```gdscript
extends VectopenAddon

func _enable() -> void:
	add_operator("Centrar", centrar, "Lleva la selección al centro del artboard")
	var b := Button.new()
	b.text = "Mi ajuste"
	add_panel(b)                       # aparece en su ficha

func centrar() -> void:               # corre como UN paso de deshacer
	for s in api.selection():
		api.set_position(s, api.artboard_size() / 2.0)

func _disable() -> void:
	pass                               # operadores y paneles se quitan solos
```

- `get_setting(clave, defecto)` / `set_setting(clave, valor)`: ajustes persistentes.
- Un complemento que falla al activarse queda desactivado y muestra el error en su ficha.
- `api="1.x"`: se carga si coincide la versión mayor de la API.
- Los complementos ejecutan código con los mismos permisos que Vectopen: instala solo los de confianza.
