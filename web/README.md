# Vectopen website

The public landing page for Vectopen — `index.html`, a single self-contained
file (HTML + CSS, fonts from Google Fonts, all SVG inline). No build step.

## Preview locally

Open `web/index.html` in a browser, or serve the folder:

```sh
cd web && python -m http.server 8080   # then open http://localhost:8080
```

## Deploy

**GitHub Pages** — Settings → Pages → *Deploy from a branch* → `main` / `/web`.
The page is then live at `https://malabo1990.github.io/-Vectopen/`.

Or drop `index.html` on any static host (Netlify, Cloudflare Pages, a plain
`nginx` root). Nothing server-side is required.

## Editing

- **Content**: everything is inline in `index.html` — hero copy, the feature
  grid, the download cards, the roadmap columns and the docs links.
- **Design tokens**: the `:root` block at the top of the `<style>` — one palette
  for light, redefined under `@media (prefers-color-scheme: dark)` and
  `:root[data-theme="dark"]`. Change `--accent` (`#E24E2B`) to reskin.
- **Fonts**: Bricolage Grotesque (display), Inter (body), IBM Plex Mono
  (identifiers).
- **The hero mock** is a hand-drawn SVG "mini editor" (`svg.scene`) — a bezier
  path with control handles, a selection box and a snap guide, coloured via the
  `.scene .s-*` CSS rules and animated on load.

## Keep in sync

When the version, roadmap or feature set changes, update:

- the `v0.1.1` tag in the hero and the stat block
- the three roadmap columns (mirror `ROADMAP.md`)
- the docs cards (paths under `docs/en/`)
