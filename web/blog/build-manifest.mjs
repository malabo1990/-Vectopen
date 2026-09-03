// Regenerates web/blog/posts.json from the front-matter of web/blog/posts/*.md
// Run:  node web/blog/build-manifest.mjs      (also run by a GitHub Action)
import { readdir, readFile, writeFile } from "node:fs/promises";
import { join, basename } from "node:path";

const DIR = "web/blog/posts";
const OUT = "web/blog/posts.json";

function parseFrontmatter(txt) {
  const m = /^﻿?---\s*\r?\n([\s\S]*?)\r?\n---\s*\r?\n?/.exec(txt);
  if (!m) return {};
  const meta = {};
  for (const line of m[1].split(/\r?\n/)) {
    const kv = /^([A-Za-z_][\w-]*)\s*:\s*(.*)$/.exec(line);
    if (!kv) continue;
    let [, k, v] = kv;
    v = v.trim();
    if (/^\[.*\]$/.test(v)) {
      v = v.slice(1, -1).split(",").map((s) => s.trim().replace(/^["']|["']$/g, "")).filter(Boolean);
    } else if (v === "true" || v === "false") {
      v = v === "true";
    } else {
      v = v.replace(/^["']|["']$/g, "");
    }
    meta[k] = v;
  }
  return meta;
}

const files = (await readdir(DIR))
  .filter((f) => f.endsWith(".md") && !/\.[a-z]{2}\.md$/.test(f)); // skip <slug>.<lang>.md

const posts = [];
for (const f of files) {
  const meta = parseFrontmatter(await readFile(join(DIR, f), "utf8"));
  const slug = basename(f, ".md");
  posts.push({
    slug,
    title: meta.title || slug,
    date: String(meta.date || "").slice(0, 10),
    summary: meta.summary || "",
    tags: Array.isArray(meta.tags) ? meta.tags : meta.tags ? [meta.tags] : [],
    draft: meta.draft === true,
  });
}
posts.sort((a, b) => String(b.date).localeCompare(String(a.date)));
await writeFile(OUT, JSON.stringify(posts, null, 2) + "\n");
console.log(`wrote ${OUT} — ${posts.length} post(s)`);
