// Garantías de seguridad de la web, comprobadas en el código fuente.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

const web = fileURLToPath(new URL("../", import.meta.url));
const read = (p) => readFileSync(web + p, "utf8");
const csp = (html) => /http-equiv="Content-Security-Policy" content="([^"]+)"/.exec(html)?.[1] ?? "";

test("la página solo puede conectar con la API de Anthropic y con Wikipedia (nunca con X)", () => {
  const policy = csp(read("index.html"));
  const connect = /connect-src ([^;]+)/.exec(policy)[1].trim().split(/\s+/);
  assert.deepEqual(connect.sort(), ["https://*.wikipedia.org", "https://api.anthropic.com"]);
  assert.match(policy, /script-src 'self'(;|$)/);
  assert.match(policy, /form-action 'none'/);
  assert.ok(!/x\.com|twitter\.com/.test(policy));
});

test("el iframe de oEmbed está aislado y su script coincide con el hash de la CSP", () => {
  const net = read("js/net.js");
  assert.match(net, /setAttribute\("sandbox", "allow-scripts"\)/);
  assert.ok(!net.includes("allow-same-origin"), "el iframe no debe compartir origen con la página");
  const html = read("oembed.html");
  const script = /<script>([\s\S]*?)<\/script>/.exec(html)[1];
  const hash = createHash("sha256").update(script).digest("base64");
  assert.ok(csp(html).includes(`'sha256-${hash}'`), "actualiza el hash de la CSP de oembed.html");
  assert.ok(!/connect-src (?!'none')/.test(csp(html)));
});

test("los datos externos nunca se insertan como HTML", () => {
  for (const f of ["js/app.js", "js/net.js", "js/core.js"]) {
    const src = read(f);
    assert.ok(!/\.innerHTML\s*=|insertAdjacentHTML|document\.write|eval\(|new Function/.test(src), f);
  }
});

test("la única salida hacia X es la ventana de redacción (x.com/intent/post)", () => {
  // Además se permite el enlace canónico del post (https://x.com/usuario/status/id), que solo se muestra para abrirlo.
  const src = (read("js/app.js") + read("js/core.js"))
    .replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "").replace(/ \/\/ .*$/gm, ""); // sin comentarios
  const xURLs = [...src.matchAll(/https:\/\/(?:[a-z]+\.)?(?:x|twitter)\.com[^\s"'`)]*/g)].map((m) => m[0])
    .filter((u) => !u.includes("…")); // ejemplos en textos de ayuda
  assert.ok(xURLs.length > 0);
  for (const u of xURLs) assert.ok(u.startsWith("https://x.com/intent/post") || u === "https://x.com/${handle}/status/${id}", u);
  // Ningún fetch puede ir a X (además lo impide la CSP).
  assert.ok(!/fetch\([^)]*(x|twitter)\.com/.test(src));
});

test("el service worker no guarda en caché nada de fuera (ni la API ni Wikipedia)", () => {
  const sw = read("sw.js");
  assert.match(sw, /url\.origin !== self\.location\.origin\) return/);
  assert.match(sw, /method !== "GET"/);
});

test("todo lo que guarda el service worker existe", () => {
  const sw = read("sw.js");
  const list = JSON.parse(/const SHELL = (\[[\s\S]*?\]);/.exec(sw)[1].replace(/'/g, '"'));
  for (const f of list) if (f !== "./") assert.doesNotThrow(() => read(f), f);
});
