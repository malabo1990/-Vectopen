/* Vectopen blog — tiny static engine.
   Posts are Markdown files with YAML front-matter in blog/posts/<slug>.md.
   blog/posts.json is a generated index (see .github/workflows/blog-manifest.yml)
   used only for the listing + the homepage teaser. */
window.VectopenBlog = (function () {
  "use strict";

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  function fmtDate(d) {
    try {
      var dt = new Date(String(d).slice(0, 10) + "T00:00:00");
      if (isNaN(dt)) return String(d);
      return dt.toLocaleDateString(document.documentElement.lang || "en", {
        year: "numeric", month: "short", day: "numeric"
      });
    } catch (e) { return String(d); }
  }

  // Minimal YAML front-matter: strings, booleans, and one-line [a, b] lists.
  function parseFrontmatter(txt) {
    var m = /^﻿?---\s*\r?\n([\s\S]*?)\r?\n---\s*\r?\n?([\s\S]*)$/.exec(txt || "");
    if (!m) return { meta: {}, body: txt || "" };
    var meta = {};
    m[1].split(/\r?\n/).forEach(function (line) {
      var kv = /^([A-Za-z_][\w-]*)\s*:\s*(.*)$/.exec(line);
      if (!kv) return;
      var k = kv[1], v = kv[2].trim();
      if (/^\[.*\]$/.test(v)) {
        v = v.slice(1, -1).split(",").map(function (s) {
          return s.trim().replace(/^["']|["']$/g, "");
        }).filter(function (s) { return s.length; });
      } else if (v === "true" || v === "false") {
        v = (v === "true");
      } else {
        v = v.replace(/^["']|["']$/g, "");
      }
      meta[k] = v;
    });
    return { meta: meta, body: m[2] };
  }

  var _cache = null;
  function list(base) {
    base = base || "";
    if (_cache) return Promise.resolve(_cache);
    return fetch(base + "posts.json", { cache: "no-cache" })
      .then(function (r) { if (!r.ok) throw new Error("manifest " + r.status); return r.json(); })
      .then(function (arr) {
        arr = (Array.isArray(arr) ? arr : []).filter(function (p) { return p && p.slug && !p.draft; });
        arr.sort(function (a, b) { return String(b.date || "").localeCompare(String(a.date || "")); });
        _cache = arr;
        return arr;
      });
  }

  // Raw Markdown for a post. Tries posts/<slug>.<lang>.md, then posts/<slug>.md
  function raw(slug, base, lang) {
    base = base || "";
    var urls = [];
    if (lang && lang !== "en") urls.push(base + "posts/" + slug + "." + lang + ".md");
    urls.push(base + "posts/" + slug + ".md");
    return urls.reduce(function (p, url) {
      return p.catch(function () {
        return fetch(url, { cache: "no-cache" }).then(function (r) {
          if (!r.ok) throw new Error(String(r.status));
          return r.text();
        });
      });
    }, Promise.reject());
  }

  function post(slug, base, lang) {
    return raw(slug, base, lang).then(function (txt) {
      return parseFrontmatter(txt);
    });
  }

  return { esc: esc, fmtDate: fmtDate, parseFrontmatter: parseFrontmatter, list: list, raw: raw, post: post };
})();
