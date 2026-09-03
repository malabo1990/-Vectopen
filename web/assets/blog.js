/* Vectopen devlog — tiny static blog engine. Reads posts.json + posts/*.md. */
window.VectopenBlog = (function () {
  "use strict";

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  function fmtDate(d) {
    try {
      var dt = new Date(String(d) + "T00:00:00");
      if (isNaN(dt)) return String(d);
      return dt.toLocaleDateString(document.documentElement.lang || "en", {
        year: "numeric", month: "short", day: "numeric"
      });
    } catch (e) { return String(d); }
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

  function meta(slug, base) {
    return list(base).then(function (arr) {
      var m = arr.filter(function (p) { return p.slug === slug; })[0];
      if (!m) throw new Error("post not listed");
      return m;
    });
  }

  // Tries posts/<slug>.<lang>.md then posts/<slug>.md
  function body(slug, base, lang) {
    base = base || "";
    var tries = [];
    if (lang && lang !== "en") tries.push(base + "posts/" + slug + "." + lang + ".md");
    tries.push(base + "posts/" + slug + ".md");
    return tries.reduce(function (p, url) {
      return p.catch(function () {
        return fetch(url, { cache: "no-cache" }).then(function (r) {
          if (!r.ok) throw new Error(r.status);
          return r.text();
        });
      });
    }, Promise.reject());
  }

  return { esc: esc, fmtDate: fmtDate, list: list, meta: meta, body: body };
})();
