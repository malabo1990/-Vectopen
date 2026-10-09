pub mod editor;
pub mod layout;
pub mod model;

use godot::builtin::{Array, Color, GString, Rect2, Vector2, Vector2i};
use godot::classes::{
    control::{FocusMode, MouseFilter}, Control, DisplayServer, Font, IControl, InputEvent, InputEventKey,
    InputEventMouseButton, InputEventMouseMotion, Time,
};
use godot::global::{Key, MouseButton};
use godot::prelude::*;

use crate::editor::EditorState;
use crate::layout::StyleFonts;
use crate::layout::LayoutEngine;
use crate::model::{
    HAlign, OverflowMode, TextDocument, TextInteractionState, VarDictionary, VerticalAlignment,
};

struct VectopenTextExtension;

#[gdextension]
unsafe impl ExtensionLibrary for VectopenTextExtension {}

#[derive(GodotClass)]
#[class(base=Control)]
pub struct VectorRichText {
    base: Base<Control>,
    doc: TextDocument,
    layout: LayoutEngine,
    editor: EditorState,
    default_font: Option<Gd<Font>>,
    /// set_font() explícito (FontCore): el tema ya no lo pisa en ready/recalculate.
    explicit_font: bool,
    /// Fuentes REALES por estilo: [negrita, cursiva, negrita+cursiva].
    /// Sin ellas se sintetiza (emboldening/cizalla), que con MSDF deja
    /// muescas blancas en las uniones de las letras.
    style_fonts: StyleFonts,
    accent_color: Color,
    selection_color: Color,
    last_click_msec: u64,
    last_click_pos: Vector2,
    click_count: u32,
}

#[godot_api]
impl IControl for VectorRichText {
    fn init(base: Base<Control>) -> Self {
        Self {
            base,
            doc: TextDocument::new(""),
            layout: LayoutEngine::default(),
            editor: EditorState::default(),
            default_font: None,
            explicit_font: false,
            style_fonts: StyleFonts::default(),
            accent_color: Color::from_rgb(0.0, 0.478, 1.0),
            selection_color: Color::from_rgba(0.0, 0.478, 1.0, 0.3),
            last_click_msec: 0,
            last_click_pos: Vector2::ZERO,
            click_count: 0,
        }
    }

    fn ready(&mut self) {
        if !self.explicit_font {
            let tf = self.base().get_theme_font("font");
            self.default_font = tf;
        }
        self.base_mut().set_mouse_filter(MouseFilter::PASS);
        self.base_mut().set_focus_mode(FocusMode::CLICK);
        self.recalculate();
    }

    fn process(&mut self, delta: f64) {
        if self.editor.is_editing {
            if self.editor.tick_blink(delta as f32) {
                self.base_mut().queue_redraw();
            }
        }
    }

    fn draw(&mut self) {
        let canvas_rid = self.base().get_canvas_item();

        // 1. Dibujar rectángulos de selección si está en edición
        if self.editor.is_editing && self.editor.has_selection() {
            if let Some((s, e)) = self.editor.selected_range() {
                let rects = self.layout.selection_rects(s, e);
                let sel_col = self.selection_color;
                for r in rects {
                    self.base_mut().draw_rect(r, sel_col);
                }
            }
        }

        // 2. Dibujar el texto completo a través del TextParagraph (soporta estilos y colores por letra)
        self.layout.draw(&self.doc, canvas_rid, Vector2::ZERO);

        // 2b. Subrayado / tachado por run (el layout no los dibujaba: el
        // estilo se guardaba pero nunca se veía). Se usan los rectángulos de
        // línea del rango (los mismos de la selección).
        let mut decos: Vec<(Rect2, Color)> = Vec::new();
        let mut pos = 0usize;
        for r in &self.doc.runs {
            let (s, e) = (pos, pos + r.length);
            pos = e;
            if r.length == 0 || !(r.style.underline || r.style.strikethrough) {
                continue;
            }
            let mut col = r.style.fill_color;
            col.a *= r.style.opacity;
            let thick = (r.style.font_size * 0.06).max(1.0);
            for lr in self.layout.selection_rects(s, e) {
                if r.style.underline {
                    let y = lr.position.y + lr.size.y * 0.86;
                    decos.push((Rect2::new(Vector2::new(lr.position.x, y), Vector2::new(lr.size.x, thick)), col));
                }
                if r.style.strikethrough {
                    let y = lr.position.y + lr.size.y * 0.52;
                    decos.push((Rect2::new(Vector2::new(lr.position.x, y), Vector2::new(lr.size.x, thick)), col));
                }
            }
        }
        for (rect, col) in decos {
            self.base_mut().draw_rect(rect, col);
        }

        // 3. Dibujar el cursor parpadeante (caret)
        if self.editor.is_editing && self.editor.caret_visible {
            let caret_r = self.layout.caret_rect(self.editor.caret_index);
            let acc_col = self.accent_color;
            self.base_mut().draw_rect(caret_r, acc_col);
        }

        // 4. Indicador de desbordamiento (overset text) estilo InDesign / Affinity
        if self.layout.is_overset && self.editor.is_editing {
            let p_sz = self.layout.frame_size;
            let square_r = Rect2::new(Vector2::new(p_sz.x - 12.0, p_sz.y - 12.0), Vector2::new(10.0, 10.0));
            self.base_mut().draw_rect(square_r, Color::from_rgb(0.9, 0.1, 0.1));
        }
    }

    fn gui_input(&mut self, event: Gd<InputEvent>) {
        if let Ok(mb) = event.clone().try_cast::<InputEventMouseButton>() {
            if mb.get_button_index() == MouseButton::LEFT {
                if mb.is_pressed() {
                    let click_pos = mb.get_position();
                    let hit_char = self.layout.hit_test(click_pos);
                    let total = self.doc.char_count();

                    let now_msec = Time::singleton().get_ticks_msec();
                    let is_multi = (now_msec.saturating_sub(self.last_click_msec) < 400)
                        && (click_pos.distance_to(self.last_click_pos) < 8.0);
                    if is_multi || mb.is_double_click() {
                        self.click_count = (self.click_count + 1).max(2);
                    } else {
                        self.click_count = 1;
                    }
                    self.last_click_msec = now_msec;
                    self.last_click_pos = click_pos;

                    if !self.editor.is_editing {
                        if self.click_count >= 2 || mb.is_double_click() {
                            self.start_editing_internal();
                        } else {
                            return;
                        }
                    }

                    let shift = mb.is_shift_pressed();

                    match self.click_count {
                        1 => {
                            if shift {
                                self.editor.move_caret(hit_char, true, total);
                            } else {
                                self.editor.move_caret(hit_char, false, total);
                                self.editor.is_mouse_dragging = true;
                            }
                        }
                        2 => {
                            self.editor.select_word_at(hit_char, &self.doc.text);
                        }
                        3 => {
                            self.editor.select_paragraph_at(hit_char, &self.doc.text);
                        }
                        _ => {
                            self.editor.select_all(total);
                        }
                    }
                    self.base_mut().grab_focus();
                    self.notify_selection_changed();
                    self.base_mut().queue_redraw();
                } else {
                    self.editor.is_mouse_dragging = false;
                }
            }
        } else if let Ok(mm) = event.clone().try_cast::<InputEventMouseMotion>() {
            if self.editor.is_editing && self.editor.is_mouse_dragging {
                let hit_char = self.layout.hit_test(mm.get_position());
                let total = self.doc.char_count();
                self.editor.move_caret(hit_char, true, total);
                self.notify_selection_changed();
                self.base_mut().queue_redraw();
            }
        } else if let Ok(key) = event.clone().try_cast::<InputEventKey>() {
            if self.editor.is_editing && key.is_pressed() {
                // Consumir la tecla: si no, sigue hasta los atajos globales del
                // lienzo (letras = cambio de herramienta) y cierra la edición.
                self.base_mut().accept_event();
                self.handle_key_input(&key);
            }
        }
    }
}

// Métodos auxiliares internos de Rust
impl VectorRichText {
    pub fn start_editing_internal(&mut self) {
        if !self.editor.is_editing {
            let total = self.doc.char_count();
            let cur = self.editor.caret_index.min(total);
            self.editor.start_editing(cur, total);
            self.base_mut().set_mouse_filter(MouseFilter::STOP);
            if self.base().is_inside_tree() {
                self.base_mut().grab_focus();
            }
            self.base_mut().emit_signal("editing_started", &[]);
            self.notify_selection_changed();
            self.base_mut().queue_redraw();
        }
    }

    pub fn stop_editing_internal(&mut self) {
        if self.editor.is_editing {
            self.editor.stop_editing();
            self.base_mut().set_mouse_filter(MouseFilter::PASS);
            if self.base().is_inside_tree() {
                self.base_mut().release_focus();
            }
            self.base_mut().emit_signal("editing_finished", &[]);
            self.base_mut().queue_redraw();
        }
    }

    pub fn handle_key_input(&mut self, key: &Gd<InputEventKey>) {
        let code = key.get_keycode();
        let shift = key.is_shift_pressed();
        let ctrl = key.is_ctrl_pressed() || key.is_meta_pressed();
        let total = self.doc.char_count();
        let mut modified_text = false;

        match code {
            Key::LEFT => {
                if ctrl {
                    self.editor.move_by_word(false, shift, &self.doc.text);
                } else {
                    self.editor.move_by_char(-1, shift, total);
                }
                self.notify_selection_changed();
            }
            Key::RIGHT => {
                if ctrl {
                    self.editor.move_by_word(true, shift, &self.doc.text);
                } else {
                    self.editor.move_by_char(1, shift, total);
                }
                self.notify_selection_changed();
            }
            Key::UP => {
                if !self.layout.lines.is_empty() {
                    let cur_idx = self.editor.caret_index;
                    let caret_x = self.layout.caret_rect(cur_idx).position.x;
                    let cur_line_idx = self
                        .layout
                        .lines
                        .iter()
                        .position(|l| cur_idx >= l.char_start && cur_idx <= l.char_end)
                        .unwrap_or(0);
                    if cur_line_idx > 0 {
                        let prev_line = &self.layout.lines[cur_line_idx - 1];
                        let target_y = prev_line.rect.position.y + prev_line.rect.size.y * 0.5;
                        let target_char = self.layout.hit_test(Vector2::new(caret_x, target_y));
                        self.editor.move_caret(target_char, shift, total);
                    } else {
                        self.editor.move_caret(0, shift, total);
                    }
                    self.notify_selection_changed();
                }
            }
            Key::DOWN => {
                if !self.layout.lines.is_empty() {
                    let cur_idx = self.editor.caret_index;
                    let caret_x = self.layout.caret_rect(cur_idx).position.x;
                    let cur_line_idx = self
                        .layout
                        .lines
                        .iter()
                        .position(|l| cur_idx >= l.char_start && cur_idx <= l.char_end)
                        .unwrap_or(0);
                    if cur_line_idx + 1 < self.layout.lines.len() {
                        let next_line = &self.layout.lines[cur_line_idx + 1];
                        let target_y = next_line.rect.position.y + next_line.rect.size.y * 0.5;
                        let target_char = self.layout.hit_test(Vector2::new(caret_x, target_y));
                        self.editor.move_caret(target_char, shift, total);
                    } else {
                        self.editor.move_caret(total, shift, total);
                    }
                    self.notify_selection_changed();
                }
            }
            Key::HOME => {
                let target = if ctrl { 0 } else { self.line_start_for_caret() };
                self.editor.move_caret(target, shift, total);
                self.notify_selection_changed();
            }
            Key::END => {
                let target = if ctrl { total } else { self.line_end_for_caret() };
                self.editor.move_caret(target, shift, total);
                self.notify_selection_changed();
            }
            Key::TAB => {
                self.insert_typed_text("    ");
                modified_text = true;
            }
            Key::BACKSPACE => {
                if let Some((s, e)) = self.editor.selected_range() {
                    self.doc.delete_range(s, e);
                    self.editor.set_selection(s, s, self.doc.char_count());
                    modified_text = true;
                } else if self.editor.caret_index > 0 {
                    let pos = self.editor.caret_index - 1;
                    self.doc.delete_range(pos, pos + 1);
                    self.editor.move_caret(pos, false, self.doc.char_count());
                    modified_text = true;
                }
            }
            Key::DELETE => {
                if let Some((s, e)) = self.editor.selected_range() {
                    self.doc.delete_range(s, e);
                    self.editor.set_selection(s, s, self.doc.char_count());
                    modified_text = true;
                } else if self.editor.caret_index < total {
                    let pos = self.editor.caret_index;
                    self.doc.delete_range(pos, pos + 1);
                    modified_text = true;
                }
            }
            Key::ENTER | Key::KP_ENTER => {
                if ctrl {
                    self.stop_editing_internal();
                    return;
                }
                if self.layout.is_paragraph {
                    self.insert_typed_text("\n");
                    modified_text = true;
                } else {
                    self.stop_editing_internal();
                    return;
                }
            }
            Key::ESCAPE => {
                self.stop_editing_internal();
                return;
            }
            Key::A if ctrl => {
                self.editor.select_all(total);
                self.notify_selection_changed();
            }
            Key::B if ctrl => {
                let (s, e) = self.editor.selected_range().unwrap_or((0, self.doc.char_count()));
                let all_on = self.doc.range_all(s, e, |st| st.bold);
                self.doc.apply_style_range(s, e, |st| st.bold = !all_on);
                modified_text = true;
            }
            Key::I if ctrl => {
                let (s, e) = self.editor.selected_range().unwrap_or((0, self.doc.char_count()));
                let all_on = self.doc.range_all(s, e, |st| st.italic);
                self.doc.apply_style_range(s, e, |st| st.italic = !all_on);
                modified_text = true;
            }
            Key::U if ctrl => {
                let (s, e) = self.editor.selected_range().unwrap_or((0, self.doc.char_count()));
                let all_on = self.doc.range_all(s, e, |st| st.underline);
                self.doc.apply_style_range(s, e, |st| st.underline = !all_on);
                modified_text = true;
            }
            Key::C if ctrl => {
                if let Some((s, e)) = self.editor.selected_range() {
                    let chars: Vec<char> = self.doc.text.chars().collect();
                    let slice: String = chars[s..e].iter().collect();
                    let gstr = GString::from(slice.as_str());
                    let mut ds = DisplayServer::singleton();
                    ds.clipboard_set(&gstr);
                }
            }
            Key::X if ctrl => {
                if let Some((s, e)) = self.editor.selected_range() {
                    let deleted = self.doc.delete_range(s, e);
                    let gstr = GString::from(deleted.as_str());
                    let mut ds = DisplayServer::singleton();
                    ds.clipboard_set(&gstr);
                    self.editor.set_selection(s, s, self.doc.char_count());
                    modified_text = true;
                }
            }
            Key::V if ctrl => {
                let ds = DisplayServer::singleton();
                let clip = ds.clipboard_get().to_string();
                if !clip.is_empty() {
                    self.insert_typed_text(&clip);
                    modified_text = true;
                }
            }
            _ => {
                let u = key.get_unicode();
                if u >= 32 {
                    if let Some(ch) = char::from_u32(u as u32) {
                        self.insert_typed_text(&ch.to_string());
                        modified_text = true;
                    }
                }
            }
        }

        if modified_text {
            self.recalculate();
            let new_txt: GString = self.doc.text.as_str().into();
            self.base_mut().emit_signal("text_changed", &[new_txt.to_variant()]);
        }
        self.base_mut().queue_redraw();
    }

    pub fn insert_typed_text(&mut self, text: &str) {
        if let Some((s, e)) = self.editor.selected_range() {
            self.doc.delete_range(s, e);
            self.editor.caret_index = s;
        }
        let pos = self.editor.caret_index;
        self.doc.insert_text(pos, text);
        let ins_chars = text.chars().count();
        self.editor.move_caret(pos + ins_chars, false, self.doc.char_count());
        self.notify_selection_changed();
    }

    pub fn line_start_for_caret(&self) -> usize {
        for l in &self.layout.lines {
            if self.editor.caret_index >= l.char_start && self.editor.caret_index <= l.char_end {
                return l.char_start;
            }
        }
        0
    }

    pub fn line_end_for_caret(&self) -> usize {
        for l in &self.layout.lines {
            if self.editor.caret_index >= l.char_start && self.editor.caret_index <= l.char_end {
                return l.char_end;
            }
        }
        self.doc.char_count()
    }

    pub fn recalculate(&mut self) {
        // Antes el tema PISABA la fuente de set_font() en cada recálculo: la
        // familia/peso elegidos en FontCore nunca llegaban al editor nativo.
        if !self.explicit_font {
            if let Some(tf) = self.base().get_theme_font("font") {
                self.default_font = Some(tf);
            }
        }
        let old_overset = self.layout.is_overset;
        self.layout.reflow(&self.doc, self.default_font.clone(), &self.style_fonts);

        let min_sz = self.layout.content_size;
        self.base_mut().set_custom_minimum_size(min_sz);
        if !self.layout.is_paragraph {
            self.base_mut().set_size(min_sz);
        }

        if old_overset != self.layout.is_overset {
            let ov = self.layout.is_overset;
            self.base_mut().emit_signal("overset_changed", &[ov.to_variant()]);
        }
    }

    pub fn notify_selection_changed(&mut self) {
        let (s, e) = self.editor.selected_range().unwrap_or((self.editor.caret_index, self.editor.caret_index));
        let caret = self.editor.caret_index as i64;
        let mut base = self.base_mut();
        base.emit_signal("selection_changed", &[(s as i64).to_variant(), (e as i64).to_variant()]);
        base.emit_signal("caret_changed", &[caret.to_variant()]);
    }
}

// Métodos expuestos a la API de Godot
#[godot_api]
impl VectorRichText {
    #[signal]
    fn text_changed(new_text: GString);

    #[signal]
    fn selection_changed(start: i64, end: i64);

    #[signal]
    fn caret_changed(index: i64);

    #[signal]
    fn editing_started();

    #[signal]
    fn editing_finished();

    #[signal]
    fn overset_changed(has_overflow: bool);

    #[func]
    pub fn ping(&self) -> GString {
        "VectopenText GDExtension v0.1.0".into()
    }

    #[func]
    pub fn set_text(&mut self, text: GString) {
        self.doc.set_text(&text.to_string());
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn get_text(&self) -> GString {
        self.doc.text.as_str().into()
    }

    #[func]
    pub fn set_is_paragraph(&mut self, is_para: bool) {
        self.layout.is_paragraph = is_para;
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn get_is_paragraph(&self) -> bool {
        self.layout.is_paragraph
    }

    #[func]
    pub fn set_frame_size(&mut self, size: Vector2) {
        self.layout.set_frame_size(size);
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn get_frame_size(&self) -> Vector2 {
        self.layout.frame_size
    }

    #[func]
    pub fn set_frame_padding(&mut self, left: f32, top: f32, right: f32, bottom: f32) {
        self.layout.frame.padding_left = left.max(0.0);
        self.layout.frame.padding_top = top.max(0.0);
        self.layout.frame.padding_right = right.max(0.0);
        self.layout.frame.padding_bottom = bottom.max(0.0);
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn get_frame_padding(&self) -> Rect2 {
        Rect2::new(
            Vector2::new(self.layout.frame.padding_left, self.layout.frame.padding_top),
            Vector2::new(self.layout.frame.padding_right, self.layout.frame.padding_bottom),
        )
    }

    #[func]
    pub fn set_columns(&mut self, columns: i64, column_gap: f32) {
        self.layout.frame.columns = (columns as u32).max(1);
        self.layout.frame.column_gap = column_gap.max(0.0);
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn get_columns(&self) -> i64 {
        self.layout.frame.columns as i64
    }

    #[func]
    pub fn get_column_gap(&self) -> f32 {
        self.layout.frame.column_gap
    }

    #[func]
    pub fn set_vertical_alignment(&mut self, alignment: GString) {
        self.layout.frame.vertical_alignment = VerticalAlignment::from_str(&alignment.to_string());
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn get_vertical_alignment(&self) -> GString {
        GString::from(self.layout.frame.vertical_alignment.to_str())
    }

    #[func]
    pub fn set_overflow_mode(&mut self, mode: GString) {
        self.layout.frame.overflow_mode = OverflowMode::from_str(&mode.to_string());
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn get_overflow_mode(&self) -> GString {
        GString::from(self.layout.frame.overflow_mode.to_str())
    }

    #[func]
    pub fn get_frame_bounds(&self) -> Vector2 {
        Vector2::new(self.layout.frame.width, self.layout.frame.height)
    }

    #[func]
    pub fn get_content_bounds(&self) -> Vector2 {
        self.layout.content_size
    }

    #[func]
    pub fn get_content_size(&self) -> Vector2 {
        self.layout.content_size
    }

    #[func]
    pub fn is_overset(&self) -> bool {
        self.layout.is_overset
    }

    #[func]
    pub fn is_overflowing(&self) -> bool {
        self.layout.is_overset
    }

    #[func]
    pub fn get_line_count(&self) -> i64 {
        self.layout.lines.len() as i64
    }

    #[func]
    pub fn get_line_rect(&self, line_idx: i64) -> Rect2 {
        if line_idx >= 0 && (line_idx as usize) < self.layout.lines.len() {
            self.layout.lines[line_idx as usize].rect
        } else {
            Rect2::default()
        }
    }

    #[func]
    pub fn start_editing(&mut self) {
        self.start_editing_internal();
    }

    #[func]
    pub fn stop_editing(&mut self) {
        self.stop_editing_internal();
    }

    #[func]
    pub fn commit_editing(&mut self) {
        self.stop_editing_internal();
    }

    #[func]
    pub fn cancel_editing(&mut self) {
        self.stop_editing_internal();
    }

    #[func]
    pub fn is_editing(&self) -> bool {
        self.editor.is_editing
    }

    #[func]
    pub fn get_interaction_state(&self) -> GString {
        let state = if self.editor.is_editing {
            if self.editor.is_mouse_dragging {
                TextInteractionState::Dragging
            } else if self.editor.has_selection() {
                TextInteractionState::Selecting
            } else {
                TextInteractionState::Editing
            }
        } else {
            TextInteractionState::Idle
        };
        GString::from(state.to_str())
    }

    #[func]
    pub fn get_caret_index(&self) -> i64 {
        self.editor.caret_index as i64
    }

    #[func]
    pub fn set_caret_index(&mut self, idx: i64) {
        let total = self.doc.char_count();
        self.editor.move_caret(idx.max(0) as usize, false, total);
        self.notify_selection_changed();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn get_selection_range(&self) -> Vector2i {
        if let Some((s, e)) = self.editor.selected_range() {
            Vector2i::new(s as i32, e as i32)
        } else {
            Vector2i::new(self.editor.caret_index as i32, self.editor.caret_index as i32)
        }
    }

    #[func]
    pub fn set_selection_range(&mut self, start: i64, end: i64) {
        let total = self.doc.char_count();
        self.editor.set_selection(start.max(0) as usize, end.max(0) as usize, total);
        self.notify_selection_changed();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn select_all(&mut self) {
        let total = self.doc.char_count();
        self.editor.select_all(total);
        self.notify_selection_changed();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn deselect(&mut self) {
        self.editor.selection_active = false;
        self.editor.selection_anchor = self.editor.caret_index;
        self.notify_selection_changed();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn get_char_count(&self) -> i64 {
        self.doc.char_count() as i64
    }

    #[func]
    pub fn get_selected_text(&self) -> GString {
        if let Some((s, e)) = self.editor.selected_range() {
            let chars: Vec<char> = self.doc.text.chars().collect();
            let slice: String = chars[s..e].iter().collect();
            slice.as_str().into()
        } else {
            "".into()
        }
    }

    #[func]
    pub fn get_selection(&self) -> Vector2i {
        self.get_selection_range()
    }

    #[func]
    pub fn set_selection(&mut self, start: i64, end: i64) {
        self.set_selection_range(start, end);
    }

    #[func]
    pub fn hit_test(&self, point: Vector2) -> i64 {
        self.layout.hit_test(point) as i64
    }

    #[func]
    pub fn select_word_at(&mut self, char_idx: i64) {
        self.editor.select_word_at(char_idx.max(0) as usize, &self.doc.text);
        self.notify_selection_changed();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn select_paragraph_at(&mut self, char_idx: i64) {
        self.editor.select_paragraph_at(char_idx.max(0) as usize, &self.doc.text);
        self.notify_selection_changed();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn move_by_word(&mut self, forward: bool, extend_selection: bool) {
        self.editor.move_by_word(forward, extend_selection, &self.doc.text);
        self.notify_selection_changed();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn insert_text(&mut self, text: GString) {
        self.insert_typed_text(&text.to_string());
        self.recalculate();
        let new_txt: GString = self.doc.text.as_str().into();
        self.base_mut().emit_signal("text_changed", &[new_txt.to_variant()]);
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn delete_range(&mut self, start: i64, end: i64) {
        let total = self.doc.char_count();
        let s = (start.max(0) as usize).min(total);
        let e = (end.max(0) as usize).min(total);
        if s < e {
            self.doc.delete_range(s, e);
            self.editor.set_selection(s, s, self.doc.char_count());
            self.recalculate();
            let new_txt: GString = self.doc.text.as_str().into();
            self.base_mut().emit_signal("text_changed", &[new_txt.to_variant()]);
            self.notify_selection_changed();
            self.base_mut().queue_redraw();
        }
    }

    #[func]
    pub fn replace_range(&mut self, start: i64, end: i64, text: GString) {
        let total = self.doc.char_count();
        let s = (start.max(0) as usize).min(total);
        let e = (end.max(0) as usize).min(total);
        if s <= e {
            self.doc.delete_range(s, e);
            let ins_str = text.to_string();
            self.doc.insert_text(s, &ins_str);
            let new_pos = s + ins_str.chars().count();
            self.editor.set_selection(new_pos, new_pos, self.doc.char_count());
            self.recalculate();
            let new_txt: GString = self.doc.text.as_str().into();
            self.base_mut().emit_signal("text_changed", &[new_txt.to_variant()]);
            self.notify_selection_changed();
            self.base_mut().queue_redraw();
        }
    }

    // ── Formato de selección ───────────────────────────────────────────────────

    #[func]
    pub fn apply_color_to_selection(&mut self, color: Color) {
        let (s, e) = self.editor.selected_range().unwrap_or((0, self.doc.char_count()));
        self.doc.apply_style_range(s, e, |st| st.fill_color = color);
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn apply_font_size_to_selection(&mut self, size: f32) {
        let (s, e) = self.editor.selected_range().unwrap_or((0, self.doc.char_count()));
        let clamped = size.clamp(4.0, 400.0);
        self.doc.apply_style_range(s, e, |st| st.font_size = clamped);
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn apply_bold_to_selection(&mut self, bold: bool) {
        let (s, e) = self.editor.selected_range().unwrap_or((0, self.doc.char_count()));
        self.doc.apply_style_range(s, e, |st| st.bold = bold);
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn apply_italic_to_selection(&mut self, italic: bool) {
        let (s, e) = self.editor.selected_range().unwrap_or((0, self.doc.char_count()));
        self.doc.apply_style_range(s, e, |st| st.italic = italic);
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn apply_underline_to_selection(&mut self, underline: bool) {
        let (s, e) = self.editor.selected_range().unwrap_or((0, self.doc.char_count()));
        self.doc.apply_style_range(s, e, |st| st.underline = underline);
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn apply_stroke_to_selection(&mut self, color: Color, width: f32) {
        let (s, e) = self.editor.selected_range().unwrap_or((0, self.doc.char_count()));
        self.doc.apply_style_range(s, e, |st| {
            st.stroke_color = color;
            st.stroke_width = width.max(0.0);
        });
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn apply_opacity_to_selection(&mut self, opacity: f32) {
        let (s, e) = self.editor.selected_range().unwrap_or((0, self.doc.char_count()));
        self.doc.apply_style_range(s, e, |st| {
            st.opacity = opacity.clamp(0.0, 1.0);
        });
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn apply_strikethrough_to_selection(&mut self, strikethrough: bool) {
        let (s, e) = self.editor.selected_range().unwrap_or((0, self.doc.char_count()));
        self.doc.apply_style_range(s, e, |st| {
            st.strikethrough = strikethrough;
        });
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn apply_baseline_shift_to_selection(&mut self, shift: f32) {
        let (s, e) = self.editor.selected_range().unwrap_or((0, self.doc.char_count()));
        self.doc.apply_style_range(s, e, |st| {
            st.baseline_shift = shift;
        });
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn apply_letter_spacing_to_selection(&mut self, spacing: f32) {
        let (s, e) = self.editor.selected_range().unwrap_or((0, self.doc.char_count()));
        self.doc.apply_style_range(s, e, |st| {
            st.letter_spacing = spacing;
        });
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    // ── Formato de párrafo ─────────────────────────────────────────────────────

    #[func]
    pub fn set_paragraph_align(&mut self, align: GString) {
        self.doc.para_style.align = HAlign::from_str(&align.to_string());
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn get_paragraph_align(&self) -> GString {
        self.doc.para_style.align.to_str().into()
    }

    #[func]
    pub fn set_paragraph_line_spacing(&mut self, spacing: f32) {
        self.doc.para_style.line_spacing = spacing.clamp(-50.0, 200.0);
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn set_paragraph_indents(&mut self, left: f32, right: f32, first: f32) {
        self.doc.para_style.indent_left = left.clamp(0.0, 500.0);
        self.doc.para_style.indent_right = right.clamp(0.0, 500.0);
        self.doc.para_style.indent_first = first.clamp(-500.0, 500.0);
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    // ── Metadatos de runs compatibles con Vectopen ─────────────────────────────

    #[func]
    pub fn get_runs_meta(&self) -> Array<VarDictionary> {
        self.doc.to_meta_runs()
    }

    #[func]
    pub fn set_runs_meta(&mut self, runs: Variant) {
        if let Ok(arr) = runs.try_to::<Array<VarDictionary>>() {
            self.doc.from_meta_runs(&arr);
        } else if let Ok(arr) = runs.try_to::<Array<Variant>>() {
            let mut dict_arr = Array::<VarDictionary>::new();
            for v in arr.iter_shared() {
                if let Ok(d) = v.try_to::<VarDictionary>() {
                    dict_arr.push(&d);
                }
            }
            self.doc.from_meta_runs(&dict_arr);
        }
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn set_text_color(&mut self, color: Color) {
        self.apply_color_to_selection(color);
    }

    #[func]
    pub fn get_text_color(&self) -> Color {
        self.doc.runs.first().map(|r| r.style.fill_color).unwrap_or(Color::from_rgb(0.0, 0.0, 0.0))
    }

    #[func]
    pub fn set_stroke_color(&mut self, color: Color) {
        let sw = self.doc.runs.first().map(|r| r.style.stroke_width).unwrap_or(0.0);
        self.apply_stroke_to_selection(color, sw);
    }

    #[func]
    pub fn get_stroke_color(&self) -> Color {
        self.doc.runs.first().map(|r| r.style.stroke_color).unwrap_or(Color::from_rgb(0.0, 0.0, 0.0))
    }

    #[func]
    pub fn set_stroke_width(&mut self, width: f32) {
        let sc = self.doc.runs.first().map(|r| r.style.stroke_color).unwrap_or(Color::from_rgb(0.0, 0.0, 0.0));
        self.apply_stroke_to_selection(sc, width);
    }

    #[func]
    pub fn get_stroke_width(&self) -> f32 {
        self.doc.runs.first().map(|r| r.style.stroke_width).unwrap_or(0.0)
    }

    #[func]
    pub fn set_font(&mut self, font: Gd<Font>) {
        self.default_font = Some(font);
        self.explicit_font = true;
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    /// Fuentes reales para runs en negrita, cursiva y negrita+cursiva
    /// (p.ej. Inter-Bold / Inter-Italic / Inter-BoldItalic de FontCore).
    #[func]
    pub fn set_style_fonts(&mut self, bold: Option<Gd<Font>>, italic: Option<Gd<Font>>, bold_italic: Option<Gd<Font>>) {
        self.style_fonts = StyleFonts { bold, italic, bold_italic };
        self.recalculate();
        self.base_mut().queue_redraw();
    }

    #[func]
    pub fn set_font_size(&mut self, size: f32) {
        self.apply_font_size_to_selection(size);
    }

    #[func]
    pub fn get_font_size(&self) -> f32 {
        self.doc.runs.first().map(|r| r.style.font_size).unwrap_or(24.0)
    }
}
