/* Vectopen site — theme toggle + i18n. No dependencies. */
(function () {
  "use strict";

  // ---------- theme ----------
  var THEMES = ["system", "light", "dark"];
  function readTheme() {
    try { var t = localStorage.getItem("vectopen-theme"); return THEMES.indexOf(t) >= 0 ? t : "system"; }
    catch (e) { return "system"; }
  }
  function applyTheme(t) {
    var r = document.documentElement;
    if (t === "light" || t === "dark") r.setAttribute("data-theme", t);
    else r.removeAttribute("data-theme");
    try { localStorage.setItem("vectopen-theme", t); } catch (e) {}
    var b = document.getElementById("themeBtn");
    if (b) b.setAttribute("data-theme", t);
  }
  function cycleTheme() {
    applyTheme(THEMES[(THEMES.indexOf(readTheme()) + 1) % THEMES.length]);
  }

  // ---------- i18n ----------
  var I18N = window.VECTOPEN_I18N || { strings: { en: {} } };
  function available() { return Object.keys(I18N.strings); }
  function readLang() {
    try {
      var s = localStorage.getItem("vectopen-lang");
      if (s && I18N.strings[s]) return s;
    } catch (e) {}
    var nav = (navigator.language || "en").slice(0, 2).toLowerCase();
    return I18N.strings[nav] ? nav : "en";
  }
  function applyLang(lang) {
    if (!I18N.strings[lang]) lang = "en";
    var base = I18N.strings.en || {};
    var dict = I18N.strings[lang] || {};
    document.documentElement.lang = lang;
    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      var k = el.getAttribute("data-i18n");
      var v = dict[k] != null ? dict[k] : base[k];
      if (v != null) el.innerHTML = v;
    });
    document.querySelectorAll("[data-i18n-aria]").forEach(function (el) {
      var k = el.getAttribute("data-i18n-aria");
      var v = dict[k] != null ? dict[k] : base[k];
      if (v != null) el.setAttribute("aria-label", String(v).replace(/<[^>]+>/g, ""));
    });
    try { localStorage.setItem("vectopen-lang", lang); } catch (e) {}
    var sel = document.getElementById("langSel");
    if (sel) sel.value = lang;
    document.dispatchEvent(new CustomEvent("vectopen:lang", { detail: { lang: lang } }));
  }
  window.VECTOPEN_T = function (key) {
    var lang = readLang();
    var d = (I18N.strings[lang] || {})[key];
    return d != null ? d : (I18N.strings.en || {})[key];
  };
  window.VECTOPEN_LANG = readLang;

  // ---------- wire up ----------
  function init() {
    applyTheme(readTheme());
    var tb = document.getElementById("themeBtn");
    if (tb) tb.addEventListener("click", cycleTheme);

    var sel = document.getElementById("langSel");
    if (sel) {
      // populate if empty
      if (!sel.options.length) {
        var names = I18N.names || {};
        available().forEach(function (l) {
          var o = document.createElement("option");
          o.value = l; o.textContent = names[l] || l.toUpperCase();
          sel.appendChild(o);
        });
      }
      sel.addEventListener("change", function () { applyLang(sel.value); });
    }
    applyLang(readLang());
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
