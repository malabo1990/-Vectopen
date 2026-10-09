use godot::builtin::{Rect2, Rid, Vector2};
use godot::global::HorizontalAlignment;
use godot::classes::{Font, FontVariation, TextParagraph, TextServerManager};
use godot::prelude::*;

use crate::model::{
    ContentBounds, FrameBounds, HAlign, TextDocument, TextFrame, TextStyle, VerticalAlignment,
};

/// Fuentes reales por estilo para los runs (las da FontCore vía
/// VectorRichText.set_style_fonts). None = sintetizar ese estilo.
#[derive(Default, Clone)]
pub struct StyleFonts {
    pub bold: Option<Gd<Font>>,
    pub italic: Option<Gd<Font>>,
    pub bold_italic: Option<Gd<Font>>,
    /// Fuentes REALES por peso (100..900) en redonda y cursiva
    /// (VectorRichText.set_weight_fonts). Peso base del texto: los runs con
    /// weight 400 sin negrita usan la base.
    pub roman_w: std::collections::HashMap<i32, Gd<Font>>,
    pub italic_w: std::collections::HashMap<i32, Gd<Font>>,
    pub base_weight: i32,
}

impl StyleFonts {
    /// Peso efectivo de un run: weight (400 = "el de la base"), y la
    /// negrita lo sube al menos a 700. Redondeado a centenas 100..900.
    pub fn effective_weight(&self, style: &TextStyle) -> i32 {
        let base = if self.base_weight > 0 { self.base_weight } else { 400 };
        let mut w = if (style.weight - 400.0).abs() < 0.5 { base } else { style.weight.round() as i32 };
        if style.bold {
            w = w.max(700);
        }
        (((w as f32) / 100.0).round() as i32 * 100).clamp(100, 900)
    }
}

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
    pub fn reflow(&mut self, doc: &TextDocument, default_font: Option<Gd<Font>>, style_fonts: &StyleFonts) {
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
            let run_font = Self::resolve_font_variation(&font, style_fonts, &r.style);
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

    /// Resuelve negrita/cursiva: primero el archivo REAL del estilo
    /// (StyleFonts: Inter-Bold, Inter-Italic, Inter-BoldItalic…); lo que no
    /// tenga archivo se sintetiza sobre el más cercano. El emboldening
    /// sintético sobre MSDF dejaba muescas blancas en las uniones cóncavas.
    fn resolve_font_variation(base_font: &Gd<Font>, sf: &StyleFonts, style: &TextStyle) -> Gd<Font> {
        let (bold, italic) = (style.bold, style.italic);
        // Peso por run: archivo REAL de ese peso (Inter-Medium, -Black…).
        let w = sf.effective_weight(style);
        let base_w = if sf.base_weight > 0 { sf.base_weight } else { 400 };
        if w == base_w && !italic {
            return base_font.clone();
        }
        let table = if italic { &sf.italic_w } else { &sf.roman_w };
        if let Some(f) = table.get(&w) {
            return f.clone();
        }
        if !bold && !italic {
            return base_font.clone();
        }
        // (fuente, falta_negrita, falta_cursiva)
        let (src, synth_bold, synth_italic) = match (bold, italic) {
            (true, true) => match (&sf.bold_italic, &sf.bold, &sf.italic) {
                (Some(bi), _, _) => (bi.clone(), false, false),
                (None, Some(b), _) => (b.clone(), false, true),
                (None, None, Some(i)) => (i.clone(), true, false),
                _ => (base_font.clone(), true, true),
            },
            (true, false) => match &sf.bold {
                Some(b) => (b.clone(), false, false),
                None => (base_font.clone(), true, false),
            },
            _ => match &sf.italic {
                Some(i) => (i.clone(), false, false),
                None => (base_font.clone(), false, true),
            },
        };
        if !synth_bold && !synth_italic {
            return src;
        }
        let mut var_font = FontVariation::new_gd();
        var_font.set_base_font(&src);
        if synth_bold {
            var_font.set_variation_embolden(0.35);
        }
        if synth_italic {
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

        let _ = draw_origin;
        let tsm = TextServerManager::singleton();
        let ts = match tsm.get_primary_interface() {
            Some(ts) => ts,
            None => return,
        };

        // Estilo por carácter: índice → run (búsqueda en los límites de runs).
        let mut run_ends: Vec<usize> = Vec::with_capacity(doc.runs.len());
        let mut acc = 0usize;
        for r in &doc.runs {
            acc += r.length;
            run_ends.push(acc);
        }
        let style_at = |char_idx: usize| -> &TextStyle {
            let i = run_ends.partition_point(|&end| end <= char_idx).min(doc.runs.len() - 1);
            &doc.runs[i].style
        };

        // Dibujo GLIFO A GLIFO en la posición de línea calculada por el
        // layout (la misma que usan selección, cursor y hit-test):
        //  · antes, con color uniforme se usaba TextParagraph.draw, que
        //    IGNORA el interlineado → el texto se desfasaba de la selección
        //    (y el resaltado de la última línea "sobraba" por abajo);
        //  · con varios colores se recortaba la línea con clip_l/clip_r, que
        //    descarta un glifo entero si su borde pasa el límite por
        //    redondeo → la última letra de una selección coloreada quedaba
        //    con el color de al lado.
        for tp in &self.paragraphs {
            let line_count = tp.get_line_count();
            for l in 0..line_count {
                let l_idx = l as usize;
                if l_idx >= self.lines.len() {
                    break;
                }
                let line = &self.lines[l_idx];
                let line_rid = tp.get_line_rid(l);
                let baseline = pos + line.rect.position + Vector2::new(0.0, line.ascent);
                let glyphs = ts.shaped_text_get_glyphs(line_rid);

                // 2 pasadas: contornos (trazo) debajo, relleno encima.
                for pass in 0..2 {
                    let mut x = 0.0f32;
                    for g in glyphs.iter_shared() {
                        let advance = g.get("advance").and_then(|v| v.try_to::<f32>().ok()).unwrap_or(0.0);
                        let repeat = g.get("repeat").and_then(|v| v.try_to::<i64>().ok()).unwrap_or(1).max(1);
                        let start = g.get("start").and_then(|v| v.try_to::<i64>().ok()).unwrap_or(0).max(0) as usize;
                        let index = g.get("index").and_then(|v| v.try_to::<i64>().ok()).unwrap_or(0);
                        let font_rid = g.get("font_rid").and_then(|v| v.try_to::<Rid>().ok());
                        let font_size = g.get("font_size").and_then(|v| v.try_to::<i64>().ok()).unwrap_or(16);
                        let offset = g.get("offset").and_then(|v| v.try_to::<Vector2>().ok()).unwrap_or(Vector2::ZERO);
                        let st = style_at(start);
                        for _ in 0..repeat {
                            if let Some(fr) = font_rid {
                                if index != 0 && fr.is_valid() {
                                    let gp = baseline + Vector2::new(x, -st.baseline_shift) + offset;
                                    if pass == 0 {
                                        if st.stroke_width > 0.001 && st.stroke_color.a > 0.001 {
                                            let mut sc = st.stroke_color;
                                            sc.a *= st.opacity;
                                            ts.font_draw_glyph_outline_ex(fr, canvas_rid, font_size, st.stroke_width.round() as i64, gp, index)
                                                .color(sc)
                                                .done();
                                        }
                                    } else {
                                        let mut fc = st.fill_color;
                                        fc.a *= st.opacity;
                                        ts.font_draw_glyph_ex(fr, canvas_rid, font_size, gp, index).color(fc).done();
                                    }
                                }
                            }
                            x += advance;
                        }
                    }
                }
            }
        }
    }
}

