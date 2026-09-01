# Vectopen Pro — UI Design Document

> Sistema de diseño elegante (Apple / Sketch / Rive) para Vectopen.
> Versión 2.0 — Paleta semántica oscura + tema claro Studio.

---

## 1. Principios

- **Superficies de cristal oscuro**: paneles translúcidos con `backdrop` sutil, bordes `rgba(255,255,255,0.12)` y sombras suaves.
- **Color semántico, no decorativo**: verde = afirmativo (guardar/confirmar/activo), rojo = negativo (eliminar/cancelar/alerta), azul = marca/enlaces/foco.
- **Geometría consistente**: paneles 12px, widgets 8px, botones 6px.
- **Tipografía SF Pro**: primaria `#F5F5F7`, secundaria 55% blanco, deshabilitada 25% blanco.
- **Contraste garantizado**: texto blanco sobre acentos verdes/rojos (oscuro), texto blanco/negro según superficie (claro).

## 2. Paleta — Modo Oscuro (Vectopen Oscuro)

| Token | Valor | Uso |
|---|---|---|
| `surface.canvas` | `#18181A` | Lienzo |
| `surface.panel_bg` | `rgba(26,26,30,0.88)` | Paneles flotantes |
| `surface.widget_bg` | `rgba(255,255,255,0.05)` | Tarjetas / chips |
| `surface.input_bg` | `rgba(255,255,255,0.08)` | Campos de texto |
| `surface.border` | `rgba(255,255,255,0.12)` | Bordes |
| `text.primary` | `#F5F5F7` | Texto principal |
| `text.secondary` | `rgba(255,255,255,0.55)` | Subtítulos |
| `text.disabled` | `rgba(255,255,255,0.25)` | Deshabilitado |
| `semantic.affirmative` | `#30D158` (hover `#28B84C`) | Acciones primarias |
| `semantic.negative` | `#FF453A` (hover `#D7372D`) | Acciones destructivas |
| `accent` | `#0A84FF` | Foco / enlaces / selección |

## 3. Paleta — Modo Claro (Studio)

| Token | Valor |
|---|---|
| `surface.app_bg` | `#EFEFF4` |
| `surface.canvas` | `#FFFFFF` |
| `surface.panel_bg` | `#F8F8FA` |
| `surface.input_bg` | `#E5E5EA` |
| `surface.border` | `#D1D1D6` |
| `text.primary` | `#1C1C1E` |
| `text.secondary` | `#6C6C70` |
| `semantic.affirmative` | `#34C759` (hover `#28A745`) |
| `semantic.negative` | `#FF3B30` (hover `#DC3545`) |
| `accent` | `#007AFF` |

## 4. Geometría

| Token | Valor |
|---|---|
| `radius_panel` | 12px |
| `radius_widget` | 8px |
| `radius_button` | 6px |

## 5. Componentes

### Botones
- **Estándar**: fondo `widget_bg`, borde `border`, hover +50% brillo, pressed −30%, texto primario 13px.
- **Afirmativo** (`theme_type_variation = "AffirmativeButton"`): fondo verde `affirmative`, texto blanco, hover `affirmative_hover`. Para: Guardar, Confirmar, Aplicar.
- **Negativo** (`"NegativeButton"`): fondo rojo `negative`, texto blanco. Para: Eliminar, Cancelar, Cerrar.

### Campos de texto (`LineEdit`)
- Fondo `input_bg`, radio 6px, borde `border`.
- **Focus**: borde `accent` + anillo `accent` al 20%.
- Placeholder `text.secondary`, caret `text.primary`.

### Paneles (`Panel` / `PanelContainer`)
- Fondo `panel_bg`, radio 12px, borde `border`, sombra suave.

### Chips / píldoras (atajos de teclado)
- Fondo `widget_bg`, radio 6px, borde `border`, texto 12px primario.
- Captura de entrada: borde `accent`.

### Listas (`Tree`)
- Fondo panel, texto primario, selección `accent` al 25%.

## 6. Reglas de uso

1. **Nunca** texto primario sobre fondo afirmativo/negativo en modo claro — usar blanco.
2. Acentos semánticos solo para acciones/estados, no para decoración.
3. Respetar radios: 12/8/6.
4. Todo texto debe cumplir contraste ≥ 4.5:1 sobre su superficie.

## 7. Implementación

- Tokens: `docs/design/design-tokens.json` (fuente de verdad).
- Tema: `autoloads/ThemeManager.gd` genera el `Theme` en runtime desde los tokens (modos `dark` / `light`, conmutables, overrides por usuario persistidos en `user://vectopen_theme.cfg`).
- Slots semánticos expuestos: `affirmative`, `negative`, `accent`, `panel_bg`, `text.primary`, etc.
