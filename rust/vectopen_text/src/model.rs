use godot::builtin::{Array, Color, Dictionary, Variant};
use godot::meta::ToGodot;

pub type VarDictionary = Dictionary<Variant, Variant>;

#[derive(Clone, Debug, PartialEq)]
pub struct TextStyle {
    pub font_family: String,
    pub font_size: f32,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub strikethrough: bool,
    pub fill_color: Color,
    pub opacity: f32,
    pub stroke_color: Color,
    pub stroke_width: f32,
    pub letter_spacing: f32,
    pub baseline_shift: f32,
    pub weight: f32,
}

impl Default for TextStyle {
    fn default() -> Self {
        Self {
            font_family: String::new(),
            font_size: 24.0,
            bold: false,
            italic: false,
            underline: false,
            strikethrough: false,
            fill_color: Color::from_rgb(0.0, 0.0, 0.0),
            opacity: 1.0,
            stroke_color: Color::from_rgb(0.0, 0.0, 0.0),
            stroke_width: 0.0,
            letter_spacing: 0.0,
            baseline_shift: 0.0,
            weight: 400.0,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HAlign {
    Left,
    Center,
    Right,
    Justify,
}

impl HAlign {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "center" => Self::Center,
            "right" => Self::Right,
            "justify" | "fill" => Self::Justify,
            _ => Self::Left,
        }
    }

    pub fn to_str(self) -> &'static str {
        match self {
            Self::Left => "left",
            Self::Center => "center",
            Self::Right => "right",
            Self::Justify => "justify",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum TextDirection {
    #[default]
    LeftToRight,
    RightToLeft,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ParagraphStyle {
    pub align: HAlign,
    pub line_spacing: f32,
    pub indent_left: f32,
    pub indent_right: f32,
    pub indent_first: f32,
    pub space_before: f32,
    pub space_after: f32,
    pub direction: TextDirection,
}

impl Default for ParagraphStyle {
    fn default() -> Self {
        Self {
            align: HAlign::Left,
            line_spacing: 4.0,
            indent_left: 0.0,
            indent_right: 0.0,
            indent_first: 0.0,
            space_before: 0.0,
            space_after: 0.0,
            direction: TextDirection::LeftToRight,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum VerticalAlignment {
    #[default]
    Top,
    Center,
    Bottom,
    Justify,
}

impl VerticalAlignment {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "center" | "middle" => Self::Center,
            "bottom" => Self::Bottom,
            "justify" => Self::Justify,
            _ => Self::Top,
        }
    }

    pub fn to_str(self) -> &'static str {
        match self {
            Self::Top => "top",
            Self::Center => "center",
            Self::Bottom => "bottom",
            Self::Justify => "justify",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum OverflowMode {
    #[default]
    Clip,
    Visible,
    Thread,
}

impl OverflowMode {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "visible" => Self::Visible,
            "thread" => Self::Thread,
            _ => Self::Clip,
        }
    }

    pub fn to_str(self) -> &'static str {
        match self {
            Self::Clip => "clip",
            Self::Visible => "visible",
            Self::Thread => "thread",
        }
    }
}

/// Marco de texto como entidad de primera clase (TextFrame)
#[derive(Clone, Debug, PartialEq)]
pub struct TextFrame {
    pub width: f32,
    pub height: f32,
    pub padding_left: f32,
    pub padding_right: f32,
    pub padding_top: f32,
    pub padding_bottom: f32,
    pub columns: u32,
    pub column_gap: f32,
    pub vertical_alignment: VerticalAlignment,
    pub overflow_mode: OverflowMode,
    pub thread_next: Option<String>,
    pub thread_previous: Option<String>,
}

impl Default for TextFrame {
    fn default() -> Self {
        Self {
            width: 350.0,
            height: 190.0,
            padding_left: 0.0,
            padding_right: 0.0,
            padding_top: 0.0,
            padding_bottom: 0.0,
            columns: 1,
            column_gap: 12.0,
            vertical_alignment: VerticalAlignment::Top,
            overflow_mode: OverflowMode::Clip,
            thread_next: None,
            thread_previous: None,
        }
    }
}

impl TextFrame {
    pub fn content_width(&self) -> f32 {
        (self.width - self.padding_left - self.padding_right).max(10.0)
    }

    pub fn content_height(&self) -> f32 {
        (self.height - self.padding_top - self.padding_bottom).max(10.0)
    }

    pub fn column_width(&self) -> f32 {
        let cw = self.content_width();
        if self.columns <= 1 {
            cw
        } else {
            let total_gaps = (self.columns - 1) as f32 * self.column_gap;
            ((cw - total_gaps) / self.columns as f32).max(10.0)
        }
    }
}

/// Límites del marco geométrico
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct FrameBounds {
    pub width: f32,
    pub height: f32,
}

/// Límites del contenido textual calculado por el layout
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct ContentBounds {
    pub width: f32,
    pub height: f32,
}

/// Máquina de estados de interacción para el subsistema de texto
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum TextInteractionState {
    #[default]
    Idle,
    Selected,
    Editing,
    Selecting,
    Dragging,
    Transforming,
    Committing,
}

impl TextInteractionState {
    pub fn to_str(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Selected => "selected",
            Self::Editing => "editing",
            Self::Selecting => "selecting",
            Self::Dragging => "dragging",
            Self::Transforming => "transforming",
            Self::Committing => "committing",
        }
    }
}

/// Representación absoluta de un tramo continuo de caracteres con mismo estilo
#[derive(Clone, Debug, PartialEq)]
pub struct CharacterRun {
    pub start: usize,
    pub end: usize,
    pub style: TextStyle,
}

/// Tramo de texto relativo para particionado y edición eficiente
#[derive(Clone, Debug, PartialEq)]
pub struct TextRun {
    pub length: usize, // en caracteres unicode
    pub style: TextStyle,
}

impl TextRun {
    pub fn to_character_run(&self, start: usize) -> CharacterRun {
        CharacterRun {
            start,
            end: start + self.length,
            style: self.style.clone(),
        }
    }
}

#[derive(Clone, Debug)]
pub struct TextDocument {
    pub text: String,
    pub runs: Vec<TextRun>,
    pub para_style: ParagraphStyle,
}

impl Default for TextDocument {
    fn default() -> Self {
        Self::new("")
    }
}

impl TextDocument {
    pub fn new(initial_text: &str) -> Self {
        let len = initial_text.chars().count();
        let default_run = TextRun {
            length: len,
            style: TextStyle::default(),
        };
        let runs = if len > 0 { vec![default_run] } else { vec![] };
        Self {
            text: initial_text.to_string(),
            runs,
            para_style: ParagraphStyle::default(),
        }
    }

    pub fn char_count(&self) -> usize {
        self.text.chars().count()
    }

    pub fn get_style_at(&self, mut char_idx: usize) -> TextStyle {
        if self.runs.is_empty() {
            return TextStyle::default();
        }
        for r in &self.runs {
            if char_idx < r.length {
                return r.style.clone();
            }
            char_idx -= r.length;
        }
        self.runs.last().map(|r| r.style.clone()).unwrap_or_default()
    }

    pub fn set_text(&mut self, new_text: &str) {
        let new_len = new_text.chars().count();
        let base_style = if let Some(first) = self.runs.first() {
            first.style.clone()
        } else {
            TextStyle::default()
        };
        self.text = new_text.to_string();
        self.runs = if new_len > 0 {
            vec![TextRun {
                length: new_len,
                style: base_style,
            }]
        } else {
            vec![]
        };
    }

    /// Inserta texto en la posición de carácter `char_idx`
    pub fn insert_text(&mut self, char_idx: usize, insert_str: &str) {
        let insert_len = insert_str.chars().count();
        if insert_len == 0 {
            return;
        }

        let total_chars = self.char_count();
        let clamped_idx = char_idx.min(total_chars);

        let byte_pos = self
            .text
            .char_indices()
            .nth(clamped_idx)
            .map(|(i, _)| i)
            .unwrap_or(self.text.len());
        self.text.insert_str(byte_pos, insert_str);

        if self.runs.is_empty() {
            self.runs.push(TextRun {
                length: insert_len,
                style: TextStyle::default(),
            });
            return;
        }

        let mut acc = 0;
        let mut inserted = false;
        for r in self.runs.iter_mut() {
            if clamped_idx <= acc + r.length {
                r.length += insert_len;
                inserted = true;
                break;
            }
            acc += r.length;
        }

        if !inserted {
            if let Some(last) = self.runs.last_mut() {
                last.length += insert_len;
            }
        }
    }

    /// Elimina el rango [start, end) de caracteres
    pub fn delete_range(&mut self, start: usize, end: usize) -> String {
        let total_chars = self.char_count();
        let s = start.min(end).min(total_chars);
        let e = start.max(end).min(total_chars);
        if s == e {
            return String::new();
        }

        let byte_start = self.text.char_indices().nth(s).map(|(i, _)| i).unwrap_or(self.text.len());
        let byte_end = self.text.char_indices().nth(e).map(|(i, _)| i).unwrap_or(self.text.len());
        let deleted = self.text[byte_start..byte_end].to_string();
        self.text.replace_range(byte_start..byte_end, "");

        let to_remove = e - s;
        let mut remaining_to_remove = to_remove;
        let mut pos = 0;
        let mut new_runs = Vec::new();

        for r in self.runs.drain(..) {
            let r_start = pos;
            let r_end = pos + r.length;
            pos = r_end;

            if r_end <= s || r_start >= e {
                new_runs.push(r);
            } else {
                let overlap_start = r_start.max(s);
                let overlap_end = r_end.min(e);
                let overlap_len = overlap_end - overlap_start;

                let left_len = overlap_start.saturating_sub(r_start);
                let right_len = r_end.saturating_sub(overlap_end);

                if left_len > 0 {
                    new_runs.push(TextRun {
                        length: left_len,
                        style: r.style.clone(),
                    });
                }
                if right_len > 0 {
                    new_runs.push(TextRun {
                        length: right_len,
                        style: r.style.clone(),
                    });
                }
                remaining_to_remove = remaining_to_remove.saturating_sub(overlap_len);
            }
        }

        self.runs = new_runs;
        self.merge_runs();
        deleted
    }

    /// Aplica una mutación de estilo a los caracteres en el rango [start, end)
    pub fn apply_style_range<F: Fn(&mut TextStyle)>(&mut self, start: usize, end: usize, f: F) {
        let total_chars = self.char_count();
        let s = start.min(end).min(total_chars);
        let e = start.max(end).min(total_chars);
        if s >= e || self.runs.is_empty() {
            return;
        }

        let mut out: Vec<TextRun> = Vec::new();
        let mut pos = 0;

        for r in self.runs.drain(..) {
            let r_start = pos;
            let r_end = pos + r.length;
            pos = r_end;

            if r_end <= s || r_start >= e {
                out.push(r);
            } else {
                let part1_len = s.saturating_sub(r_start);
                if part1_len > 0 {
                    out.push(TextRun {
                        length: part1_len,
                        style: r.style.clone(),
                    });
                }

                let mid_start = r_start.max(s);
                let mid_end = r_end.min(e);
                let mid_len = mid_end - mid_start;
                if mid_len > 0 {
                    let mut modified_style = r.style.clone();
                    f(&mut modified_style);
                    out.push(TextRun {
                        length: mid_len,
                        style: modified_style,
                    });
                }

                let part3_len = r_end.saturating_sub(e);
                if part3_len > 0 {
                    out.push(TextRun {
                        length: part3_len,
                        style: r.style.clone(),
                    });
                }
            }
        }

        self.runs = out;
        self.merge_runs();
    }

    /// Fusiona runs adyacentes que comparten exactamente el mismo estilo
    pub fn merge_runs(&mut self) {
        if self.runs.len() <= 1 {
            return;
        }
        let mut merged: Vec<TextRun> = Vec::new();
        for r in self.runs.drain(..) {
            if r.length == 0 {
                continue;
            }
            if let Some(prev) = merged.last_mut() {
                if prev.style == r.style {
                    prev.length += r.length;
                    continue;
                }
            }
            merged.push(r);
        }
        self.runs = merged;
    }

    /// Serializa los runs a Array de Dictionary compatible con Vectopen
    pub fn to_meta_runs(&self) -> Array<VarDictionary> {
        let mut arr = Array::new();
        for r in &self.runs {
            let mut d = VarDictionary::new();
            d.set("length", &(r.length as i64).to_variant());
            d.set("color", &r.style.fill_color.to_variant());
            d.set("opacity", &r.style.opacity.to_variant());
            d.set("size", &r.style.font_size.to_variant());
            d.set("bold", &r.style.bold.to_variant());
            d.set("italic", &r.style.italic.to_variant());
            d.set("underline", &r.style.underline.to_variant());
            d.set("strikethrough", &r.style.strikethrough.to_variant());
            d.set("stroke_color", &r.style.stroke_color.to_variant());
            d.set("stroke_width", &r.style.stroke_width.to_variant());
            d.set("letter_spacing", &r.style.letter_spacing.to_variant());
            d.set("baseline_shift", &r.style.baseline_shift.to_variant());
            d.set("weight", &r.style.weight.to_variant());
            arr.push(&d);
        }
        arr
    }

    /// Carga los runs desde un Array de Dictionary de Vectopen
    pub fn from_meta_runs(&mut self, arr: &Array<VarDictionary>) {
        if arr.is_empty() {
            let len = self.char_count();
            self.runs = if len > 0 {
                vec![TextRun {
                    length: len,
                    style: TextStyle::default(),
                }]
            } else {
                vec![]
            };
            return;
        }

        let mut runs = Vec::new();
        for i in 0..arr.len() {
            let Some(d) = arr.get(i) else { continue };
            let len = d.get("length").and_then(|v| v.try_to::<i64>().ok()).unwrap_or(0) as usize;
            if len == 0 {
                continue;
            }
            let mut style = TextStyle::default();
            if let Some(c) = d.get("color").and_then(|v| v.try_to::<Color>().ok()) {
                style.fill_color = c;
            }
            if let Some(op) = d.get("opacity").and_then(|v| v.try_to::<f32>().ok()) {
                style.opacity = op;
            }
            if let Some(s) = d.get("size").and_then(|v| v.try_to::<f32>().ok()) {
                style.font_size = s;
            }
            if let Some(b) = d.get("bold").and_then(|v| v.try_to::<bool>().ok()) {
                style.bold = b;
            }
            if let Some(it) = d.get("italic").and_then(|v| v.try_to::<bool>().ok()) {
                style.italic = it;
            }
            if let Some(u) = d.get("underline").and_then(|v| v.try_to::<bool>().ok()) {
                style.underline = u;
            }
            if let Some(st) = d.get("strikethrough").and_then(|v| v.try_to::<bool>().ok()) {
                style.strikethrough = st;
            }
            if let Some(sc) = d.get("stroke_color").and_then(|v| v.try_to::<Color>().ok()) {
                style.stroke_color = sc;
            }
            if let Some(sw) = d.get("stroke_width").and_then(|v| v.try_to::<f32>().ok()) {
                style.stroke_width = sw;
            }
            if let Some(ls) = d.get("letter_spacing").and_then(|v| v.try_to::<f32>().ok()) {
                style.letter_spacing = ls;
            }
            if let Some(bs) = d.get("baseline_shift").and_then(|v| v.try_to::<f32>().ok()) {
                style.baseline_shift = bs;
            }
            if let Some(w) = d.get("weight").and_then(|v| v.try_to::<f32>().ok()) {
                style.weight = w;
            }
            runs.push(TextRun { length: len, style });
        }
        self.runs = runs;
        self.merge_runs();
    }

    /// Retorna la lista de tramos con offsets absolutos [start..end)
    pub fn get_character_runs(&self) -> Vec<CharacterRun> {
        let mut result = Vec::new();
        let mut offset = 0;
        for r in &self.runs {
            result.push(r.to_character_run(offset));
            offset += r.length;
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_text_frame_content_and_columns() {
        let mut frame = TextFrame::default();
        frame.width = 400.0;
        frame.height = 200.0;
        frame.padding_left = 10.0;
        frame.padding_right = 10.0;
        frame.padding_top = 5.0;
        frame.padding_bottom = 5.0;

        assert_eq!(frame.content_width(), 380.0);
        assert_eq!(frame.content_height(), 190.0);
        assert_eq!(frame.column_width(), 380.0);

        frame.columns = 2;
        frame.column_gap = 20.0;
        // (380 - 20) / 2 = 180.0
        assert_eq!(frame.column_width(), 180.0);
    }

    #[test]
    fn test_character_runs_conversion() {
        let mut doc = TextDocument::new("Hello World");
        assert_eq!(doc.char_count(), 11);
        doc.apply_style_range(0, 5, |s| {
            s.bold = true;
            s.fill_color = Color::from_rgb(1.0, 0.0, 0.0);
        });

        let char_runs = doc.get_character_runs();
        assert_eq!(char_runs.len(), 2);
        assert_eq!(char_runs[0].start, 0);
        assert_eq!(char_runs[0].end, 5);
        assert!(char_runs[0].style.bold);
        assert_eq!(char_runs[1].start, 5);
        assert_eq!(char_runs[1].end, 11);
        assert!(!char_runs[1].style.bold);
    }

    #[test]
    fn test_bounds_and_states() {
        let fb = FrameBounds { width: 400.0, height: 200.0 };
        let cb = ContentBounds { width: 380.0, height: 86.0 };
        assert_eq!(fb.width, 400.0);
        assert_eq!(cb.height, 86.0);

        assert_eq!(TextInteractionState::Idle.to_str(), "idle");
        assert_eq!(TextInteractionState::Editing.to_str(), "editing");
        assert_eq!(TextInteractionState::Committing.to_str(), "committing");
    }
}
