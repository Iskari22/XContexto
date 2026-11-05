// Interfaz de XContexto (web). La lógica está en core.js; aquí solo hay DOM y almacenamiento local.
import {
  DEFAULT_CONFIG, STANCE_LABEL, VERDICT_LABEL, XCError, analyze, regenerateDrafts, composeURL, cost, makePost,
  parsePostURL, findPostURL, xLength, recordEvent, emptyPrefs, EMPTY_STYLE, buildStyle, parseTweetsJS, trustedDomains,
} from "./core.js";
import { wikipediaArticles, fetchOEmbed } from "./net.js";

// ---------------------------------------------------------------- Almacenamiento (solo este navegador)

const KEY = "xcx.apiKey";
const store = {
  get(k, def) { try { const v = localStorage.getItem(k); return v == null ? def : JSON.parse(v); } catch { return def; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* modo privado o sin espacio */ } },
  del(k) { try { localStorage.removeItem(k); } catch { /* nada */ } },
};
function getKey() {
  try { return sessionStorage.getItem(KEY) || localStorage.getItem(KEY) || ""; } catch { return ""; }
}
function setKey(k, remember) {
  try {
    localStorage.removeItem(KEY); sessionStorage.removeItem(KEY);
    if (k) (remember ? localStorage : sessionStorage).setItem(KEY, k);
  } catch { toast("Este navegador no permite guardar datos (¿modo privado?)."); }
}

const settings = () => ({ model: DEFAULT_CONFIG.model, effort: "medium", limit: 100, extraDomains: [], ...store.get("xcx.settings", {}) });
const spend = () => ({ totalUSD: 0, analyses: 0, ...store.get("xcx.spend", {}) });
const style = () => ({ ...EMPTY_STYLE, ...store.get("xcx.style", {}) });
const prefs = () => store.get("xcx.prefs", null) ?? emptyPrefs();
const historyList = () => store.get("xcx.history", []);

function config() {
  const s = settings();
  return { ...DEFAULT_CONFIG, model: s.model, researchEffort: s.effort, draftingEffort: "medium" };
}

function learn(kind, extra = {}) {
  if (!current) return;
  store.set("xcx.prefs", recordEvent(prefs(), { kind, topic: current.report.topic, ...extra }));
}

// ---------------------------------------------------------------- Utilidades de DOM (sin innerHTML con datos externos)

const $ = (id) => document.getElementById(id);
function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k === "class") el.className = v;
    else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else el.setAttribute(k, v === true ? "" : v);
  }
  for (const c of kids.flat()) if (c != null && c !== false) el.append(c instanceof Node ? c : String(c));
  return el;
}
const safeHref = (u) => (/^https?:\/\//i.test(u) ? u : "#");
const link = (url, text) => h("a", { href: safeHref(url), target: "_blank", rel: "noopener noreferrer" }, text);

let toastTimer;
function toast(msg) {
  const t = $("toast");
  t.textContent = msg; t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, 2600);
}

async function copyText(text) {
  try { await navigator.clipboard.writeText(text); return true; } catch {
    const ta = h("textarea", { style: "position:fixed;opacity:0" }); ta.value = text; document.body.append(ta);
    ta.select(); const ok = document.execCommand("copy"); ta.remove(); return ok;
  }
}

// ---------------------------------------------------------------- Estado

let current = null;
let controller = null;

const STAGES = { fetching: "Leyendo el post…", researching: "Buscando contexto en fuentes reputadas…", drafting: "Escribiendo 3 borradores con tu estilo…" };

function show(section) {
  for (const id of ["status", "error", "result"]) $(id).hidden = id !== section;
}
function setStatus(stage) { show("status"); $("status-text").textContent = STAGES[stage] ?? stage; }

function showError(e) {
  show("error");
  $("error-text").textContent = e?.message ?? String(e);
  const acts = $("error-actions");
  acts.replaceChildren();
  if (["unauthorized", "missingAPIKey", "noCredits"].includes(e?.code)) {
    acts.append(h("button", { type: "button", class: "primary", onclick: openSettings }, "Abrir ajustes"));
  }
  if (e?.code === "needsText") $("post-input").focus();
}

function refreshOnboarding() { $("onboarding").hidden = !!getKey(); }

// ---------------------------------------------------------------- Análisis

async function readPost() {
  const raw = $("post-input").value.trim();
  if (!raw) throw new XCError("needsText", "Pega la URL o el texto de un post.");
  const parsed = parsePostURL(raw) ?? findPostURL(raw);
  const base = { url: parsed?.canonical, text: raw, author: $("author-input").value.trim(), handle: $("handle-input").value.trim().replace(/^@/, "") };
  let post = makePost(base);
  if (!post && parsed) {
    setStatus("fetching");
    const oembed = await fetchOEmbed(parsed.canonical);
    post = makePost({ ...base, oembed });
    if (!post) {
      throw new XCError("needsText", "No pude leer ese post (puede ser privado, estar borrado o X lo bloquea). Copia su texto, pégalo debajo de la URL y vuelve a pulsar Analizar.");
    }
  }
  if (!post) throw new XCError("needsText", "No reconozco eso como un post. Pega la URL completa (https://x.com/…/status/…) o el texto.");
  return post;
}

async function runAnalysis() {
  const apiKey = getKey();
  if (!apiKey) { showError(new XCError("missingAPIKey", "Falta tu clave de la API de Anthropic. Añádela en Ajustes.")); return; }
  const s = settings(), sp = spend();
  if (sp.totalUSD >= s.limit) {
    showError(new XCError("budget", `Has alcanzado tu límite de gasto (${sp.totalUSD.toFixed(2)} de ${s.limit} USD). Súbelo en Ajustes.`));
    return;
  }
  controller?.abort();
  controller = new AbortController();
  const btn = $("btn-analyze"); btn.disabled = true;
  try {
    const post = await readPost();
    setStatus("researching");
    const result = await analyze(post, {
      apiKey, config: config(), style: style(), prefs: prefs(), signal: controller.signal,
      domains: trustedDomains(s.extraDomains),
      wiki: (p) => wikipediaArticles(p, { signal: controller.signal }),
      progress: (st) => st !== "done" && setStatus(st),
      log: (m) => console.info("[XContexto]", m),
    });
    addSpend(result.totalCostUSD, 1);
    current = result;
    store.set("xcx.prefs", recordEvent(prefs(), { kind: "shown", topic: result.report.topic }));
    saveHistory(result);
    render(result);
  } catch (e) {
    if (e?.name === "AbortError") { show(null); toast("Cancelado"); } else { console.error(e); showError(e); }
  } finally {
    btn.disabled = false;
    controller = null;
  }
}

async function runRegenerate() {
  if (!current) return;
  const apiKey = getKey();
  controller = new AbortController();
  const btn = $("btn-regen"); btn.disabled = true;
  btn.textContent = "Rehaciendo…";
  try {
    const before = current.totalCostUSD;
    const r = await regenerateDrafts(current, { apiKey, config: config(), style: style(), prefs: prefs(), signal: controller.signal });
    addSpend(r.totalCostUSD - before, 0);
    learn("regenerated");
    current = r;
    saveHistory(r);
    render(r);
  } catch (e) {
    if (e?.name !== "AbortError") toast(e.message);
  } finally {
    btn.disabled = false; btn.textContent = "Rehacer borradores"; controller = null;
  }
}

function addSpend(usd, analyses) {
  const sp = spend();
  store.set("xcx.spend", { totalUSD: sp.totalUSD + usd, analyses: sp.analyses + analyses });
}

function saveHistory(r) {
  const list = historyList().filter((x) => x.post.id !== r.post.id);
  list.unshift(r);
  store.set("xcx.history", list.slice(0, 25));
}

// ---------------------------------------------------------------- Pintar el resultado

function render(r) {
  show("result");
  const p = r.post;
  $("post-card").replaceChildren(
    h("div", { class: "who" }, p.authorName || "Post", p.handle ? h("span", {}, ` @${p.handle}`) : null),
    h("p", { class: "text" }, p.text),
    r.report.topic ? h("span", { class: "topic" }, r.report.topic) : null,
    p.url ? h("p", { class: "hint" }, link(p.url, "Ver el post en X")) : null,
  );

  const drafts = $("drafts");
  drafts.replaceChildren(...r.drafts.map((d) => renderDraft(d, r)));

  const rep = r.report;
  const refs = (ix) => h("span", { class: "refs" }, ix.map((i) => rep.sources[i]).filter(Boolean).map((s, n) => link(s.url, s.publisher || String(n + 1))));
  const ctx = $("context-card");
  ctx.replaceChildren(
    h("h2", {}, "Contexto"),
    rep.summary ? h("p", {}, rep.summary) : null,
    rep.background ? h("p", { class: "muted" }, rep.background) : null,
    rep.keyFacts.length ? [h("h3", {}, "Datos clave"), h("ul", { class: "facts" }, rep.keyFacts.map((f) => h("li", {}, f.text, " ", refs(f.sources))))] : null,
    rep.claims.length ? [h("h3", {}, "Afirmaciones del post"), h("ul", { class: "claims" }, rep.claims.map((c) =>
      h("li", {}, h("span", { class: `verdict v-${c.verdict}` }, VERDICT_LABEL[c.verdict]), c.claim, " ", refs(c.sources),
        c.explanation ? h("span", { class: "expl" }, c.explanation) : null)))] : null,
    rep.perspectives.length ? [h("h3", {}, "Posturas"), h("ul", { class: "persp" }, rep.perspectives.map((x) => h("li", {}, h("strong", {}, x.label + ": "), x.text)))] : null,
    rep.sources.length ? [h("h3", {}, `Fuentes (${rep.sources.length})`), h("ul", { class: "sources" }, rep.sources.map((s) =>
      h("li", {}, h("span", { class: "kind" }, kindLabel(s.kind)), link(s.url, s.title || s.url), h("span", { class: "muted" }, ` · ${s.publisher}`))))] : null,
    rep.droppedUnverifiedSources ? h("p", { class: "warn-line" }, `Descartadas ${rep.droppedUnverifiedSources} URL que no aparecían en ninguna búsqueda real.`) : null,
  );
  for (const a of ctx.querySelectorAll("a")) a.addEventListener("click", () => learn("viewedSources"));

  $("result-meta").textContent = `${r.usage.map((u) => u.model).filter((v, i, a) => a.indexOf(v) === i).join(" + ")} · ` +
    `${r.usage.reduce((a, u) => a + u.webSearches, 0)} búsquedas · ${r.totalCostUSD.toFixed(3)} USD · ${Math.round(r.durationSeconds)} s`;
  window.scrollTo({ top: 0, behavior: "smooth" });
}

const kindLabel = (k) => ({ wikipedia: "Wikipedia", news: "Prensa", institution: "Institución", factCheck: "Verificador", other: "Otra" })[k] ?? k;

function renderDraft(d, r) {
  const ta = h("textarea", { rows: "4", "aria-label": `Borrador ${STANCE_LABEL[d.stance]}` });
  ta.value = d.text;
  const counter = h("span", {});
  const updateCount = () => {
    const n = xLength(ta.value);
    counter.textContent = `${n}/280`;
    counter.className = n > 280 ? "over" : "";
  };
  ta.addEventListener("input", updateCount);
  updateCount();

  const finalText = () => {
    const t = ta.value.trim();
    if (t !== d.text) learn("edited", { stance: d.stance, originalText: d.text, finalText: t });
    return t;
  };
  const thumb = (kind, label, aria) => h("button", {
    type: "button", "aria-label": aria, "aria-pressed": "false",
    onclick: (e) => { learn(kind, { stance: d.stance }); e.currentTarget.setAttribute("aria-pressed", "true"); toast("Anotado: aprenderé de esto"); },
  }, label);

  const src = d.sources.map((i) => r.report.sources[i]).filter(Boolean);
  return h("div", { class: "draft" },
    h("div", { class: "draft-head" }, h("strong", {}, STANCE_LABEL[d.stance]),
      r.predictedFavorite === d.stance ? h("span", { class: "badge fav" }, "Tu favorito probable") : null),
    ta,
    h("div", { class: "meta" }, h("span", {}, src.length ? ["Apoyo: ", src.map((s, i) => [i ? ", " : "", link(s.url, s.publisher)])] : "Sin fuente concreta"), counter),
    d.rationale ? h("p", { class: "rationale" }, d.rationale) : null,
    h("div", { class: "actions" },
      h("button", { type: "button", class: "primary", onclick: async () => {
        const t = finalText();
        if (await copyText(t)) { learn("copied", { stance: d.stance, finalText: t }); toast("Copiado"); } else toast("No pude copiar");
      } }, "Copiar"),
      h("button", { type: "button", class: "secondary", onclick: () => {
        const t = finalText();
        learn("composed", { stance: d.stance, finalText: t });
        // Solo abre el editor de X con el texto. Publicar es cosa tuya.
        window.open(composeURL(t, /^\d+$/.test(r.post.id) ? r.post.id : null), "_blank", "noopener,noreferrer");
      } }, "Abrir en X"),
      h("span", { class: "thumbs" }, thumb("thumbsUp", "👍", "Me gusta"), thumb("thumbsDown", "👎", "No me gusta")),
    ),
  );
}

// ---------------------------------------------------------------- Ajustes

function openSettings(e) {
  e?.preventDefault?.();
  const s = settings(), st = style(), sp = spend(), pr = prefs();
  $("api-key").value = getKey();
  $("model").value = s.model;
  $("effort").value = s.effort;
  $("limit").value = s.limit;
  $("spend-summary").textContent = `Gastado (estimación): ${sp.totalUSD.toFixed(2)} USD en ${sp.analyses} análisis. La cifra exacta está en console.anthropic.com → Usage.`;
  $("style-notes").value = st.manualNotes ?? "";
  $("style-guide").value = st.learnedGuide ?? "";
  $("style-summary").textContent = st.sampleCount ? `Estilo aprendido de ${st.sampleCount} posts tuyos (longitud típica ~${st.medianLength} caracteres).` : "Aún sin archivo importado.";
  $("extra-domains").value = (s.extraDomains ?? []).join("\n");
  $("bookmarklet").value = bookmarklet();
  const t = pr.totals ?? {};
  $("learning-summary").textContent = `Aprendizaje: ${t.shown ?? 0} análisis vistos, ${(t.copied ?? 0) + (t.composed ?? 0)} borradores usados, ${t.edited ?? 0} editados. Todo se guarda solo en este navegador.`;
  $("settings").showModal();
}

function saveSettings() {
  const s = settings();
  const limit = Number($("limit").value);
  store.set("xcx.settings", {
    ...s,
    model: $("model").value,
    effort: $("effort").value,
    limit: Number.isFinite(limit) && limit > 0 ? limit : s.limit,
    extraDomains: $("extra-domains").value.split(/\s+/).filter(Boolean),
  });
  store.set("xcx.style", { ...style(), manualNotes: $("style-notes").value.trim(), learnedGuide: $("style-guide").value.trim() || null });
}

function bookmarklet() {
  const app = location.origin + location.pathname;
  // Lee el post que tienes abierto en x.com y lo abre aquí. Solo LEE la página: no escribe nada en X.
  const code = `(()=>{const m=location.pathname.match(/\\/status\\/(\\d+)/);const as=[...document.querySelectorAll('article[data-testid="tweet"]')];` +
    `const a=(m&&as.find(x=>x.querySelector('a[href*="/status/'+m[1]+'"] time')))||as[0];` +
    `const t=a?.querySelector('[data-testid="tweetText"]')?.innerText||'';` +
    `const n=a?.querySelector('[data-testid="User-Name"] span')?.innerText||'';` +
    `location.href=${JSON.stringify(app)}+'?'+new URLSearchParams({url:location.href,text:t.slice(0,4000),author:n});})()`;
  return "javascript:" + code;
}

async function importArchive(file) {
  try {
    const samples = parseTweetsJS(await file.text());
    const built = buildStyle(samples, $("style-notes").value.trim());
    store.set("xcx.style", { ...built, learnedGuide: $("style-guide").value.trim() || null });
    $("style-summary").textContent = `Estilo aprendido de ${built.sampleCount} posts tuyos (longitud típica ~${built.medianLength} caracteres).`;
    toast("Archivo importado");
  } catch (e) { toast(e.message); }
}

function exportData() {
  const data = { exportedAt: new Date().toISOString(), settings: settings(), spend: spend(), style: style(), prefs: prefs(), history: historyList() };
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
  const a = h("a", { href: URL.createObjectURL(blob), download: "xcontexto-datos.json" });
  document.body.append(a); a.click(); a.remove();
}

// ---------------------------------------------------------------- Historial

function openHistory() {
  const list = historyList();
  $("history-list").replaceChildren(...(list.length ? list.map((r) => h("li", {}, h("button", { type: "button", onclick: () => {
    current = r; $("history").close(); render(r);
  } }, h("span", { class: "when" }, `${new Date(r.generatedAt).toLocaleString("es-ES")} · ${r.report.topic}`),
    h("span", { class: "snippet" }, (r.post.handle ? "@" + r.post.handle + ": " : "") + r.post.text)))) : [h("li", { class: "muted" }, "Aún no hay análisis.")]));
  $("history").showModal();
}

// ---------------------------------------------------------------- Arranque

function wire() {
  $("input-form").addEventListener("submit", (e) => { e.preventDefault(); runAnalysis(); });
  $("btn-cancel").addEventListener("click", () => controller?.abort());
  $("btn-regen").addEventListener("click", runRegenerate);
  $("btn-paste").addEventListener("click", async () => {
    try { $("post-input").value = await navigator.clipboard.readText(); } catch { toast("Mantén pulsado el campo y elige Pegar"); $("post-input").focus(); }
  });
  $("btn-settings").addEventListener("click", openSettings);
  $("open-settings-link").addEventListener("click", openSettings);
  $("btn-history").addEventListener("click", openHistory);
  $("btn-close-history").addEventListener("click", () => $("history").close());
  $("settings").addEventListener("close", () => { saveSettings(); refreshOnboarding(); });
  $("btn-toggle-key").addEventListener("click", () => {
    const i = $("api-key"); i.type = i.type === "password" ? "text" : "password"; $("btn-toggle-key").textContent = i.type === "password" ? "Ver" : "Ocultar";
  });
  $("btn-save-key").addEventListener("click", () => {
    const k = $("api-key").value.trim();
    if (k && !/^sk-ant-[\w-]{10,}$/.test(k)) { toast("Eso no parece una clave de Anthropic (empieza por sk-ant-)"); return; }
    setKey(k, $("remember-key").checked); refreshOnboarding(); toast(k ? "Clave guardada en este navegador" : "Clave borrada");
  });
  $("btn-forget-key").addEventListener("click", () => { setKey(""); $("api-key").value = ""; refreshOnboarding(); toast("Clave borrada"); });
  $("btn-reset-spend").addEventListener("click", () => { store.set("xcx.spend", { totalUSD: 0, analyses: 0 }); openSettings(); });
  $("archive-file").addEventListener("change", (e) => { const f = e.target.files?.[0]; if (f) importArchive(f); });
  $("btn-copy-bookmarklet").addEventListener("click", async () => { if (await copyText($("bookmarklet").value)) toast("Marcador copiado"); });
  $("btn-export").addEventListener("click", exportData);
  $("btn-wipe").addEventListener("click", () => {
    if (!confirm("¿Borrar la clave, el estilo, lo aprendido, el historial y el gasto de este navegador?")) return;
    for (const k of ["xcx.settings", "xcx.spend", "xcx.style", "xcx.prefs", "xcx.history"]) store.del(k);
    setKey(""); current = null; show(null); $("settings").close(); toast("Todo borrado");
  });
}

function fromQuery() {
  // Llega desde el marcador, la extensión de Safari o la de Chrome: ?url=…&text=…&author=…&handle=…
  const q = new URLSearchParams(location.search);
  const url = q.get("url"), text = q.get("text");
  if (!url && !text) return;
  $("post-input").value = [text, url].filter(Boolean).join("\n\n");
  if (q.get("author")) $("author-input").value = q.get("author");
  if (q.get("handle")) $("handle-input").value = q.get("handle");
  window.history.replaceState(null, "", location.pathname); // no dejar el texto en la barra
  if (getKey() && q.get("auto") !== "0") runAnalysis();
}

wire();
refreshOnboarding();
fromQuery();
const sp = spend();
if (sp.analyses) $("cost-hint").textContent = `Llevas ${sp.totalUSD.toFixed(2)} USD en ${sp.analyses} análisis (límite ${settings().limit} USD).`;

if ("serviceWorker" in navigator && location.protocol === "https:") {
  navigator.serviceWorker.register("sw.js").catch(() => {});
}

export { cost }; // útil desde la consola
