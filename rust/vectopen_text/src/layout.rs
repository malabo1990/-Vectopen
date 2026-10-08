use godot::builtin::{Rect2, Rid, Vector2};
use godot::global::HorizontalAlignment;
use godot::classes::{Font, FontVariation, TextParagraph, TextServerManager};
use godot::prelude::*;

use crate::model::{
    ContentBounds, FrameBounds, HAlign, TextDocument, TextFrame, TextStyle, VerticalAlignment,
};

#[derive(Clone, Debug)]
pub struct LineInfo {
    pub char_start: usize,
    pub char_end: usize,
    pub rect: Rect2,
    pub ascent: f32,
    pub descent: f32,
    pub line_rid: Rid,
}

pub struct LayoutEngine {
    pub is_paragraph: bool,
    pub frame: TextFrame,
    pub frame_size: Vector2,
    pub content_size: Vector2,
    pub vert_offset: f32,
    pub lines: Vec<LineInfo>,
    pub paragraphs: Vec<Gd<TextParagraph>>,
    pub is_overset: bool,
}

impl Default for LayoutEngine {
    fn default() -> Self {
        let frame = TextFrame::default();
        let frame_size = Vector2::new(frame.width, frame.height);
        Self {
            is_paragraph: false,
            frame,
            frame_size,
            content_size: Vector2::ZERO,
            vert_offset: 0.0,
            lines: Vec::new(),
            paragraphs: Vec::new(),
            is_overset: false,
        }
    }
}

impl LayoutEngine {
    pub fn set_frame_size(&mut self, size: Vector2) {
        self.frame_size = size;
        self.frame.width = size.x;
        self.frame.height = size.y;
    }

    pub fn frame_bounds(&self) -> FrameBounds {
        FrameBounds {
            width: self.frame.width,
            height: self.frame.height,
        }
    }

    pub fn content_bounds(&self) -> ContentBounds {
        ContentBounds {
            width: self.content_size.x,
            height: self.content_size.y,
        }
    }
    /// Re-calcula la disposición tipográfica completa del documento
    pub fn reflow(&mut self, doc: &TextDocument, default_font: Option<Gd<Font>>) {
        self.lines.clear();
        self.paragraphs.clear();
        self.vert_offset = 0.0;

        let font = match default_font {
            Some(f) => f,
            None => {
                self.content_size = Vector2::new(100.0, 30.0);
                return;
            }
        };

        if doc.text.is_empty() {
            let sample_h = 24.0 * 1.2;
            let pad_w = if self.is_paragraph { self.frame.padding_left + self.frame.padding_right } else { 0.0 };
            let pad_h = if self.is_paragraph { self.frame.padding_top + self.frame.padding_bottom } else { 0.0 };
            self.content_size = Vector2::new((pad_w + 20.0).max(20.0), (pad_h + sample_h).max(sample_h));
            self.is_overset = false;
            return;
        }

        let mut tp = TextParagraph::new_gd();

        // Configurar ancho de envoltura para párrafos considerando columnas y paddings
        let wrap_w = if self.is_paragraph && self.frame.width > 20.0 {
            let col_w = self.frame.column_width();
            let left_ind = doc.para_style.indent_left.max(0.0);
            let right_ind = doc.para_style.indent_right.max(0.0);
            (col_w - left_ind - right_ind).max(20.0)
        } else {
            -1.0
        };
        tp.set_width(wrap_w);

        // Alineación
        let halign = match doc.para_style.align {
            HAlign::Left => HorizontalAlignment::LEFT,
            HAlign::Center => HorizontalAlignment::CENTER,
            HAlign::Right => HorizontalAlignment::RIGHT,
            HAlign::Justify => HorizontalAlignment::FILL,
        };
        tp.set_alignment(halign);

        // Interlineado
        let line_spacing = doc.para_style.line_spacing;

        // Agregar cada run de texto formateado al TextParagraph
        let mut char_offset = 0;
        let doc_chars: Vec<char> = doc.text.chars().collect();

        for r in &doc.runs {
            if char_offset >= doc_chars.len() {
                break;
            }
            let take = r.length.min(doc_chars.len() - char_offset);
            if take == 0 {
                continue;
            }
            let slice: String = doc_chars[char_offset..char_offset + take].iter().collect();
            let run_font = Self::resolve_font_variation(&font, &r.style);
            let fs = r.style.font_size.round().max(4.0) as i32;

            let gslice = GString::from(slice.as_str());
            tp.add_string(
                &gslice,
                &run_font,
                fs,
            );

            char_offset += take;
        }

        let total_lines = tp.get_line_count();

        // 1. Calcular altura acumulada y ancho máximo de las líneas
        let mut unaligned_total_h = 0.0;
        let mut max_line_w: f32 = 0.0;
        for l in 0..total_lines {
            let l_size = tp.get_line_size(l);
            max_line_w = max_line_w.max(l_size.x);
            unaligned_total_h += l_size.y + line_spacing;
        }

        // 2. Alineación vertical dentro del marco
        let content_avail_h = self.frame.content_height();
        self.vert_offset = if self.is_paragraph && unaligned_total_h < content_avail_h {
            match self.frame.vertical_alignment {
                VerticalAlignment::Center => ((content_avail_h - unaligned_total_h) * 0.5).max(0.0),
                VerticalAlignment::Bottom => (content_avail_h - unaligned_total_h).max(0.0),
                _ => 0.0,
            }
        } else {
            0.0
        };

        let base_x = if self.is_paragraph { self.frame.padding_left } else { 0.0 };
        let base_y = if self.is_paragraph { self.frame.padding_top + self.vert_offset } else { 0.0 };

        let num_cols = if self.is_paragraph { self.frame.columns.max(1) } else { 1 };
        let col_w = if self.is_paragraph { self.frame.column_width() } else { wrap_w };
        let col_gap = self.frame.column_gap;
        let col_avail_h = self.frame.content_height();

        let mut col_idx: u32 = 0;
        let mut cur_y = base_y;
        let mut has_column_overflow = false;

        for l in 0..total_lines {
            let l_size = tp.get_line_size(l);
            let ascent = tp.get_line_ascent(l);
            let descent = tp.get_line_descent(l);
            let h = l_size.y + line_spacing;

            // En modo párrafo multi-columna, avanzar de columna cuando se supera la altura disponible
            if self.is_paragraph && num_cols > 1 && col_avail_h > 20.0 {
                if (cur_y + h - base_y) > col_avail_h {
                    if col_idx + 1 < num_cols {
                        col_idx += 1;
                        cur_y = base_y;
                    } else {
                        has_column_overflow = true;
                    }
                }
            }

            let col_x = base_x + (col_idx as f32) * (col_w + col_gap);

            let line_range = tp.get_line_range(l);
            let l_start = line_range.x as usize;
            let l_end = line_range.y as usize;

            let align_x = match doc.para_style.align {
                HAlign::Center => ((col_w.max(l_size.x) - l_size.x) * 0.5).max(0.0),
                HAlign::Right => (col_w.max(l_size.x) - l_size.x).max(0.0),
                _ => doc.para_style.indent_left.max(0.0),
            };
            let line_x = col_x + align_x;

            let line_rid = tp.get_line_rid(l);
            self.lines.push(LineInfo {
                char_start: l_start,
                char_end: l_end,
                rect: Rect2::new(Vector2::new(line_x, cur_y), Vector2::new(l_size.x, h)),
                ascent,
                descent,
                line_rid,
            });

            cur_y += h;
        }

        let total_w = if self.is_paragraph {
            self.frame.width.max(max_line_w + self.frame.padding_left + self.frame.padding_right)
        } else {
            max_line_w.max(20.0)
        };
        let total_h = if self.is_paragraph {
            (unaligned_total_h + self.frame.padding_top + self.frame.padding_bottom).max(24.0)
        } else {
            cur_y.max(24.0)
        };
        self.content_size = Vector2::new(total_w, total_h);

        self.is_overset = if self.is_paragraph && self.frame.height > 10.0 {
            if num_cols > 1 {
                has_column_overflow || ((cur_y - base_y) > col_avail_h + 1.0)
            } else {
                (unaligned_total_h + self.frame.padding_top + self.frame.padding_bottom) > (self.frame.height + 1.0)
            }
        } else {
            false
        };

        self.paragraphs.push(tp);
    }

    /// Resuelve negrita/cursiva mediante FontVariation sobre la fuente base
    fn resolve_font_variation(base_font: &Gd<Font>, style: &TextStyle) -> Gd<Font> {
        if !style.bold && !style.italic {
            return base_font.clone();
        }
        let mut var_font = FontVariation::new_gd();
        var_font.set_base_font(base_font);
        if style.bold {
            var_font.set_variation_embolden(0.35);
        }
        if style.italic {
            var_font.set_variation_transform(godot::builtin::Transform2D::from_cols(
                Vector2::new(1.0, 0.0),
                Vector2::new(0.22, 1.0),
                Vector2::ZERO,
            ));
        }
        var_font.upcast()
    }

    /// Hit-testing: convierte coordenadas locales de ratón a índice de carácter
    pub fn hit_test(&self, point: Vector2) -> usize {
        if self.lines.is_empty() {
            return 0;
        }

        let base_x = if self.is_paragraph { self.frame.padding_left } else { 0.0 };
        let base_y = if self.is_paragraph { self.frame.padding_top + self.vert_offset } else { 0.0 };

        if let Some(tp) = self.paragraphs.first() {
            let tp_coords = point - Vector2::new(base_x, base_y);
            let hit = tp.hit_test(tp_coords);
            if hit >= 0 {
                return hit as usize;
            }
        }

        let tsm = TextServerManager::singleton();
        let ts = tsm.get_primary_interface();

        let mut best_line = 0;
        let mut min_dist = f32::MAX;

        for (i, line) in self.lines.iter().enumerate() {
            let r = line.rect;
            if r.contains_point(point) {
                best_line = i;
                break;
            }
            let dx = if point.x < r.position.x {
                r.position.x - point.x
            } else if point.x > r.position.x + r.size.x {
                point.x - (r.position.x + r.size.x)
            } else {
                0.0
            };
            let dy = if point.y < r.position.y {
                r.position.y - point.y
            } else if point.y > r.position.y + r.size.y {
                point.y - (r.position.y + r.size.y)
            } else {
                0.0
            };
            let dist = dx * dx + dy * dy;
            if dist < min_dist {
                min_dist = dist;
                best_line = i;
            }
        }

        let line = &self.lines[best_line];
        if let Some(ref ts) = ts {
            let local_x = point.x - line.rect.position.x;
            let hit_grapheme = ts.shaped_text_hit_test_grapheme(line.line_rid, local_x as f64);
            if hit_grapheme >= 0 {
                return (hit_grapheme as usize).clamp(line.char_start, line.char_end);
            }
        }

        if point.x <= line.rect.position.x {
            return line.char_start;
        }
        if point.x >= line.rect.position.x + line.rect.size.x {
            return line.char_end;
        }
        let ratio = ((point.x - line.rect.position.x) / line.rect.size.x.max(1.0)).clamp(0.0, 1.0);
        let chars_in_line = line.char_end.saturating_sub(line.char_start);
        let offset = (ratio * chars_in_line as f32).round() as usize;
        line.char_start + offset
    }

    /// Retorna el rectángulo visual del cursor (caret) para una posición de carácter
    pub fn caret_rect(&self, char_idx: usize) -> Rect2 {
        if self.lines.is_empty() {
            let base_x = if self.is_paragraph { self.frame.padding_left } else { 0.0 };
            let base_y = if self.is_paragraph { self.frame.padding_top } else { 2.0 };
            return Rect2::new(Vector2::new(base_x, base_y), Vector2::new(2.0, 24.0));
        }

        let tsm = TextServerManager::singleton();
        let ts = tsm.get_primary_interface();

        for line in &self.lines {
            if char_idx >= line.char_start && char_idx <= line.char_end {
                let h = (line.ascent + line.descent).max(line.rect.size.y).max(16.0);
                let y = line.rect.position.y;

                if char_idx == line.char_start {
                    return Rect2::new(Vector2::new(line.rect.position.x, y), Vector2::new(2.0, h));
                }

                if let Some(ref ts) = ts {
                    let sel = ts.shaped_text_get_selection(
                        line.line_rid,
                        line.char_start as i64,
                        char_idx as i64,
                    );
                    if !sel.is_empty() {
                        if let Some(last_span) = sel.as_slice().last() {
                            let x = line.rect.position.x + last_span.y;
                            return Rect2::new(Vector2::new(x, y), Vector2::new(2.0, h));
                        }
                    }
                }

                let ratio = if line.char_end > line.char_start {
                    ((char_idx - line.char_start) as f32) / ((line.char_end - line.char_start) as f32)
                } else {
                    0.0
                };
                let x = line.rect.position.x + (ratio * line.rect.size.x);
                return Rect2::new(Vector2::new(x, y), Vector2::new(2.0, h));
            }
        }

        if let Some(last) = self.lines.last() {
            let x = last.rect.position.x + last.rect.size.x;
            let y = last.rect.position.y;
            let h = (last.ascent + last.descent).max(last.rect.size.y).max(16.0);
            return Rect2::new(Vector2::new(x, y), Vector2::new(2.0, h));
        }

        Rect2::new(Vector2::ZERO, Vector2::new(2.0, 24.0))
    }

    /// Retorna la lista de rectángulos de selección entre start y end
    pub fn selection_rects(&self, start: usize, end: usize) -> Vec<Rect2> {
        let mut rects = Vec::new();
        let s = start.min(end);
        let e = start.max(end);
        if s == e || self.lines.is_empty() {
            return rects;
        }

        let tsm = TextServerManager::singleton();
        let ts = tsm.get_primary_interface();

        for line in &self.lines {
            if line.char_end <= s || line.char_start >= e {
                continue;
            }
            let overlap_start = line.char_start.max(s);
            let overlap_end = line.char_end.min(e);
            let y = line.rect.position.y;
            let h = (line.ascent + line.descent).max(line.rect.size.y);

            if let Some(ref ts) = ts {
                let sel = ts.shaped_text_get_selection(
                    line.line_rid,
                    overlap_start as i64,
                    overlap_end as i64,
                );
                if !sel.is_empty() {
                    for span in sel.as_slice() {
                        let x = line.rect.position.x + span.x.min(span.y);
                        let w = (span.y - span.x).abs().max(2.0);
                        rects.push(Rect2::new(Vector2::new(x, y), Vector2::new(w, h)));
                    }
                    continue;
                }
            }

            let chars_in_line = (line.char_end - line.char_start).max(1) as f32;
            let x1_ratio = ((overlap_start - line.char_start) as f32) / chars_in_line;
            let x2_ratio = ((overlap_end - line.char_start) as f32) / chars_in_line;

            let x = line.rect.position.x + (x1_ratio * line.rect.size.x);
            let w = ((x2_ratio - x1_ratio) * line.rect.size.x).max(2.0);

            rects.push(Rect2::new(Vector2::new(x, y), Vector2::new(w, h)));
        }

        rects
    }

    /// Dibuja el texto en el CanvasItem de Godot (soporta colores, opacidad, desplazamiento de baseline y trazos por letra/run)
    pub fn draw(&self, doc: &TextDocument, canvas_rid: Rid, pos: Vector2) {
        if doc.runs.is_empty() {
            return;
        }

        let base_x = if self.is_paragraph { self.frame.padding_left } else { 0.0 };
        let base_y = if self.is_paragraph { self.frame.padding_top + self.vert_offset } else { 0.0 };
        let draw_origin = pos + Vector2::new(base_x, base_y);

        let first_style = &doc.runs[0].style;
        let uniform_fill = doc.runs.iter().all(|r| {
            r.style.fill_color == first_style.fill_color
                && (r.style.opacity - first_style.opacity).abs() < 0.001
        });
        let uniform_stroke = doc.runs.iter().all(|r| {
            r.style.stroke_color == first_style.stroke_color
                && (r.style.stroke_width - first_style.stroke_width).abs() < 0.001
        });

        let num_cols = if self.is_paragraph { self.frame.columns.max(1) } else { 1 };

        if uniform_fill && uniform_stroke && num_cols <= 1 {
            let mut final_col = first_style.fill_color;
            final_col.a *= first_style.opacity;
            for tp in &self.paragraphs {
                if first_style.stroke_width > 0.001 && first_style.stroke_color.a > 0.001 {
                    let mut final_sc = first_style.stroke_color;
                    final_sc.a *= first_style.opacity;
                    tp.draw_outline_ex(canvas_rid, draw_origin)
                        .outline_size(first_style.stroke_width.round() as i32)
                        .color(final_sc)
                        .done();
                }
                tp.draw_ex(canvas_rid, draw_origin).color(final_col).done();
            }
            return;
        }

        let tsm = TextServerManager::singleton();
        let ts = match tsm.get_primary_interface() {
            Some(ts) => ts,
            None => return,
        };

        for tp in &self.paragraphs {
            let line_count = tp.get_line_count();
            for l in 0..line_count {
                let l_idx = l as usize;
                if l_idx >= self.lines.len() {
                    break;
                }
                let line_rid = tp.get_line_rid(l);
                let line_range = tp.get_line_range(l);
                let l_start = line_range.x as usize;
                let l_end = line_range.y as usize;

                let l_ascent = self.lines[l_idx].ascent;
                let line_rect_pos = pos + self.lines[l_idx].rect.position;
                let line_baseline_pos = line_rect_pos + Vector2::new(0.0, l_ascent);

                if uniform_fill && uniform_stroke {
                    let mut final_col = first_style.fill_color;
                    final_col.a *= first_style.opacity;
                    if first_style.stroke_width > 0.001 && first_style.stroke_color.a > 0.001 {
                        let mut final_sc = first_style.stroke_color;
                        final_sc.a *= first_style.opacity;
                        ts.shaped_text_draw_outline_ex(line_rid, canvas_rid, line_baseline_pos)
                            .outline_size(first_style.stroke_width.round() as i64)
                            .color(final_sc)
                            .done();
                    }
                    ts.shaped_text_draw_ex(line_rid, canvas_rid, line_baseline_pos)
                        .color(final_col)
                        .done();
                    continue;
                }

                let mut char_acc = 0;
                for r in &doc.runs {
                    let r_start = char_acc;
                    let r_end = char_acc + r.length;
                    char_acc = r_end;

                    if r_end <= l_start || r_start >= l_end {
                        continue;
                    }

                    let o_start = l_start.max(r_start);
                    let o_end = l_end.min(r_end);
                    if o_start >= o_end {
                        continue;
                    }

                    let b_start = ts.shaped_text_get_grapheme_bounds(line_rid, o_start as i64);
                    let b_end = ts.shaped_text_get_grapheme_bounds(line_rid, (o_end - 1) as i64);
                    let clip_l = f64::from(b_start.x.min(b_end.y));
                    let clip_r = f64::from(b_start.x.max(b_end.y));

                    let mut fill_col = r.style.fill_color;
                    fill_col.a *= r.style.opacity;
                    let shift_pos = line_baseline_pos - Vector2::new(0.0, r.style.baseline_shift);

                    if r.style.stroke_width > 0.001 && r.style.stroke_color.a > 0.001 {
                        let mut str_col = r.style.stroke_color;
                        str_col.a *= r.style.opacity;
                        ts.shaped_text_draw_outline_ex(line_rid, canvas_rid, shift_pos)
                            .clip_l(clip_l)
                            .clip_r(clip_r)
                            .outline_size(r.style.stroke_width.round() as i64)
                            .color(str_col)
                            .done();
                    }
                    ts.shaped_text_draw_ex(line_rid, canvas_rid, shift_pos)
                        .clip_l(clip_l)
                        .clip_r(clip_r)
                        .color(fill_col)
                        .done();
                }
            }
        }
    }
}

