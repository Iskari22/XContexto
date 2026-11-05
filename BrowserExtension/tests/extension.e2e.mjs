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
  for (const host of ["https://xcx.example/**", "https://iskari22.github.io/**"]) {
    await ctx.route(host, (r) => { opened.push(r.request().url()); r.fulfill({ status: 200, body: "ok" }); });
  }
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
  // Por defecto: la versión web publicada.
  const def = await run(kind, {});
  assert.equal(def.opened.length, 1, kind);
  const d = new URL(def.opened[0]);
  assert.equal(d.origin + d.pathname, "https://iskari22.github.io/XContexto/");
  assert.equal(d.searchParams.get("url"), "https://x.com/anadatos/status/1855000000000000001");
  assert.equal(d.searchParams.get("text"), "El paro bajó al 2% en 2025 & es récord");
  assert.equal(d.searchParams.get("handle"), "anadatos");
  assert.equal(d.searchParams.get("author"), "Ana Datos");
  console.log(`✓ ${kind}: abre la versión web con el post`);

  // Opción: la app del Mac/iPhone.
  const { links } = await run(kind, { target: "app" });
  assert.equal(links.length, 1, kind);
  const u = new URL(links[0]);
  assert.equal(u.protocol + u.host, "xcontexto:analyze");
  assert.equal(u.searchParams.get("text"), "El paro bajó al 2% en 2025 & es récord");
  console.log(`✓ ${kind}: abre la app con el post`);

  // Opción: otra dirección web.
  const { opened } = await run(kind, { target: "web", webURL: "https://xcx.example/XContexto/?viejo=1" });
  assert.equal(new URL(opened[0]).origin + new URL(opened[0]).pathname, "https://xcx.example/XContexto/");
  console.log(`✓ ${kind}: respeta otra dirección web`);
}

// ⌥ + clic en un post: copia el post con las instrucciones (el MISMO texto que la web) y abre Claude.
const { claudeChatPrompt, localDate } = await import(new URL("../../Web/js/prompts.js", import.meta.url));
async function altClick(kind, storage) {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  const opened = [];
  await ctx.route("https://x.com/**", (r) => {
    if (r.request().isNavigationRequest() && !r.request().url().endsWith("/home")) opened.push(r.request().url());
    r.fulfill({ status: 200, contentType: "text/html", body: FAKE_X });
  });
  await ctx.route("https://claude.ai/**", (r) => { opened.push(r.request().url()); r.fulfill({ status: 200, body: "ok" }); });
  await page.goto("https://x.com/home");
  await page.evaluate((st) => {
    window.__schemes = []; window.__copied = [];
    window.browser = { storage: { local: { get: async (d) => ({ ...d, ...st }) }, onChanged: { addListener: () => {} } } };
    Object.defineProperty(navigator, "clipboard", { value: { writeText: async (t) => { window.__copied.push(t); } } });
    const orig = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function () { if (this.href.startsWith("claude:")) window.__schemes.push(this.href); else orig.call(this); };
    // Si X recibiera el clic, abriría el post: lo registramos para comprobar que no ocurre.
    document.querySelector("article").addEventListener("click", () => { window.__xGotClick = true; });
  }, storage);
  await page.addStyleTag({ content: readFileSync(dir + kind + "/content.css", "utf8") });
  await page.addScriptTag({ content: readFileSync(dir + kind + "/content.js", "utf8") });
  await page.waitForSelector(".xcx-btn");
  await page.waitForTimeout(50);
  const popup = ctx.waitForEvent("page", { timeout: 1500 }).catch(() => null);
  await page.click('[data-testid="tweetText"]', { modifiers: ["Alt"] });
  const p = await popup;
  if (p) await p.waitForLoadState().catch(() => {});
  await page.waitForTimeout(100);
  const out = await page.evaluate(() => ({ schemes: window.__schemes, copied: window.__copied, xGotClick: !!window.__xGotClick, toast: document.querySelector(".xcx-toast")?.textContent ?? "" }));
  await ctx.close();
  return { ...out, opened };
}

const expected = (styleNotes = "") => claudeChatPrompt(
  { authorName: "Ana Datos", handle: "anadatos", url: "https://x.com/anadatos/status/1855000000000000001", text: "El paro bajó al 2% en 2025 & es récord" },
  { today: localDate(), styleNotes });

for (const kind of ["safari", "chrome"]) {
  const app = await altClick(kind, {});
  assert.deepEqual(app.copied, [expected()], `${kind}: copia el mismo texto que la web`);
  assert.equal(app.schemes.length, 1);
  assert.equal(app.schemes[0], "claude://claude.ai/new?q=" + encodeURIComponent(expected()));
  assert.equal(app.xGotClick, false, "X no recibe el clic (no abre el post)");
  assert.match(app.toast, /copiado/);
  console.log(`✓ ${kind}: ⌥ + clic copia el post y abre la app de Claude`);

  const web = await altClick(kind, { altClick: "web", styleNotes: "tuteo, sin emojis" });
  assert.deepEqual(web.copied, [expected("tuteo, sin emojis")]);
  assert.equal(web.opened.length, 1);
  assert.equal(new URL(web.opened[0]).origin + new URL(web.opened[0]).pathname, "https://claude.ai/new");
  assert.equal(new URL(web.opened[0]).searchParams.get("q"), expected("tuteo, sin emojis"));
  console.log(`✓ ${kind}: ⌥ + clic con la opción claude.ai y tu estilo`);

  const off = await altClick(kind, { altClick: "off" });
  assert.deepEqual(off.copied, []); assert.deepEqual(off.schemes, []);
  console.log(`✓ ${kind}: ⌥ + clic desactivado no hace nada`);
}

// Chrome y Safari comparten el mismo código (solo cambia el manifiesto).
for (const f of ["content.js", "content.css", "popup.html", "popup.css", "popup.js", "_locales/es/messages.json"]) {
  assert.equal(readFileSync(dir + "chrome/" + f, "utf8"), readFileSync(dir + "safari/" + f, "utf8"), `${f} distinto entre Chrome y Safari`);
}
console.log("✓ chrome y safari: mismo código");

for (const kind of ["safari", "chrome"]) {
  const manifest = JSON.parse(readFileSync(dir + kind + "/manifest.json", "utf8"));
  assert.equal(manifest.manifest_version, 3);
  assert.deepEqual(manifest.permissions, ["storage"], "sin permisos de red ni de pestañas");
  assert.ok(!("host_permissions" in manifest) && !("background" in manifest));
  for (const s of [...Object.values(manifest.icons), ...Object.values(manifest.action.default_icon)]) readFileSync(dir + kind + "/" + s);
  readFileSync(dir + kind + "/" + manifest.action.default_popup);
  console.log(`✓ ${kind}: manifiesto con permisos mínimos`);
}

// El menú de la extensión guarda la elección.
{
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  await ctx.route("https://ext.local/**", (r) => {
    const f = new URL(r.request().url()).pathname.slice(1) || "popup.html";
    r.fulfill({ status: 200, contentType: f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html", body: readFileSync(dir + "chrome/" + f) });
  });
  await page.addInitScript(() => {
    const data = {};
    window.chrome = { storage: { local: { get: async (d) => ({ ...d, ...data }), set: async (v) => Object.assign(data, v) } } };
    window.__data = data;
  });
  await page.goto("https://ext.local/popup.html");
  await page.waitForFunction(() => document.querySelector("#webURL").value !== "");
  assert.equal(await page.inputValue("#webURL"), "https://iskari22.github.io/XContexto/");
  assert.equal(await page.isChecked("input[name=target][value=web]"), true);
  assert.equal(await page.isChecked("input[name=altClick][value=app]"), true, "⌥ + clic abre la app de Claude por defecto");
  await page.check("input[name=altClick][value=web]");
  await page.waitForFunction(() => window.__data.altClick === "web");
  await page.fill("#styleNotes", "tuteo");
  await page.dispatchEvent("#styleNotes", "change");
  await page.waitForFunction(() => window.__data.styleNotes === "tuteo");
  await page.check("input[name=target][value=app]");
  await page.waitForFunction(() => window.__data.target === "app");
  await page.check("input[name=target][value=web]");
  await page.fill("#webURL", "http://inseguro.example/");
  await page.dispatchEvent("#webURL", "change");
  assert.match(await page.textContent("#saved"), /https/);
  await ctx.close();
  console.log("✓ menú: guarda la elección y rechaza direcciones sin https");
}

await browser.close();
