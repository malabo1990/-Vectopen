# Vectopen website

Static site for Vectopen. No build step — plain HTML, CSS and vanilla JS.
Fonts come from Google Fonts; the devlog renders Markdown with `marked` from a
CDN. Everything else ships in this folder.

```
web/
├── index.html            landing page
├── assets/
│   ├── site.css          shared shell (tokens, nav, footer, prose)
│   ├── site.js           theme toggle + i18n engine
│   ├── i18n.js           translation dictionary  ← add languages here
│   └── blog.js           tiny static blog engine
├── blog/
│   ├── index.html        post list
│   ├── post.html         single post  (?p=<slug>)
│   ├── posts.json        manifest (newest first is not required — it sorts)
│   └── posts/<slug>.md   post bodies (Markdown)
└── logo.svg / logo.png   the mark, as raw assets
```

## Preview locally

```sh
cd web && python -m http.server 8080   # http://localhost:8080
```

(Open it over HTTP, not `file://` — the devlog uses `fetch`.)

## Deploy

**GitHub Pages** → Settings → Pages → *Deploy from a branch* → `main` / `/web`.
Live at `https://malabo1990.github.io/-Vectopen/`. Or any static host.

## Theme

`site.js` cycles **system → light → dark**, stored in `localStorage`, applied as
`data-theme` on `<html>`. A tiny inline script in each page's `<head>` sets it
before first paint to avoid a flash.

## Translations

`assets/i18n.js` holds one dictionary per language. To add one (e.g. German):

1. In `names`, add `de: "Deutsch"`.
2. Copy the whole `en: { … }` block to `de: { … }` and translate the *values* —
   keep every key.

The switcher and `<html lang>` update automatically. Text in the HTML is the
English fallback (`data-i18n="key"` on the element). Devlog **posts** are not
auto-translated — add `posts/<slug>.<lang>.md` and `post.html` picks it up for
that language, falling back to `<slug>.md`.

## Writing a devlog post

1. Create `blog/posts/<slug>.md` — start with a paragraph, use `##` for
   headings (the title comes from the manifest, don't repeat it as `#`).
2. Add an entry to `blog/posts.json`:

   ```json
   { "slug": "2026-10-devlog-02", "title": "…", "date": "2026-10-01",
     "summary": "one or two sentences", "tags": ["…"] }
   ```

   Set `"draft": true` to hide a post while writing it.

The landing page shows the newest three; `blog/` lists them all.

Post Markdown is rendered as-is (no sanitising) — it's authored by the repo
owner, so that's fine. Don't paste untrusted HTML into a post.

## Keep in sync

When the version, roadmap or feature set changes: the `v0.1.1` tag and the stat
block in `index.html`, the roadmap keys in `i18n.js` (mirror `ROADMAP.md`), and
the docs cards.

## Donation links

`index.html` → the **Support the project** section points at
`github.com/sponsors/malabo1990`, `ko-fi.com/vectopen` and
`liberapay.com/vectopen`. **Create/verify those accounts** (or change the URLs)
before publishing — right now they may 404.
