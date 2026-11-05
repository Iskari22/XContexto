// Prueba de extremo a extremo de la web en un iPhone emulado (Chromium + Playwright), con la API,
// Wikipedia y oEmbed SIMULADOS: no gasta créditos ni necesita red.
//   node Web/tests/e2e.mjs            → ejecuta y comprueba
//   node Web/tests/e2e.mjs --shots D  → además guarda capturas en la carpeta D
import { createRequire } from "node:module";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { extname, join, normalize } from "node:path";
import assert from "node:assert/strict";
import { fakeResearchResponse, fakeDraftsResponse } from "./fixtures.mjs";

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require("playwright"); } catch { playwright = require("/opt/node-tools/node_modules/playwright"); }
const { chromium, devices } = playwright;

const root = fileURLToPath(new URL("../", import.meta.url));
const shotsDir = process.argv.includes("--shots") ? process.argv[process.argv.indexOf("--shots") + 1] : null;
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".webmanifest": "application/manifest+json" };

const server = createServer(async (req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, "http://x").pathname)).replace(/^\/+/, "") || "index.html";
  try {
    const body = await readFile(join(root, path));
    res.writeHead(200, { "content-type": TYPES[extname(path)] ?? "application/octet-stream" });
    res.end(body);
  } catch { res.writeHead(404); res.end("no"); }
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${server.address().port}/`;

const browser = await chromium.launch();
const ctx = await browser.newContext({ ...devices["iPhone 14"], locale: "es-ES", permissions: ["clipboard-read", "clipboard-write"] });
const page = await ctx.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });

const apiCalls = [];
await ctx.route("https://api.anthropic.com/**", async (route) => {
  const req = route.request();
  if (req.method() === "OPTIONS") return route.fulfill({ status: 204, headers: cors() });
  const body = JSON.parse(req.postData());
  apiCalls.push({ headers: req.headers(), body });
  const data = body.output_config?.format ? fakeDraftsResponse() : fakeResearchResponse();
  await new Promise((r) => setTimeout(r, 150));
  return route.fulfill({ status: 200, headers: { ...cors(), "content-type": "application/json" }, body: JSON.stringify(data) });
});
await ctx.route("https://*.wikipedia.org/**", (route) => {
  const u = route.request().url();
  const data = u.includes("/search/page")
    ? { pages: [{ key: "Encuesta_de_población_activa" }] }
    : { title: "Encuesta de población activa", extract: "La EPA es una investigación trimestral del INE.", content_urls: { desktop: { page: "https://es.wikipedia.org/wiki/Encuesta_de_poblaci%C3%B3n_activa" } } };
  return route.fulfill({ status: 200, headers: { ...cors(), "content-type": "application/json" }, body: JSON.stringify(data) });
});
await ctx.route(/https:\/\/publish\.(twitter|x)\.com\/oembed.*/, (route) => {
  const cb = new URL(route.request().url()).searchParams.get("callback");
  const data = { author_name: "Ana Datos", html: '<blockquote><p lang="es" dir="ltr">El paro bajó al 2% en 2025, récord histórico</p>&mdash; Ana</blockquote>' };
  return route.fulfill({ status: 200, headers: { "content-type": "text/javascript" }, body: `${cb}(${JSON.stringify(data)})` });
});
// Cualquier otro intento de salir a X se registra (no debería haber ninguno).
const xTraffic = [];
const composeOpened = [];
await ctx.route(/https:\/\/(?!publish\.)([a-z]+\.)?(x|twitter)\.com\/.*/, (route) => {
  const u = route.request().url();
  if (u.startsWith("https://x.com/intent/post?")) { composeOpened.push(u); return route.fulfill({ status: 200, contentType: "text/html", body: "<p>editor de X (simulado)</p>" }); }
  xTraffic.push(u); return route.abort();
});

function cors() {
  return { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "POST, GET, OPTIONS" };
}
const shot = async (name) => { if (shotsDir) await page.screenshot({ path: join(shotsDir, name + ".png"), fullPage: true }); };

// 1) Primera vez: pide la clave.
await page.goto(base);
await page.waitForSelector("#onboarding:not([hidden])");
await shot("1-inicio");

// 2) Guardar la clave en Ajustes.
await page.click("#btn-settings");
await page.fill("#api-key", "sk-ant-api03-PRUEBA-0123456789");
await page.click("#btn-save-key");
await page.click("#settings-form button[value=close]");
assert.equal(await page.isHidden("#onboarding"), true, "el aviso de clave debería desaparecer");
assert.equal(await page.evaluate(() => localStorage.getItem("xcx.apiKey")), "sk-ant-api03-PRUEBA-0123456789");

// 3) Analizar un post pegando solo la URL (lee el texto por oEmbed en el iframe aislado).
await page.fill("#post-input", "https://x.com/anadatos/status/1855000000000000001?s=46");
await page.click("#btn-analyze");
await page.waitForSelector("#result:not([hidden])", { timeout: 15000 });
await shot("2-resultado");

assert.equal(apiCalls.length, 2, "investigación + borradores");
const [research, drafts] = apiCalls;
assert.equal(research.headers["anthropic-dangerous-direct-browser-access"], "true");
assert.equal(research.headers["x-api-key"], "sk-ant-api03-PRUEBA-0123456789");
assert.equal(research.body.model, "claude-opus-5-5");
assert.equal(research.body.tools[0].type, "web_search_20260209");
assert.ok(research.body.messages[0].content.includes("El paro bajó al 2%"), "el texto del post llega desde oEmbed");
assert.ok(research.body.messages[0].content.includes("Encuesta de población activa"), "Wikipedia llega al prompt");
assert.ok(drafts.body.output_config.format.type === "json_schema");

const draftTexts = await page.$$eval(".draft textarea", (els) => els.map((e) => e.value));
assert.equal(draftTexts.length, 3);
assert.ok(draftTexts.every((t) => !t.startsWith("@")), "sin @ inicial");
const verdicts = await page.$$eval(".claims .verdict", (els) => els.map((e) => e.textContent));
assert.deepEqual(verdicts, ["Discutido", "No verificable"]);
const sourceLinks = await page.$$eval(".sources a", (els) => els.map((e) => e.href));
assert.ok(sourceLinks.some((u) => u.includes("ine.es")));
assert.ok(!sourceLinks.some((u) => u.includes("inventada")), "la URL inventada no aparece");

// 4) Editar y copiar un borrador: se aprende.
const first = page.locator(".draft").first();
await first.locator("textarea").fill("Texto editado por mí con un dato del INE");
await first.getByRole("button", { name: "Copiar" }).click();
assert.equal(await page.evaluate(() => navigator.clipboard.readText()), "Texto editado por mí con un dato del INE");
const prefs = await page.evaluate(() => JSON.parse(localStorage.getItem("xcx.prefs")));
assert.equal(prefs.totals.copied, 1);
assert.equal(prefs.totals.edited, 1);

// 5) «Abrir en X» solo abre x.com/intent/post (no publica).
const [popup] = await Promise.all([ctx.waitForEvent("page"), first.getByRole("button", { name: "Abrir en X" }).click()]);
await popup.waitForLoadState().catch(() => {});
assert.equal(composeOpened.length, 1);
const opened = new URL(composeOpened[0]);
assert.equal(opened.origin + opened.pathname, "https://x.com/intent/post");
assert.equal(opened.searchParams.get("in_reply_to"), "1855000000000000001");
assert.equal(opened.searchParams.get("text"), "Texto editado por mí con un dato del INE");
await popup.close();

// 6) Gasto, historial y entrada desde el marcador (?url=&text=).
const spend = await page.evaluate(() => JSON.parse(localStorage.getItem("xcx.spend")));
assert.ok(spend.totalUSD > 0 && spend.analyses === 1);
await page.click("#btn-history");
assert.equal(await page.locator("#history-list li").count(), 1);
await shot("3-historial");
await page.click("#btn-close-history");

await page.goto(base + "?" + new URLSearchParams({ url: "https://x.com/otro/status/42", text: "La OTAN despliega tropas en Polonia", author: "Otro" }));
await page.waitForSelector("#result:not([hidden])", { timeout: 15000 });
assert.equal(apiCalls.length, 4);
assert.ok(apiCalls[2].body.messages[0].content.includes("La OTAN despliega tropas en Polonia"));
assert.equal(new URL(page.url()).search, "", "el texto no se queda en la barra de direcciones");

// 7) «Con Claude»: copia el post con las instrucciones y abre la app de Claude (sin usar la API).
await page.goto(base);
await page.evaluate(() => {
  window.__schemes = [];
  const orig = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () { if (this.href.startsWith("claude:")) window.__schemes.push(this.href); else orig.call(this); };
});
const callsBefore = apiCalls.length;
await page.fill("#post-input", "Polonia gasta el 4% del PIB en defensa https://x.com/otro/status/77");
await page.click("#btn-claude");
await page.waitForSelector("#claude-handoff:not([hidden])");
const handed = await page.evaluate(() => navigator.clipboard.readText());
assert.ok(handed.includes("Polonia gasta el 4% del PIB en defensa"));
assert.ok(handed.includes('url="https://x.com/otro/status/77"'));
assert.ok(handed.includes("Crítico · refuta"));
const schemes = await page.evaluate(() => window.__schemes);
assert.equal(schemes.length, 1);
assert.ok(schemes[0].startsWith("claude://claude.ai/new?q="));
assert.equal(new URL(schemes[0].replace("claude://", "https://")).searchParams.get("q"), handed);
assert.equal(apiCalls.length, callsBefore, "no llama a la API");
await shot("5-con-claude");

// 8) Ajustes en pantalla de móvil.
await page.click("#btn-settings");
await shot("4-ajustes");
const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
assert.equal(overflow, false, "sin scroll horizontal");

assert.deepEqual(xTraffic, [], "ningún tráfico hacia X fuera de oEmbed");
assert.deepEqual(errors.filter((e) => !/favicon/.test(e)), [], "sin errores en consola");

await browser.close();
server.close();
console.log("✓ e2e: 8 pasos OK en iPhone 14 emulado");
