// Prueba los scripts de las extensiones (Safari y Chrome) en una página de X simulada, sin red.
//   node BrowserExtension/tests/extension.e2e.mjs
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require("playwright"); } catch { playwright = require("/opt/node-tools/node_modules/playwright"); }
const dir = fileURLToPath(new URL("../", import.meta.url));

// Estructura mínima de un post en x.com (los mismos data-testid que usa la web de X).
const FAKE_X = `<!doctype html><html><head><meta charset="utf-8"></head><body>
<article data-testid="tweet">
  <div data-testid="User-Name"><span>Ana Datos</span><span>@anadatos</span></div>
  <div data-testid="tweetText">El paro bajó al 2% en 2025 &amp; es récord</div>
  <a href="/anadatos/status/1855000000000000001"><time>1 h</time></a>
  <div role="group"><button>Responder</button></div>
</article></body></html>`;

const browser = await playwright.chromium.launch();

async function run(kind, storage) {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  const opened = [];
  await ctx.route("https://x.com/**", (r) => r.fulfill({ status: 200, contentType: "text/html", body: FAKE_X }));
  await ctx.route("https://xcx.example/**", (r) => { opened.push(r.request().url()); r.fulfill({ status: 200, body: "ok" }); });
  await page.goto("https://x.com/home");
  // Simula la API de extensiones y recoge los enlaces xcontexto:// sin navegar.
  await page.evaluate((st) => {
    window.__xcx = [];
    const listeners = [];
    window.browser = { storage: { local: { get: async (d) => ({ ...d, ...st }) }, onChanged: { addListener: (f) => listeners.push(f) } } };
    const origClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function () { if (this.href.startsWith("xcontexto:")) window.__xcx.push(this.href); else origClick.call(this); };
  }, storage);
  await page.addStyleTag({ content: readFileSync(dir + kind + "/content.css", "utf8") });
  await page.addScriptTag({ content: readFileSync(dir + kind + "/content.js", "utf8") });
  await page.waitForSelector(".xcx-btn");
  assert.equal(await page.locator(".xcx-btn").count(), 1, "un solo botón por post");
  await page.waitForTimeout(50);
  const popup = ctx.waitForEvent("page", { timeout: 3000 }).catch(() => null);
  await page.click(".xcx-btn");
  const p = await popup;
  if (p) await p.waitForLoadState().catch(() => {});
  const links = await page.evaluate(() => window.__xcx);
  await ctx.close();
  return { links, opened };
}

for (const kind of ["safari", "chrome"]) {
  const { links } = await run(kind, {});
  assert.equal(links.length, 1, kind);
  const u = new URL(links[0]);
  assert.equal(u.protocol + u.host, "xcontexto:analyze");
  assert.equal(u.searchParams.get("url"), "https://x.com/anadatos/status/1855000000000000001");
  assert.equal(u.searchParams.get("text"), "El paro bajó al 2% en 2025 & es récord");
  assert.equal(u.searchParams.get("handle"), "anadatos");
  assert.equal(u.searchParams.get("author"), "Ana Datos");
  console.log(`✓ ${kind}: abre la app con el post`);
}

const { opened } = await run("safari", { target: "web", webURL: "https://xcx.example/XContexto/" });
assert.equal(opened.length, 1);
const w = new URL(opened[0]);
assert.equal(w.origin + w.pathname, "https://xcx.example/XContexto/");
assert.equal(w.searchParams.get("text"), "El paro bajó al 2% en 2025 & es récord");
console.log("✓ safari: abre la versión web con el post");

const manifest = JSON.parse(readFileSync(dir + "safari/manifest.json", "utf8"));
assert.deepEqual(manifest.permissions, ["storage"], "sin permisos de red ni de pestañas");
assert.ok(!("host_permissions" in manifest));
for (const s of Object.values(manifest.icons)) readFileSync(dir + "safari/" + s);
console.log("✓ safari: manifiesto con permisos mínimos");

await browser.close();
