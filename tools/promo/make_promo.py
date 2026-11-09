#!/usr/bin/env python3
"""Monta el vídeo promocional de Vectopen a partir de los fotogramas que graba
test/e2e/promo_video_e2e.gd (Movie Maker de Godot) y sus marcas «MARK».

  python3 tools/promo/make_promo.py <carpeta_fotogramas> [en|es] [carpeta_salida]

Salida: vectopen_promo_<idioma>_16x9.mp4 (YouTube, X, web) y
        vectopen_promo_<idioma>_9x16.mp4 (Reels, TikTok, Shorts).
Necesita ffmpeg (libx264) e ImageMagick 7 (`magick`).
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONTS = os.path.join(ROOT, "assets", "fonts")
LOGO_SVG = os.path.join(ROOT, "icon", "logo", "logo_vectopen.svg")
FPS = 30
W, H = 1920, 1080
BG = "#f4f5fb"
INK = "#1f1d36"
VIOLET = "#5a4bda"
CORAL = "#ff6b6b"
MUTED = "#6b6880"

SCENES = ["abrir", "color", "nodos", "pincel", "texto", "zoom", "muro", "modos"]
TEXT = {
    "en": {
        "abrir": "Open SVG, PDF, AI & Affinity files",
        "color": "Recolor in one click",
        "nodos": "Precise Bézier & node editing",
        "pincel": "Krita-like vector brushes",
        "texto": "Text on a path",
        "zoom": "Zoom up to 190,000% — always sharp",
        "muro": "10,000 elements, smooth",
        "modos": "Three interfaces: Smart · Modern · Pro",
        "tag": "The free, open-source vector editor",
        "cta": "Download it free",
        "platforms": "Windows · macOS · Linux · Android (preview)",
        "feedback": "Ideas or bugs? Tell us on GitHub · Reddit · Telegram",
    },
    "es": {
        "abrir": "Abre SVG, PDF, AI y Affinity",
        "color": "Recolorea en un clic",
        "nodos": "Bézier y nodos precisos",
        "pincel": "Pinceles vectoriales tipo Krita",
        "texto": "Texto en trazado",
        "zoom": "Zoom hasta 190 000 %, siempre nítido",
        "muro": "10 000 elementos, fluido",
        "modos": "Tres interfaces: Smart · Modern · Pro",
        "tag": "El editor vectorial libre y gratuito",
        "cta": "Descárgalo gratis",
        "platforms": "Windows · macOS · Linux · Android (vista previa)",
        "feedback": "¿Ideas o fallos? Cuéntanos en GitHub · Reddit · Telegram",
    },
}
URL = "malabo1990.github.io/vectopen-web"


def run(cmd):
    r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-3000:])
        raise SystemExit(f"falló: {cmd[0]}")


def font(name):
    return os.path.join(FONTS, f"Inter-{name}.ttf")


def marks(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        m = re.match(r"MARK (\w+) (\d+)", line)
        if m:
            out[m.group(1)] = int(m.group(2))
    return out


def caption_png(text, out, size=46):
    """Rótulo: cápsula oscura translúcida con barra de acento."""
    run(["magick", "-background", "none", "-fill", "white", "-font", font("SemiBold"),
         "-pointsize", str(size), f"label:{text}", out + ".txt.png"])
    w = int(subprocess.check_output(["magick", "identify", "-format", "%w", out + ".txt.png"]))
    pw, ph = w + 110, int(size * 2.1)
    run(["magick", "-size", f"{pw}x{ph}", "xc:none",
         "-fill", "rgba(20,18,43,0.88)", "-draw", f"roundrectangle 0,0 {pw - 1},{ph - 1} 22,22",
         "-fill", CORAL, "-draw", f"roundrectangle 26,26 33,{ph - 27} 3,3",
         out + ".txt.png", "-gravity", "west", "-geometry", "+60+0", "-composite", out])


def logo_png(height, out):
    run(["magick", "-background", "none", "-density", "1400", LOGO_SVG, "-resize", f"x{height}", out])


def title_card(L, tmp, out):
    logo = os.path.join(tmp, "logo_title.png")
    logo_png(300, logo)
    run(["magick", "-size", f"{W}x{H}", f"xc:{BG}",
         logo, "-gravity", "center", "-geometry", "+0-90", "-composite",
         "-font", font("Medium"), "-pointsize", "50", "-fill", INK,
         "-annotate", "+0+150", L["tag"], out])


def end_card(L, tmp, out):
    logo = os.path.join(tmp, "logo_end.png")
    logo_png(230, logo)
    url_pill = os.path.join(tmp, "url_pill.png")
    run(["magick", "-background", "none", "-fill", "white", "-font", font("SemiBold"),
         "-pointsize", "44", f"label:{URL}", url_pill + ".t.png"])
    uw = int(subprocess.check_output(["magick", "identify", "-format", "%w", url_pill + ".t.png"]))
    run(["magick", "-size", f"{uw + 90}x92", "xc:none", "-fill", VIOLET,
         "-draw", f"roundrectangle 0,0 {uw + 89},91 46,46",
         url_pill + ".t.png", "-gravity", "center", "-composite", url_pill])
    run(["magick", "-size", f"{W}x{H}", f"xc:{BG}",
         logo, "-gravity", "north", "-geometry", "+0+90", "-composite",
         "-font", font("Black"), "-pointsize", "92", "-fill", INK, "-gravity", "north",
         "-annotate", "+0+370", L["cta"],
         "-font", font("Medium"), "-pointsize", "40", "-fill", VIOLET,
         "-annotate", "+0+500", L["platforms"],
         url_pill, "-gravity", "north", "-geometry", "+0+598", "-composite",
         "-font", font("Regular"), "-pointsize", "32", "-fill", MUTED, "-gravity", "north",
         "-annotate", "+0+762", L["feedback"],
         "-font", font("Medium"), "-pointsize", "26", "-fill", MUTED, "-gravity", "south",
         "-annotate", "+0+60", "MIT · v0.2.3-beta · github.com/malabo1990/-Vectopen", out])


def outro_card(tmp, out):
    """Cierre: solo el logo de Vectopen, grande."""
    logo = os.path.join(tmp, "logo_outro.png")
    logo_png(460, logo)
    run(["magick", "-size", f"{W}x{H}", f"xc:{BG}",
         logo, "-gravity", "center", "-geometry", "+0-20", "-composite", out])


def main():
    frames = os.path.abspath(sys.argv[1])
    lang = sys.argv[2] if len(sys.argv) > 2 else "en"
    out_dir = os.path.abspath(sys.argv[3] if len(sys.argv) > 3 else frames)
    L = TEXT[lang]
    M = marks(os.path.join(frames, "marks.txt"))
    tmp = tempfile.mkdtemp(prefix="vectopen_promo_")
    title_s, end_s, outro_s, fade = 2.2, 3.2, 1.9, 0.35

    # Tramos de la grabación (fotogramas) y su duración en el vídeo final.
    segs = [(M[s], M[s + "_fin"]) for s in SCENES]
    sel = "+".join(f"between(n,{a},{b - 1})" for a, b in segs)
    body = os.path.join(tmp, "body.mp4")
    run(["ffmpeg", "-y", "-framerate", str(FPS), "-i", os.path.join(frames, "f%08d.png"),
         "-vf", f"select='{sel}',setpts=N/{FPS}/TB", "-r", str(FPS),
         "-c:v", "libx264", "-crf", "14", "-preset", "slow", "-pix_fmt", "yuv420p", body])
    starts, t = [], title_s - fade
    for a, b in segs:
        starts.append((t, t + (b - a) / FPS))
        t += (b - a) / FPS

    title = os.path.join(tmp, "title.png")
    end = os.path.join(tmp, "end.png")
    title_card(L, tmp, title)
    end_card(L, tmp, end)
    outro = os.path.join(tmp, "outro.png")
    outro_card(tmp, outro)
    caps = []
    for i, s in enumerate(SCENES):
        p = os.path.join(tmp, f"cap_{i}.png")
        caption_png(L[s], p)
        caps.append(p)

    body_s = sum((b - a) for a, b in segs) / FPS
    total = title_s + body_s + end_s + outro_s - 3 * fade
    caps_v = []
    for i, s in enumerate(SCENES):
        p = os.path.join(tmp, f"capv_{i}.png")
        caption_png(L[s], p, 50)
        caps_v.append(p)
    for fmt in ["16x9", "9x16"]:
        out = os.path.join(out_dir, f"vectopen_promo_{lang}_{fmt}.mp4")
        cap_list = caps if fmt == "16x9" else caps_v
        inputs = ["-loop", "1", "-t", str(title_s), "-framerate", str(FPS), "-i", title,
                  "-i", body,
                  "-loop", "1", "-t", str(end_s), "-framerate", str(FPS), "-i", end,
                  "-loop", "1", "-t", str(outro_s), "-framerate", str(FPS), "-i", outro]
        for p in cap_list:
            inputs += ["-loop", "1", "-t", f"{total:.3f}", "-framerate", str(FPS), "-i", p]
        f = []
        f.append("[0:v]format=yuv420p,setsar=1,fps=30,settb=1/30[t]")
        f.append("[1:v]format=yuv420p,setsar=1,fps=30,settb=1/30[b]")
        f.append("[2:v]format=yuv420p,setsar=1,fps=30,settb=1/30[e]")
        f.append("[3:v]format=yuv420p,setsar=1,fps=30,settb=1/30[o]")
        f.append(f"[t][b]xfade=transition=fade:duration={fade}:offset={title_s - fade:.3f}[tb]")
        f.append(f"[tb][e]xfade=transition=fade:duration={fade}:offset={title_s + body_s - 2 * fade:.3f}[tbe]")
        f.append(f"[tbe][o]xfade=transition=fade:duration={fade}:offset={title_s + body_s + end_s - 3 * fade:.3f}[v0]")
        last = "v0"
        cap_xy = "x=70:y=H-h-150"
        if fmt == "9x16":
            # Vertical: el vídeo 16:9 en el centro, marca arriba, rótulo debajo y web abajo.
            logo = os.path.join(tmp, "logo_v.png")
            logo_png(170, logo)
            frame_bg = os.path.join(tmp, "vertical_bg.png")
            run(["magick", "-size", "1080x1920", f"xc:{BG}",
                 logo, "-gravity", "north", "-geometry", "+0+170", "-composite",
                 "-font", font("Medium"), "-pointsize", "44", "-fill", INK, "-gravity", "north",
                 "-annotate", "+0+380", L["tag"],
                 "-font", font("SemiBold"), "-pointsize", "40", "-fill", VIOLET, "-gravity", "south",
                 "-annotate", "+0+300", URL,
                 "-font", font("Regular"), "-pointsize", "32", "-fill", MUTED, "-gravity", "south",
                 "-annotate", "+0+235", L["platforms"], frame_bg])
            inputs += ["-loop", "1", "-t", f"{total:.3f}", "-framerate", str(FPS), "-i", frame_bg]
            bg_idx = 4 + len(cap_list)
            f.append(f"[{last}]scale=1080:-2[sv]")
            f.append(f"[{bg_idx}:v]format=yuv420p[bgv]")
            f.append("[bgv][sv]overlay=x=0:y=(H-h)/2[vb]")
            last = "vb"
            cap_xy = "x=(W-w)/2:y=H/2+304+70"
        for i, (st, en) in enumerate(starts):
            st2, en2 = st + 0.25, en - 0.15
            f.append(f"[{4 + i}:v]format=rgba,fade=t=in:st={st2:.3f}:d=0.3:alpha=1,"
                     f"fade=t=out:st={en2 - 0.3:.3f}:d=0.3:alpha=1[c{i}]")
            f.append(f"[{last}][c{i}]overlay={cap_xy}:enable='between(t,{st2:.3f},{en2:.3f})'[v{i + 1}]")
            last = f"v{i + 1}"
        args = ["ffmpeg", "-y"] + inputs + ["-filter_complex", ";".join(f), "-map", f"[{last}]",
                                            "-t", f"{total:.3f}", "-r", str(FPS),
                                            "-c:v", "libx264", "-crf", "17", "-preset", "slow",
                                            "-pix_fmt", "yuv420p", "-movflags", "+faststart", out]
        run(args)
        print(f"{out}  ({total:.1f} s)")


if __name__ == "__main__":
    main()
