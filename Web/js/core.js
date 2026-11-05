// XContexto (web): lógica pura, sin DOM. La misma que el motor Swift (XCEngine), portada a JavaScript.
// Todo se prueba con `node --test Web/tests`.

import { RESEARCH_SYSTEM, DRAFT_SYSTEM, DRAFT_SCHEMA } from "./prompts.js";

export const API_URL = "https://api.anthropic.com/v1/messages";
export const API_VERSION = "2026-10-21";
export const BETA_FALLBACK = "server-side-fallback-2026-07-01";
export const STANCES = ["neutral", "supportive", "critical"];
export const STANCE_LABEL = { neutral: "Neutro · amplía", supportive: "A favor · refuerza", critical: "Crítico · refuta" };
export const VERDICT_LABEL = {
  supported: "Respaldado", disputed: "Discutido", false: "Erróneo", unverifiable: "No verificable", opinion: "Opinión",
};

export const DEFAULT_CONFIG = {
  model: "claude-opus-5-5",
  fallbackModel: "claude-sonnet-5-5",
  researchEffort: "medium",
  draftingEffort: "medium",
  maxWebSearches: 5,
};

// ---------------------------------------------------------------- Fuentes reputadas (= TrustedSources.swift)

export const TRUSTED_DOMAINS = [
  // Agencias y servicio público
  "reuters.com", "apnews.com", "efe.com", "europapress.es", "afp.com", "bbc.com", "rtve.es", "dw.com", "france24.com",
  // Prensa de referencia
  "elpais.com", "elmundo.es", "lavanguardia.com", "abc.es", "elconfidencial.com", "eldiario.es", "expansion.com",
  "theguardian.com", "nytimes.com", "washingtonpost.com", "ft.com", "economist.com", "wsj.com", "lemonde.fr",
  "politico.eu", "aljazeera.com", "bloomberg.com", "npr.org",
  // Análisis y geopolítica
  "foreignaffairs.com", "cfr.org", "crisisgroup.org", "sipri.org", "chathamhouse.org", "brookings.edu",
  "realinstitutoelcano.org", "csis.org", "iiss.org",
  // Instituciones y datos
  "un.org", "europa.eu", "nato.int", "worldbank.org", "imf.org", "oecd.org", "who.int", "ine.es", "bde.es",
  "boe.es", "lamoncloa.gob.es", "congreso.es", "ourworldindata.org",
  // Verificación
  "maldita.es", "newtral.es", "efe.com", "factcheck.org", "politifact.com", "fullfact.org", "snopes.com",
  // Enciclopedias
  "wikipedia.org", "britannica.com",
];

const FACT_CHECKERS = ["maldita.es", "newtral.es", "factcheck.org", "politifact.com", "fullfact.org", "snopes.com"];
const INSTITUTIONS = [".int", ".gob.es", ".europa.eu", "un.org", "worldbank.org", "imf.org", "oecd.org", "who.int",
  "ine.es", "bde.es", "boe.es", "congreso.es"];

const DOMAIN_RE = /^(?!-)[a-z0-9-]+(\.[a-z0-9-]+)+$/;

/** Lista sin duplicados y como mucho 64 dominios (límite de la API). Admite dominios extra del usuario. */
export function trustedDomains(extra = []) {
  const seen = new Set();
  const out = [];
  for (const raw of [...TRUSTED_DOMAINS, ...extra]) {
    const d = String(raw).trim().toLowerCase().replace(/^https?:\/\//, "").replace(/^www\./, "").replace(/\/.*$/, "");
    if (!DOMAIN_RE.test(d) || seen.has(d)) continue;
    seen.add(d);
    out.push(d);
  }
  return out.slice(0, 64);
}

export function hostOf(url) {
  try { return new URL(url).hostname.toLowerCase().replace(/^www\./, ""); } catch { return ""; }
}

const endsWithDomain = (host, d) => host === d.replace(/^\./, "") || host.endsWith(d.startsWith(".") ? d : "." + d);

export function sourceKind(url) {
  const host = hostOf(url);
  if (host.endsWith("wikipedia.org")) return "wikipedia";
  if (FACT_CHECKERS.some((d) => endsWithDomain(host, d))) return "factCheck";
  if (INSTITUTIONS.some((d) => endsWithDomain(host, d))) return "institution";
  if (TRUSTED_DOMAINS.some((d) => endsWithDomain(host, d))) return "news";
  return "other";
}

export const publisher = (url) => hostOf(url) || url;

// ---------------------------------------------------------------- Posts de X (= PostURL.swift, PostingGuard.swift)

const X_HOSTS = new Set(["x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"]);

/** Reconoce https://x.com/usuario/status/123… y devuelve {handle, id, canonical}, o null. */
export function parsePostURL(str) {
  let u;
  try { u = new URL(String(str ?? "").trim()); } catch { return null; }
  if (u.protocol !== "https:" && u.protocol !== "http:") return null;
  if (!X_HOSTS.has(u.hostname.toLowerCase())) return null;
  const parts = u.pathname.split("/").filter(Boolean);
  const i = parts.findIndex((p) => p === "status" || p === "statuses");
  if (i < 1 || i + 1 >= parts.length) return null;
  const id = parts[i + 1];
  if (!/^\d+$/.test(id)) return null;
  const handle = parts[i - 1];
  if (!/^\w{1,50}$/.test(handle)) return null;
  return { handle, id, canonical: `https://x.com/${handle}/status/${id}` };
}

/** Busca la primera URL de post dentro de un texto pegado (p. ej. "Mira esto https://x.com/a/status/1 …"). */
export function findPostURL(text) {
  for (const m of String(text ?? "").matchAll(/https?:\/\/[^\s<>"']+/g)) {
    const p = parsePostURL(m[0]);
    if (p) return p;
  }
  return null;
}

// Rangos que X cuenta como 1 (latín, griego, cirílico, árabe, hebreo… y alguna puntuación); el resto, como 2.
const LIGHT_RANGES = [[0x0000, 0x10ff], [0x2000, 0x200d], [0x2010, 0x201f], [0x2032, 0x2037]];
const segmenter = typeof Intl !== "undefined" && Intl.Segmenter ? new Intl.Segmenter("es", { granularity: "grapheme" }) : null;

/** Longitud tal como la cuenta X: cada URL vale 23; emojis, CJK y algunos símbolos (p. ej. «…») valen 2. */
export function xLength(text) {
  const s = String(text ?? "");
  let n = 0;
  const withoutURLs = s.replace(/https?:\/\/\S+/g, () => { n += 23; return ""; });
  const graphemes = segmenter ? [...segmenter.segment(withoutURLs)].map((g) => g.segment) : [...withoutURLs];
  for (const g of graphemes) {
    if (EMOJI_RE.test(g)) { n += 2; continue; }
    const cp = g.codePointAt(0);
    n += LIGHT_RANGES.some(([a, b]) => cp >= a && cp <= b) ? 1 : 2;
  }
  return n;
}

/** La ÚNICA salida hacia X: la ventana de redacción. No publica; eres tú quien pulsa "Publicar". */
export function composeURL(text, inReplyTo) {
  const u = new URL("https://x.com/intent/post");
  u.searchParams.set("text", String(text ?? ""));
  if (inReplyTo && /^\d+$/.test(String(inReplyTo))) u.searchParams.set("in_reply_to", String(inReplyTo));
  return u.toString();
}

// ---------------------------------------------------------------- oEmbed (= OEmbedParser en PostFetcher.swift)

const ENTITIES = { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'", "&apos;": "'", "&mdash;": "—", "&nbsp;": " " };

export function decodeEntities(s) {
  return String(s)
    .replace(/&(amp|lt|gt|quot|#39|apos|mdash|nbsp);/g, (m) => ENTITIES[m])
    .replace(/&#(x?)([0-9a-f]+);/gi, (m, hex, num) => {
      const v = parseInt(num, hex ? 16 : 10);
      try { return String.fromCodePoint(v); } catch { return m; }
    });
}

/** El HTML de oEmbed es `<blockquote><p lang="es">TEXTO</p>&mdash; Autor …</blockquote>`. */
export function tweetTextFromOEmbed(html) {
  const m = /<p[^>]*>([\s\S]*?)<\/p>/.exec(String(html ?? ""));
  if (!m) return "";
  const inner = m[1].replace(/<br\s*\/?>/g, "\n").replace(/<[^>]+>/g, "");
  return decodeEntities(inner).trim();
}

export function langFromOEmbed(html) {
  return /<p lang="([a-z]{2,3})"/.exec(String(html ?? ""))?.[1] ?? null;
}

export function guessLang(text) {
  const lower = " " + String(text).toLowerCase() + " ";
  const count = (ws) => ws.reduce((a, w) => a + lower.split(w).length - 1, 0);
  const es = count([" el ", " la ", " de ", " que ", " los ", " las ", " por ", " para ", " con ", " una ", " es "]);
  const en = count([" the ", " and ", " of ", " to ", " is ", " that ", " for ", " with ", " on "]);
  return en > es ? "en" : "es";
}

/** Une lo que llega (URL, texto pegado, oEmbed) en un post. */
export function makePost({ url, text, author, handle, oembed } = {}) {
  const parsed = parsePostURL(url) ?? findPostURL(text);
  // La URL del propio post no forma parte de su texto (llega junto al texto desde el marcador o al pegar).
  let body = String(text ?? "")
    .replace(/https?:\/\/(?:www\.|mobile\.)?(?:x|twitter)\.com\/\w+\/status(?:es)?\/\d+\S*/g, "")
    .trim();
  let lang = null;
  if (!body && oembed?.html) {
    body = tweetTextFromOEmbed(oembed.html);
    lang = langFromOEmbed(oembed.html);
  }
  if (!body) return null;
  return {
    id: parsed?.id ?? "local-" + hash(body),
    url: parsed?.canonical ?? null,
    authorName: author || oembed?.author_name || parsed?.handle || "",
    handle: handle || parsed?.handle || "",
    text: body.slice(0, 4000),
    lang: lang ?? guessLang(body),
  };
}

export function hash(s) {
  let h = 2166136261;
  for (const ch of String(s)) { h ^= ch.codePointAt(0); h = Math.imul(h, 16777619); }
  return (h >>> 0).toString(36);
}

// ---------------------------------------------------------------- Wikipedia (= Wikipedia.swift)

const STOP = new Set(["El", "La", "Los", "Las", "Un", "Una", "Y", "De", "En", "Que", "The", "A", "An", "This", "Esto",
  "Hoy", "Ayer", "Si", "No", "Por", "Para", "Con", "Es", "Lo", "Al", "Del", "Se", "Ya", "RT"]);

/** Consulta de búsqueda para Wikipedia: hashtags y nombres propios primero. */
export function keywordQuery(text, maxTerms = 6) {
  const cleaned = String(text).replace(/https?:\/\/\S+/g, " ").replace(/@\w+/g, " ");
  const words = cleaned.split(/[^\p{L}\p{N}#-]+/u).filter(Boolean);
  let terms = [];
  for (const w of words) {
    const core = w.startsWith("#") ? w.slice(1) : w;
    if ([...core].length <= 2 || STOP.has(core)) continue;
    const first = core[0];
    if (w.startsWith("#") || (first && first !== first.toLowerCase()) || core === core.toUpperCase()) {
      if (!terms.includes(core)) terms.push(core);
    }
    if (terms.length >= maxTerms) break;
  }
  if (terms.length < 2) terms = words.filter((w) => [...w].length > 4).slice(0, maxTerms);
  return terms.join(" ");
}

export function wikiHost(lang) { return `${lang === "en" ? "en" : "es"}.wikipedia.org`; }

// ---------------------------------------------------------------- JSON y URLs

export function extractJSON(text) {
  const t = String(text ?? "");
  let candidate = t;
  const tag = /<json>([\s\S]*?)<\/json>/.exec(t);
  const fence = /```json([\s\S]*?)```/.exec(t);
  if (tag) candidate = tag[1];
  else if (fence) candidate = fence[1];
  else {
    const a = t.indexOf("{"), b = t.lastIndexOf("}");
    if (a >= 0 && b > a) candidate = t.slice(a, b + 1);
  }
  try { return JSON.parse(candidate); } catch { throw new XCError("decoding", "No encontré JSON válido en la respuesta."); }
}

export function normalizeURL(url) {
  let s = String(url).toLowerCase();
  for (const p of ["https://", "http://", "www."]) if (s.startsWith(p)) s = s.slice(p.length);
  const q = s.search(/[?#]/);
  if (q >= 0) s = s.slice(0, q);
  return s.replace(/\/+$/, "");
}

// ---------------------------------------------------------------- Errores (= Errors.swift)

export class XCError extends Error {
  constructor(code, message, extra = {}) { super(message); this.code = code; Object.assign(this, extra); }
  get retryable() { return ["rateLimited", "overloaded", "network", "truncated", "decoding"].includes(this.code); }
}

export function errorFromResponse(status, json, retryAfter) {
  const msg = json?.error?.message ?? "";
  if (status === 401 || status === 403) return new XCError("unauthorized", "La clave de la API no es válida o se revocó.");
  if (status === 429) return new XCError("rateLimited", "Demasiadas peticiones seguidas. Reintentando en unos segundos.", { retryAfter });
  if ([500, 502, 503, 504, 529].includes(status)) return new XCError("overloaded", `La API está saturada (${status}). Reintentando.`);
  if (/credit balance/i.test(msg)) {
    return new XCError("noCredits", "La cuenta de esta clave no tiene saldo. Revisa Billing en console.anthropic.com o usa una clave de una organización con créditos.");
  }
  return new XCError("api", `La API devolvió ${status}: ${msg || "error desconocido"}`);
}

// ---------------------------------------------------------------- Cliente de la API (= ClaudeClient.swift)

/** Lee una respuesta de /v1/messages. Devuelve también los resultados de búsqueda (las únicas URLs "verificadas"). */
export function readMessage(json) {
  const content = Array.isArray(json?.content) ? json.content : [];
  const text = content.filter((b) => b.type === "text").map((b) => b.text ?? "").join("");
  const webResults = content
    .filter((b) => b.type === "web_search_tool_result" && Array.isArray(b.content)) // si hay error, content es un objeto
    .flatMap((b) => b.content)
    .filter((r) => r.type === "web_search_result" && r.url)
    .map((r) => ({ url: r.url, title: r.title || r.url }));
  const cited = content.flatMap((b) => (Array.isArray(b.citations) ? b.citations : [])).map((c) => c.url).filter(Boolean);
  const u = json?.usage ?? {};
  const usage = {
    model: json?.model ?? "",
    inputTokens: u.input_tokens ?? 0,
    outputTokens: u.output_tokens ?? 0,
    cacheReadTokens: u.cache_read_input_tokens ?? 0,
    cacheWriteTokens: u.cache_creation_input_tokens ?? 0,
    webSearches: u.server_tool_use?.web_search_requests ?? 0,
  };
  return { id: json?.id ?? "", model: usage.model, stopReason: json?.stop_reason ?? null, content, text, webResults, cited, usage };
}

export function addUsage(a, b) {
  return {
    model: b.model || a.model,
    inputTokens: a.inputTokens + b.inputTokens, outputTokens: a.outputTokens + b.outputTokens,
    cacheReadTokens: a.cacheReadTokens + b.cacheReadTokens, cacheWriteTokens: a.cacheWriteTokens + b.cacheWriteTokens,
    webSearches: a.webSearches + b.webSearches,
  };
}

/**
 * Envía una petición a la API desde el navegador. La clave va directa de tu navegador a api.anthropic.com.
 * Si la búsqueda web hace pausa (`pause_turn`), continúa el turno hasta 3 veces.
 */
export async function callClaude(body, { apiKey, model, fetchImpl = globalThis.fetch, signal } = {}) {
  if (!apiKey) throw new XCError("missingAPIKey", "Falta tu clave de la API de Anthropic. Añádela en Ajustes.");
  let req = { ...body, model, fallbacks: "default" };
  let all = [];
  let usage = null;
  for (let turn = 0; turn < 4; turn++) {
    let resp;
    try {
      resp = await fetchImpl(API_URL, {
        method: "POST",
        signal,
        headers: {
          "content-type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": API_VERSION,
          "anthropic-beta": BETA_FALLBACK,
          // Necesaria para llamar a la API desde una página web: la clave es tuya y no sale de tu navegador.
          "anthropic-dangerous-direct-browser-access": "true",
        },
        body: JSON.stringify(req),
      });
    } catch (e) {
      if (e?.name === "AbortError") throw e;
      throw new XCError("network", "Error de red: " + (e?.message ?? e));
    }
    let json = null;
    try { json = await resp.json(); } catch { json = null; }
    if (resp.status !== 200) {
      const ra = Number(resp.headers?.get?.("retry-after"));
      throw errorFromResponse(resp.status, json, Number.isFinite(ra) ? ra : null);
    }
    const msg = readMessage(json);
    usage = usage ? addUsage(usage, msg.usage) : msg.usage;
    all = all.concat(msg.content);
    if (msg.stopReason === "refusal") {
      const cat = json?.stop_details?.category;
      throw new XCError("refusal", `El modelo declinó esta petición${cat ? ` (${cat})` : ""}.`);
    }
    if (msg.stopReason === "max_tokens") throw new XCError("truncated", "La respuesta se cortó antes de terminar.");
    if (msg.stopReason !== "pause_turn") {
      return { ...readMessage({ ...json, content: all }), usage };
    }
    // Pausa de la búsqueda web: se devuelve el turno tal cual para que el modelo continúe.
    req = { ...req, messages: [...body.messages, { role: "assistant", content: all }] };
  }
  throw new XCError("truncated", "La búsqueda web no terminó tras varias pausas.");
}

/** Reintentos con arreglo automático (= withRecovery en Diagnostics.swift). */
export async function withRecovery(fn, { attempts = 3, fallbackModel, model, sleep = (ms) => new Promise((r) => setTimeout(r, ms)), log = () => {} } = {}) {
  let current = model;
  let last;
  for (let i = 1; i <= attempts; i++) {
    try { return await fn(current); } catch (e) {
      last = e;
      if (!(e instanceof XCError) || !e.retryable || i === attempts) throw e;
      if (e.code === "overloaded" && i >= 2 && fallbackModel && current !== fallbackModel) {
        log(`API saturada: cambio a ${fallbackModel}`);
        current = fallbackModel;
      } else {
        const wait = e.retryAfter ? e.retryAfter * 1000 : 800 * 2 ** (i - 1);
        log(`${e.message} (reintento ${i}/${attempts - 1})`);
        await sleep(Math.min(wait, 20000));
      }
    }
  }
  throw last;
}

// ---------------------------------------------------------------- Precios (= Pricing.swift)

export const RATES = {
  "claude-opus-5-5": { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 },
  "claude-sonnet-5-5": { input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5 },
  "claude-haiku-5-5": { input: 0.1, output: 0.5, cacheRead: 0.01, cacheWrite: 0.125 },
};
export const WEB_SEARCH_USD = 0.01;

export function cost(u) {
  const r = RATES[u.model] ?? RATES["claude-opus-5-5"];
  const m = 1e6;
  return u.inputTokens / m * r.input + u.outputTokens / m * r.output + u.cacheReadTokens / m * r.cacheRead
    + u.cacheWriteTokens / m * r.cacheWrite + u.webSearches * WEB_SEARCH_USD;
}

// ---------------------------------------------------------------- Investigación (= ResearchService.swift)

export function researchUserMessage(post, articles, today) {
  const wiki = articles.map((a) => `\n### ${a.title} (${a.url})\n${a.extract.slice(0, 1200)}\n`).join("");
  return `<fecha_de_hoy>${today}</fecha_de_hoy>

<post autor="${esc(post.authorName)} (@${esc(post.handle)})" url="${esc(post.url ?? "")}">
${post.text}
</post>

<wikipedia>${wiki || "(sin resultados)"}</wikipedia>`;
}

const esc = (s) => String(s ?? "").replace(/"/g, "'");

export function buildResearchRequest(post, articles, { today, effort = "medium", useWebSearch = true, domains = trustedDomains(), maxUses = 5 } = {}) {
  const body = {
    max_tokens: 16000,
    system: [{ type: "text", text: RESEARCH_SYSTEM, cache_control: { type: "ephemeral" } }],
    messages: [{ role: "user", content: researchUserMessage(post, articles, today) }],
    output_config: { effort },
  };
  if (useWebSearch) {
    body.tools = [{ type: "web_search_20260209", name: "web_search", max_uses: maxUses, allowed_domains: domains }];
  }
  return body;
}

/** Convierte la respuesta en un informe. Solo acepta URLs que aparecieron de verdad en la búsqueda o en Wikipedia. */
export function parseResearch(msg, articles) {
  const json = extractJSON(msg.text);
  const verified = new Map();
  for (const r of msg.webResults) verified.set(normalizeURL(r.url), r.title);
  for (const a of articles) verified.set(normalizeURL(a.url), a.title);
  for (const u of msg.cited) if (!verified.has(normalizeURL(u))) verified.set(normalizeURL(u), publisher(u));

  const sources = [];
  const index = new Map();
  let dropped = 0;
  const refs = (list) => (Array.isArray(list) ? list : []).filter((x) => typeof x === "string").flatMap((raw) => {
    const key = normalizeURL(raw);
    if (!verified.has(key)) { dropped++; return []; }
    if (index.has(key)) return [index.get(key)];
    sources.push({ title: verified.get(key), url: raw, publisher: publisher(raw), kind: sourceKind(raw), verified: true });
    index.set(key, sources.length - 1);
    return [sources.length - 1];
  });

  const arr = (v) => (Array.isArray(v) ? v : []);
  const keyFacts = arr(json.key_facts).filter((f) => typeof f?.text === "string").map((f) => ({ text: f.text, sources: refs(f.source_urls) }));
  const claims = arr(json.claims).filter((c) => typeof c?.claim === "string").map((c) => ({
    claim: c.claim,
    verdict: Object.hasOwn(VERDICT_LABEL, c.verdict) ? c.verdict : "unverifiable",
    explanation: String(c.explanation ?? ""),
    sources: refs(c.source_urls),
  }));
  // Un "false"/"disputed" sin ninguna fuente verificada se rebaja a "no verificable".
  for (const c of claims) if ((c.verdict === "false" || c.verdict === "disputed") && c.sources.length === 0) c.verdict = "unverifiable";
  const perspectives = arr(json.perspectives).filter((p) => typeof p?.label === "string" && typeof p?.text === "string")
    .map((p) => ({ label: p.label, text: p.text }));
  for (const a of articles) {
    const k = normalizeURL(a.url);
    if (!index.has(k)) { sources.push({ title: a.title, url: a.url, publisher: publisher(a.url), kind: "wikipedia", verified: true }); index.set(k, sources.length - 1); }
  }
  return {
    topic: String(json.topic ?? ""), summary: String(json.summary ?? ""), background: String(json.background ?? ""),
    keyFacts, claims, perspectives, sources, droppedUnverifiedSources: dropped,
  };
}

// ---------------------------------------------------------------- Borradores (= DraftWriter.swift)

export function reportAsText(report) {
  const urls = (ix) => ix.map((i) => report.sources[i]?.url).filter(Boolean).join(", ");
  let t = `Tema: ${report.topic}\nResumen: ${report.summary}\nAntecedentes: ${report.background}\n\nHechos:\n`;
  for (const f of report.keyFacts) t += `- ${f.text} [${urls(f.sources)}]\n`;
  t += "\nAfirmaciones del post:\n";
  for (const c of report.claims) t += `- "${c.claim}" → ${c.verdict}: ${c.explanation} [${urls(c.sources)}]\n`;
  if (report.perspectives.length) t += "\nPosturas:\n" + report.perspectives.map((p) => `- ${p.label}: ${p.text}`).join("\n");
  return t;
}

export function buildDraftRequest(post, report, style, prefs, { effort = "medium" } = {}) {
  const examples = exemplars(style, post.text).map((s) => `- ${s.text}`).join("\n");
  // Orden: lo estable primero (estilo) y lo variable al final, para aprovechar el caché.
  const styleBlock = `<estilo_del_usuario>\n${styleDescription(style)}\n\nEjemplos reales suyos:\n${examples || "(ninguno aún)"}\n</estilo_del_usuario>`;
  const hints = promptHints(prefs, report.topic);
  const user = `<post autor="@${esc(post.handle)}">
${post.text}
</post>

<informe_de_contexto>
${reportAsText(report)}
</informe_de_contexto>
${hints ? `\n<preferencias_aprendidas>\n${hints}\n</preferencias_aprendidas>` : ""}`;
  return {
    max_tokens: 8000,
    system: [
      { type: "text", text: DRAFT_SYSTEM },
      { type: "text", text: styleBlock, cache_control: { type: "ephemeral" } },
    ],
    messages: [{ role: "user", content: user }],
    output_config: { effort, format: { type: "json_schema", schema: DRAFT_SCHEMA } },
  };
}

export function parseDrafts(msg, report) {
  const json = extractJSON(msg.text);
  const byURL = new Map(report.sources.map((s, i) => [normalizeURL(s.url), i]));
  const seen = new Set();
  const drafts = (Array.isArray(json.drafts) ? json.drafts : []).flatMap((d) => {
    if (!STANCES.includes(d?.stance) || typeof d?.text !== "string" || seen.has(d.stance)) return [];
    seen.add(d.stance);
    const text = stripLeadingMentions(d.text.trim());
    const sources = [...new Set((Array.isArray(d.source_urls) ? d.source_urls : []).map((u) => byURL.get(normalizeURL(u))).filter((i) => i !== undefined))];
    return [{ stance: d.stance, text, rationale: String(d.rationale ?? ""), sources, length: xLength(text) }];
  });
  if (drafts.length !== 3) throw new XCError("decoding", `Faltan borradores (${drafts.length}/3).`);
  return drafts;
}

/** X añade la @ del autor en las respuestas: si el modelo la escribe, sobra. */
export function stripLeadingMentions(text) { return String(text).replace(/^(@\w+[\s,:]+)+/, "").trim(); }

// ---------------------------------------------------------------- Estilo (= StyleProfile.swift, ArchiveImporter.swift)

export const EMPTY_STYLE = {
  sampleCount: 0, medianLength: 200, emojiRate: 0, hashtagRate: 0, questionRate: 0, exclamationRate: 0, linkRate: 0,
  startsLowercaseRate: 0, signaturePhrases: [], samples: [], manualNotes: "", learnedGuide: null,
};

/** Lee data/tweets.js del archivo de X (Ajustes → Tu cuenta → Descargar un archivo de tus datos). */
export function parseTweetsJS(text) {
  const s = String(text);
  const i = s.indexOf("[");
  if (i < 0) throw new XCError("decoding", "tweets.js sin lista");
  let items;
  try { items = JSON.parse(s.slice(i)); } catch { throw new XCError("decoding", "tweets.js no es JSON válido"); }
  if (!Array.isArray(items)) throw new XCError("decoding", "tweets.js sin lista");
  return items.flatMap((item) => {
    const t = item?.tweet ?? item;
    const full = t?.full_text ?? t?.text;
    if (typeof full !== "string") return [];
    const num = (v) => Number.parseInt(v, 10) || 0;
    return [{
      text: decodeEntities(full.replace(/^(@\w+\s+)+/, "")),
      isReply: t.in_reply_to_status_id_str != null,
      likes: num(t.favorite_count), retweets: num(t.retweet_count), lang: t.lang ?? null,
      replyToID: t.in_reply_to_status_id_str ?? null, replyToHandle: t.in_reply_to_screen_name ?? null,
    }];
  });
}

const EMOJI_RE = /\p{Extended_Pictographic}/u;

export function buildStyle(all, manualNotes = "") {
  const s = all.filter((x) => !x.text.startsWith("RT @") && [...x.text].length > 15);
  if (!s.length) return { ...EMPTY_STYLE, manualNotes };
  const rate = (p) => s.filter((x) => p(x.text)).length / s.length;
  const lengths = s.map((x) => [...x.text].length).sort((a, b) => a - b);
  const score = (x) => x.likes + 2 * x.retweets + (x.isReply ? 5 : 0);
  return {
    sampleCount: s.length,
    medianLength: lengths[Math.floor(lengths.length / 2)],
    emojiRate: rate((t) => EMOJI_RE.test(t)),
    hashtagRate: rate((t) => t.includes("#")),
    questionRate: rate((t) => t.includes("?")),
    exclamationRate: rate((t) => t.includes("!")),
    linkRate: rate((t) => t.includes("http")),
    startsLowercaseRate: rate((t) => /^\p{Ll}/u.test(t)),
    signaturePhrases: signature(s.map((x) => x.text)),
    samples: [...s].sort((a, b) => score(b) - score(a)).slice(0, 300),
    manualNotes,
    learnedGuide: null,
  };
}

const BIGRAM_STOP = new Set(["de la", "en el", "en la", "de los", "que el", "que la", "a la", "de las", "por el", "con el", "y el", "es un", "es una", "of the", "in the"]);

export function signature(texts) {
  const counts = new Map();
  for (const t of texts) {
    const w = t.toLowerCase().replace(/https?:\/\/\S+|@\w+/g, "").split(/[^\p{L}']+/u).filter(Boolean);
    if (w.length <= 2) continue;
    for (let i = 0; i < w.length - 1; i++) {
      const bi = w[i] + " " + w[i + 1];
      if (!BIGRAM_STOP.has(bi) && bi.length > 6) counts.set(bi, (counts.get(bi) ?? 0) + 1);
    }
  }
  const minHits = Math.max(3, Math.floor(texts.length / 80));
  return [...counts].filter(([, n]) => n >= minHits).sort((a, b) => b[1] - a[1]).slice(0, 12).map(([k]) => k);
}

export function exemplars(style, text, count = 8) {
  if (!style?.samples?.length) return [];
  const words = new Set(String(text).toLowerCase().split(/[^\p{L}]+/u).filter((w) => [...w].length > 4));
  return style.samples
    .map((s, i) => {
      const sw = new Set(s.text.toLowerCase().split(/[^\p{L}]+/u));
      let overlap = 0;
      for (const w of words) if (sw.has(w)) overlap++;
      return [overlap * 3 + (s.isReply ? 1 : 0) - i * 0.001, s];
    })
    .sort((a, b) => b[0] - a[0]).slice(0, count).map(([, s]) => s);
}

export function styleDescription(style) {
  const st = style ?? EMPTY_STYLE;
  if (!st.sampleCount && !st.manualNotes) {
    return "Aún no tengo muestras de su estilo: escribe claro, directo y natural, como una persona informada en X.";
  }
  const pct = (x) => Math.round(x * 100);
  const lines = [];
  if (st.sampleCount) {
    lines.push(`Analizados ${st.sampleCount} posts suyos. Longitud típica: ~${st.medianLength} caracteres.`);
    lines.push(`Emojis en ${pct(st.emojiRate)}% de posts, hashtags en ${pct(st.hashtagRate)}%, preguntas en ${pct(st.questionRate)}%, exclamaciones en ${pct(st.exclamationRate)}%.`);
    if (st.startsLowercaseRate > 0.4) lines.push("Suele empezar en minúscula.");
    if (st.signaturePhrases?.length) lines.push(`Expresiones habituales: ${st.signaturePhrases.slice(0, 8).join(", ")}.`);
  }
  if (st.manualNotes) lines.push(`Indicaciones del propio usuario: ${st.manualNotes}`);
  if (st.learnedGuide) lines.push(`Guía de estilo aprendida de sus respuestas reales:\n${st.learnedGuide}`);
  return lines.join("\n");
}

// ---------------------------------------------------------------- Aprendizaje (= Learning.swift)

export function emptyPrefs() { return { global: {}, byTopic: {}, preferredLength: null, recentEdits: [], totals: {} }; }

export function topicKey(t) { return String(t).toLowerCase().split(/[^\p{L}]+/u).filter(Boolean).slice(0, 2).join(" "); }

const beta = (b) => b ?? { a: 1, b: 1 };
const mean = (b) => b.a / (b.a + b.b);
const bcount = (b) => b.a + b.b - 2;

/** Registra lo que haces (copiar, abrir en X, editar, 👍/👎…) y actualiza el modelo. Devuelve un modelo nuevo. */
export function recordEvent(prefs, e) {
  const p = structuredClone(prefs ?? emptyPrefs());
  p.totals[e.kind] = (p.totals[e.kind] ?? 0) + 1;
  const tk = topicKey(e.topic ?? "");
  const bump = (s, success, w = 1) => {
    const g = beta(p.global[s]); const t = beta(p.byTopic[tk]?.[s]);
    if (success) { g.a += w; t.a += w; } else { g.b += w; t.b += w; }
    p.global[s] = g; (p.byTopic[tk] ??= {})[s] = t;
  };
  switch (e.kind) {
    case "copied": case "composed":
      if (e.stance) { bump(e.stance, true); for (const o of STANCES) if (o !== e.stance) bump(o, false, 0.35); }
      if (e.finalText) { const len = [...e.finalText].length; p.preferredLength = p.preferredLength == null ? len : p.preferredLength * 0.8 + len * 0.2; }
      break;
    case "thumbsUp": if (e.stance) bump(e.stance, true, 0.5); break;
    case "thumbsDown": if (e.stance) bump(e.stance, false, 1); break;
    case "edited":
      if (e.originalText && e.finalText && e.originalText !== e.finalText) {
        p.recentEdits.push({ before: e.originalText, after: e.finalText });
        p.recentEdits = p.recentEdits.slice(-6);
      }
      break;
    case "dismissed": for (const s of STANCES) bump(s, false, 0.15); break;
    default: break;
  }
  return p;
}

export function stanceScore(prefs, s, topic) {
  const g = beta(prefs?.global?.[s]);
  const t = prefs?.byTopic?.[topicKey(topic)]?.[s];
  if (!t || bcount(t) <= 0) return mean(g);
  const w = Math.min(0.7, bcount(t) / 10);
  return mean(g) * (1 - w) + mean(t) * w;
}

export function ranking(prefs, topic) {
  return [...STANCES].sort((a, b) => stanceScore(prefs, b, topic) - stanceScore(prefs, a, topic));
}

const used = (p) => (p?.totals?.copied ?? 0) + (p?.totals?.composed ?? 0);

export function predictedFavorite(prefs, topic) { return used(prefs) >= 3 ? ranking(prefs, topic)[0] : null; }

export function promptHints(prefs, topic) {
  if (!prefs) return "";
  const h = [];
  if (prefs.preferredLength != null) h.push(`Longitud que suele usar al final: ~${Math.round(prefs.preferredLength)} caracteres.`);
  if (used(prefs) >= 3) h.push(`En temas como este suele preferir el enfoque "${STANCE_LABEL[ranking(prefs, topic)[0]]}"; dale el máximo cuidado.`);
  if (prefs.recentEdits?.length) {
    h.push("Ediciones recientes que hizo a borradores (aprende de ellas: qué quita, qué añade, cómo cambia el tono):");
    for (const e of prefs.recentEdits.slice(-3)) h.push(`ANTES: ${e.before}\nDESPUÉS: ${e.after}`);
  }
  return h.join("\n");
}

export function sortDrafts(drafts, prefs, topic) {
  const order = ranking(prefs, topic);
  return [...drafts].sort((a, b) => order.indexOf(a.stance) - order.indexOf(b.stance));
}

// ---------------------------------------------------------------- Flujo completo (= Engine.swift)

/**
 * post → (Wikipedia) → investigación con búsqueda web → 3 borradores → orden por preferencias.
 * `deps` inyecta red y almacenamiento para poder probarlo sin conexión.
 */
export async function analyze(post, deps) {
  const { apiKey, config = DEFAULT_CONFIG, style, prefs, wiki = async () => [], fetchImpl, signal,
    progress = () => {}, log = () => {}, today = new Date().toISOString().slice(0, 10), domains } = deps;
  const t0 = Date.now();
  progress("researching");
  const articles = await wiki(post).catch(() => []);
  const send = (body) => (m) => callClaude(body, { apiKey, model: m, fetchImpl, signal });
  const rec = { model: config.model, fallbackModel: config.fallbackModel, log, sleep: deps.sleep };

  let research;
  try {
    const body = buildResearchRequest(post, articles, { today, effort: config.researchEffort, domains, maxUses: config.maxWebSearches });
    research = await withRecovery(send(body), rec);
  } catch (e) {
    if (e?.name === "AbortError" || ["unauthorized", "missingAPIKey", "noCredits"].includes(e?.code)) throw e;
    log("Sin búsqueda web: " + e.message + ". Sigo solo con Wikipedia.");
    research = await withRecovery(send(buildResearchRequest(post, articles, { today, effort: config.researchEffort, useWebSearch: false })), rec);
  }
  const report = parseResearch(research, articles);

  progress("drafting");
  const draftsMsg = await withRecovery(async (m) => {
    const msg = await send(buildDraftRequest(post, report, style, prefs, { effort: config.draftingEffort }))(m);
    return { msg, drafts: parseDrafts(msg, report) };
  }, rec);

  const usage = [research.usage, draftsMsg.msg.usage];
  progress("done");
  return {
    post, report,
    drafts: sortDrafts(draftsMsg.drafts, prefs, report.topic),
    predictedFavorite: predictedFavorite(prefs, report.topic),
    usage, totalCostUSD: usage.reduce((a, u) => a + cost(u), 0),
    generatedAt: new Date().toISOString(), durationSeconds: (Date.now() - t0) / 1000,
  };
}

/** Rehace solo los borradores, sin repetir la investigación (más barato). */
export async function regenerateDrafts(result, deps) {
  const { apiKey, config = DEFAULT_CONFIG, style, prefs, fetchImpl, signal, log = () => {} } = deps;
  const out = await withRecovery(async (m) => {
    const msg = await callClaude(buildDraftRequest(result.post, result.report, style, prefs, { effort: config.draftingEffort }), { apiKey, model: m, fetchImpl, signal });
    return { msg, drafts: parseDrafts(msg, result.report) };
  }, { model: config.model, fallbackModel: config.fallbackModel, log, sleep: deps.sleep });
  const usage = [...result.usage, out.msg.usage];
  return { ...result, drafts: sortDrafts(out.drafts, prefs, result.report.topic), usage, totalCostUSD: usage.reduce((a, u) => a + cost(u), 0) };
}
