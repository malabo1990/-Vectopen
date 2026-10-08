use unicode_segmentation::UnicodeSegmentation;

#[derive(Clone, Debug)]
pub struct EditorState {
    pub is_editing: bool,
    pub caret_index: usize,
    pub selection_anchor: usize, // donde empezó la selección
    pub selection_active: bool,
    pub caret_blink_timer: f32,
    pub caret_visible: bool,
    pub is_mouse_dragging: bool,
}

impl Default for EditorState {
    fn default() -> Self {
        Self {
            is_editing: false,
            caret_index: 0,
            selection_anchor: 0,
            selection_active: false,
            caret_blink_timer: 0.0,
            caret_visible: true,
            is_mouse_dragging: false,
        }
    }
}

impl EditorState {
    pub fn start_editing(&mut self, initial_caret: usize, total_chars: usize) {
        self.is_editing = true;
        self.caret_index = initial_caret.min(total_chars);
        self.selection_anchor = self.caret_index;
        self.selection_active = false;
        self.caret_blink_timer = 0.0;
        self.caret_visible = true;
        self.is_mouse_dragging = false;
    }

    pub fn stop_editing(&mut self) {
        self.is_editing = false;
        self.selection_active = false;
        self.caret_visible = false;
        self.is_mouse_dragging = false;
    }

    pub fn has_selection(&self) -> bool {
        self.selection_active && self.caret_index != self.selection_anchor
    }

    pub fn selected_range(&self) -> Option<(usize, usize)> {
        if !self.has_selection() {
            None
        } else {
            let s = self.caret_index.min(self.selection_anchor);
            let e = self.caret_index.max(self.selection_anchor);
            Some((s, e))
        }
    }

    pub fn select_all(&mut self, total_chars: usize) {
        self.selection_anchor = 0;
        self.caret_index = total_chars;
        self.selection_active = total_chars > 0;
        self.reset_blink();
    }

    pub fn clear_selection(&mut self) {
        self.selection_anchor = self.caret_index;
        self.selection_active = false;
    }

    pub fn set_selection(&mut self, start: usize, end: usize, total_chars: usize) {
        let s = start.min(total_chars);
        let e = end.min(total_chars);
        self.selection_anchor = s;
        self.caret_index = e;
        self.selection_active = s != e;
        self.reset_blink();
    }

    pub fn move_caret(&mut self, new_idx: usize, extend_selection: bool, total_chars: usize) {
        let clamped = new_idx.min(total_chars);
        if extend_selection {
            if !self.selection_active {
                self.selection_anchor = self.caret_index;
                self.selection_active = true;
            }
        } else {
            self.selection_active = false;
            self.selection_anchor = clamped;
        }
        self.caret_index = clamped;
        self.reset_blink();
    }

    pub fn move_by_char(&mut self, delta: i32, extend_selection: bool, total_chars: usize) {
        let new_pos = if delta < 0 {
            self.caret_index.saturating_sub((-delta) as usize)
        } else {
            (self.caret_index + delta as usize).min(total_chars)
        };
        self.move_caret(new_pos, extend_selection, total_chars);
    }

    pub fn move_by_word(&mut self, forward: bool, extend_selection: bool, text: &str) {
        let total_chars = text.chars().count();
        if total_chars == 0 {
            self.move_caret(0, extend_selection, 0);
            return;
        }

        let mut boundaries: Vec<usize> = Vec::new();
        for (byte_offset, _) in text.split_word_bound_indices() {
            boundaries.push(text[..byte_offset].chars().count());
        }
        boundaries.push(total_chars);
        boundaries.dedup();

        if forward {
            let mut target = total_chars;
            for &b in &boundaries {
                if b > self.caret_index {
                    target = b;
                    break;
                }
            }
            self.move_caret(target, extend_selection, total_chars);
        } else {
            let mut target = 0;
            for &b in boundaries.iter().rev() {
                if b < self.caret_index {
                    target = b;
                    break;
                }
            }
            self.move_caret(target, extend_selection, total_chars);
        }
    }

    /// Selecciona la palabra completa que contiene `char_idx`
    pub fn select_word_at(&mut self, char_idx: usize, text: &str) {
        let total_chars = text.chars().count();
        if total_chars == 0 {
            self.set_selection(0, 0, 0);
            return;
        }
        let target = char_idx.min(total_chars);
        let mut start = 0;
        let mut end = total_chars;

        let mut words: Vec<(usize, usize, bool)> = Vec::new();
        for (byte_offset, word) in text.split_word_bound_indices() {
            let w_start = text[..byte_offset].chars().count();
            let w_chars = word.chars().count();
            let w_end = w_start + w_chars;
            let is_word = word.chars().any(|c| c.is_alphanumeric());
            words.push((w_start, w_end, is_word));
        }

        let mut found = false;
        for i in 0..words.len() {
            let (w_start, w_end, is_word) = words[i];
            if target >= w_start && target < w_end {
                // Si el clic cayó exactamente al inicio de un separador/espacio y el segmento anterior
                // era una palabra real, priorizamos la palabra contigua anterior.
                if !is_word && target == w_start && i > 0 && words[i - 1].2 {
                    start = words[i - 1].0;
                    end = words[i - 1].1;
                } else {
                    start = w_start;
                    end = w_end;
                }
                found = true;
                break;
            }
        }

        // Si cayó al final de una palabra o al final del texto:
        if !found {
            if let Some((w_start, w_end, _)) = words.iter().filter(|(_, w_end, _)| *w_end == target).last() {
                start = *w_start;
                end = *w_end;
            } else if let Some((w_start, w_end, _)) = words.last() {
                start = *w_start;
                end = *w_end;
            }
        }

        self.set_selection(start, end, total_chars);
    }

    /// Selecciona el párrafo completo que contiene `char_idx`
    pub fn select_paragraph_at(&mut self, char_idx: usize, text: &str) {
        let total_chars = text.chars().count();
        if total_chars == 0 {
            self.set_selection(0, 0, 0);
            return;
        }
        let chars: Vec<char> = text.chars().collect();
        let target = char_idx.min(total_chars);

        let mut start = 0;
        for i in (0..target).rev() {
            if chars.get(i) == Some(&'\n') {
                start = i + 1;
                break;
            }
        }

        let mut end = total_chars;
        for i in target..total_chars {
            if chars.get(i) == Some(&'\n') {
                end = i;
                break;
            }
        }

        self.set_selection(start, end, total_chars);
    }

    pub fn reset_blink(&mut self) {
        self.caret_blink_timer = 0.0;
        self.caret_visible = true;
    }

    /// Actualiza el temporizador de parpadeo (500ms visible / 500ms oculto)
    pub fn tick_blink(&mut self, delta: f32) -> bool {
        if !self.is_editing {
            return false;
        }
        self.caret_blink_timer += delta;
        let old_vis = self.caret_visible;
        self.caret_visible = (self.caret_blink_timer % 1.0) < 0.55;
        self.caret_visible != old_vis
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_select_word_at() {
        let text = "Hola mundo editorial";
        let mut editor = EditorState::default();

        // Clic en 'H', 'o', 'l', 'a'
        editor.select_word_at(0, text);
        assert_eq!(editor.selected_range(), Some((0, 4)));

        editor.select_word_at(2, text);
        assert_eq!(editor.selected_range(), Some((0, 4)));

        // Clic justo en el límite entre "Hola" y " "
        editor.select_word_at(4, text);
        assert_eq!(editor.selected_range(), Some((0, 4)));

        // Clic en "mundo"
        editor.select_word_at(6, text);
        assert_eq!(editor.selected_range(), Some((5, 10)));

        // Clic al final del texto
        editor.select_word_at(20, text);
        assert_eq!(editor.selected_range(), Some((11, 20)));
    }

    #[test]
    fn test_select_paragraph_at() {
        let text = "Párrafo uno.\nPárrafo dos con más texto.\nPárrafo tres.";
        let mut editor = EditorState::default();

        // En el primer párrafo
        editor.select_paragraph_at(5, text);
        assert_eq!(editor.selected_range(), Some((0, 12)));

        // En el segundo párrafo
        editor.select_paragraph_at(15, text);
        assert_eq!(editor.selected_range(), Some((13, 39)));

        // En el tercer párrafo
        editor.select_paragraph_at(45, text);
        assert_eq!(editor.selected_range(), Some((40, 53)));
    }

    #[test]
    fn test_move_by_word() {
        let text = "Hola mundo";
        let mut editor = EditorState::default();
        editor.move_caret(0, false, 10);

        editor.move_by_word(true, false, text);
        assert_eq!(editor.caret_index, 4);

        editor.move_by_word(true, false, text);
        assert_eq!(editor.caret_index, 5);

        editor.move_by_word(true, false, text);
        assert_eq!(editor.caret_index, 10);

        editor.move_by_word(false, false, text);
        assert_eq!(editor.caret_index, 5);
    }
}
