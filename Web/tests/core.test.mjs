// node --test Web/tests   (sin dependencias, sin red, sin gasto de API)
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import * as C from "../js/core.js";
import { fakeResearchResponse, fakeDraftsResponse, fakeFetch } from "./fixtures.mjs";

describe("Seguridad: nunca publica", () => {
  test("composeURL solo abre el editor de X", () => {
    const u = new URL(C.composeURL("Hola & adiós", "123"));
    assert.equal(u.host, "x.com");
    assert.equal(u.pathname, "/intent/post");
    assert.equal(u.searchParams.get("text"), "Hola & adiós");
    assert.equal(u.searchParams.get("in_reply_to"), "123");
    assert.ok(!C.composeURL("x", "1; DROP").includes("in_reply_to"));
  });

  test("la petición a la API lleva la cabecera de navegador y respaldo automático", async () => {
    const calls = [];
    const f = fakeFetch([fakeDraftsResponse()], calls);
    await C.callClaude({ max_tokens: 10, messages: [{ role: "user", content: "hola" }] }, { apiKey: "sk-ant-test-123456789", model: "claude-opus-5-5", fetchImpl: f });
    const { url, init } = calls[0];
    assert.equal(url, "https://api.anthropic.com/v1/messages");
    assert.equal(init.headers["anthropic-dangerous-direct-browser-access"], "true");
    assert.equal(init.headers["anthropic-version"], C.API_VERSION);
    assert.equal(init.headers["anthropic-beta"], "server-side-fallback-2026-07-01");
    const body = JSON.parse(init.body);
    assert.equal(body.model, "claude-opus-5-5");
    assert.equal(body.fallbacks, "default");
    assert.ok(!("temperature" in body));
  });

  test("sin clave no hay llamada", async () => {
    await assert.rejects(C.callClaude({ messages: [] }, { apiKey: "" }), (e) => e.code === "missingAPIKey");
  });
});

describe("Posts", () => {
  test("reconoce URLs de posts", () => {
    assert.equal(C.parsePostURL("https://x.com/elonmusk/status/1234567890?s=20")?.id, "1234567890");
    assert.equal(C.parsePostURL("https://twitter.com/RTVE/status/42")?.handle, "RTVE");
    assert.equal(C.parsePostURL("https://mobile.twitter.com/a/status/7/photo/1")?.canonical, "https://x.com/a/status/7");
    assert.equal(C.parsePostURL("https://x.com/home"), null);
    assert.equal(C.parsePostURL("https://evil.com/a/status/1"), null);
    assert.equal(C.parsePostURL("javascript:alert(1)"), null);
    assert.equal(C.findPostURL("mira esto https://x.com/ana/status/99 qué fuerte")?.id, "99");
  });

  test("lee el HTML de oEmbed", () => {
    const html = `<blockquote class="twitter-tweet"><p lang="es" dir="ltr">Hola &amp; adiós<br>línea 2 <a href="https://t.co/x">pic</a> &#128512;</p>&mdash; Autor (@a) <a href="#">1 ene</a></blockquote>`;
    assert.equal(C.tweetTextFromOEmbed(html), "Hola & adiós\nlínea 2 pic 😀");
    assert.equal(C.langFromOEmbed(html), "es");
  });

  test("makePost: texto pegado con la URL del post", () => {
    const p = C.makePost({ text: "El PIB creció un 3%\n\nhttps://x.com/ana/status/55?s=46" });
    assert.equal(p.id, "55");
    assert.equal(p.handle, "ana");
    assert.equal(p.text, "El PIB creció un 3%");
    assert.equal(p.url, "https://x.com/ana/status/55");
  });

  test("makePost: solo URL → necesita oEmbed", () => {
    assert.equal(C.makePost({ text: "https://x.com/ana/status/55" }), null);
    const p = C.makePost({ text: "https://x.com/ana/status/55", oembed: { html: '<p lang="en">Hello world</p>', author_name: "Ana" } });
    assert.equal(p.text, "Hello world");
    assert.equal(p.lang, "en");
    assert.equal(p.authorName, "Ana");
  });

  test("makePost: texto sin URL", () => {
    const p = C.makePost({ text: "La OTAN despliega tropas en Polonia" });
    assert.ok(p.id.startsWith("local-"));
    assert.equal(p.lang, "es");
  });

  test("longitud como en X", () => {
    assert.equal(C.xLength("ver https://www.example.com/un/enlace/larguisimo/de/verdad"), 4 + 23);
    assert.equal(C.xLength("ñandú"), 5);
    assert.equal(C.xLength("👍"), 2);
    assert.equal(C.xLength("👍🏽"), 2);
    assert.equal(C.xLength("日本"), 4);
  });

  test("consulta para Wikipedia con entidades", () => {
    const q = C.keywordQuery("La OTAN despliega tropas en Polonia tras la cumbre de #Vilna https://t.co/abc");
    assert.ok(q.includes("OTAN") && q.includes("Polonia") && q.includes("Vilna"), q);
  });

  test("quita la @ inicial de un borrador", () => {
    assert.equal(C.stripLeadingMentions("@ana @luis Los datos dicen otra cosa"), "Los datos dicen otra cosa");
    assert.equal(C.stripLeadingMentions("Según @INE_es el paro baja"), "Según @INE_es el paro baja");
  });
});

describe("Fuentes", () => {
  test("lista de dominios sin duplicados y ≤ 64", () => {
    const d = C.trustedDomains();
    assert.equal(new Set(d).size, d.length);
    assert.ok(d.length <= 64);
    assert.ok(d.includes("realinstitutoelcano.org"));
  });

  test("dominios extra se normalizan y validan", () => {
    const d = C.trustedDomains(["https://www.Heraldo.es/", "no es dominio", "elpais.com"]);
    assert.ok(d.includes("heraldo.es"));
    assert.ok(!d.includes("no es dominio"));
    assert.equal(d.filter((x) => x === "elpais.com").length, 1);
  });

  test("clasifica fuentes", () => {
    assert.equal(C.sourceKind("https://es.wikipedia.org/wiki/OTAN"), "wikipedia");
    assert.equal(C.sourceKind("https://maldita.es/x"), "factCheck");
    assert.equal(C.sourceKind("https://www.nato.int/cps/en"), "institution");
    assert.equal(C.sourceKind("https://www.ine.es/prensa"), "institution");
    assert.equal(C.sourceKind("https://elpais.com/a"), "news");
    assert.equal(C.sourceKind("https://notelpais.com/a"), "other");
    assert.equal(C.sourceKind("https://blog.example.com/a"), "other");
  });
});

describe("JSON y URLs", () => {
  test("extrae JSON", () => {
    assert.equal(C.extractJSON('Aquí tienes:\n<json>{"topic": "x"}</json>').topic, "x");
    assert.equal(C.extractJSON('```json\n{"a":1}\n```').a, 1);
    assert.throws(() => C.extractJSON("sin json"), (e) => e.code === "decoding");
  });

  test("normaliza URLs", () => {
    assert.equal(C.normalizeURL("https://www.ElPais.com/a/b/?utm=1#x"), "elpais.com/a/b");
  });
});

describe("Investigación", () => {
  const post = { id: "1", url: "https://x.com/a/status/1", authorName: "A", handle: "a", text: "El paro bajó al 2% en 2025", lang: "es" };
  const wiki = [{ title: "Paro en España", extract: "El paro…", url: "https://es.wikipedia.org/wiki/Paro" }];

  test("la petición usa la búsqueda web limitada a fuentes reputadas y la fecha de hoy", () => {
    const b = C.buildResearchRequest(post, wiki, { today: "2026-11-05" });
    assert.equal(b.tools[0].type, "web_search_20260209");
    assert.deepEqual(b.tools[0].allowed_domains, C.trustedDomains());
    assert.ok(b.messages[0].content.startsWith("<fecha_de_hoy>2026-11-05</fecha_de_hoy>"));
    assert.equal(b.system[0].cache_control.type, "ephemeral");
    assert.equal(b.output_config.effort, "medium");
    assert.equal(C.buildResearchRequest(post, [], { useWebSearch: false }).tools, undefined);
  });

  test("solo acepta URLs que aparecieron de verdad", () => {
    const msg = C.readMessage(fakeResearchResponse());
    const r = C.parseResearch(msg, wiki);
    assert.equal(r.topic, "Paro en España");
    // La URL inventada se descarta; la de INE y la de Wikipedia se aceptan.
    assert.equal(r.droppedUnverifiedSources, 1);
    assert.ok(r.sources.every((s) => s.verified));
    assert.ok(r.sources.some((s) => s.url.includes("ine.es")));
    assert.ok(!r.sources.some((s) => s.url.includes("inventada")));
    assert.ok(r.sources.some((s) => s.kind === "wikipedia"));
    // El dato apoyado solo en la URL inventada desaparece.
    assert.equal(r.keyFacts.length, 1);
    assert.ok(!r.keyFacts.some((f) => f.text.includes("inventado")));
  });

  test("un 'false' sin fuente verificada se rebaja a 'no verificable'", () => {
    const msg = C.readMessage(fakeResearchResponse());
    const r = C.parseResearch(msg, wiki);
    const c = r.claims.find((x) => x.claim.includes("2%"));
    assert.equal(c.verdict, "disputed"); // tiene fuente del INE
    const sinFuente = r.claims.find((x) => x.claim.includes("récord"));
    assert.equal(sinFuente.verdict, "unverifiable");
  });

  test("veredicto desconocido → no verificable", () => {
    const msg = { text: '<json>{"claims":[{"claim":"x","verdict":"quizá"}]}</json>', webResults: [], cited: [] };
    assert.equal(C.parseResearch(msg, []).claims[0].verdict, "unverifiable");
  });
});

describe("Borradores", () => {
  const post = { id: "1", handle: "a", text: "El paro bajó al 2% en 2025", lang: "es" };
  const report = C.parseResearch(C.readMessage(fakeResearchResponse()), []);

  test("la petición pide JSON con esquema y pone el estilo en caché", () => {
    const b = C.buildDraftRequest(post, report, C.EMPTY_STYLE, C.emptyPrefs());
    assert.equal(b.output_config.format.type, "json_schema");
    assert.equal(b.system[1].cache_control.type, "ephemeral");
    assert.ok(b.system[1].text.includes("<estilo_del_usuario>"));
    assert.ok(b.messages[0].content.includes("<informe_de_contexto>"));
    assert.ok(b.messages[0].content.includes("ine.es"));
  });

  test("lee los 3 borradores y enlaza sus fuentes", () => {
    const d = C.parseDrafts(C.readMessage(fakeDraftsResponse()), report);
    assert.deepEqual(d.map((x) => x.stance).sort(), ["critical", "neutral", "supportive"]);
    assert.ok(d.find((x) => x.stance === "critical").sources.length >= 1);
    assert.ok(!d.some((x) => x.text.startsWith("@")));
    assert.ok(d.every((x) => typeof x.length === "number"));
  });

  test("falla si faltan borradores", () => {
    const msg = { text: '{"drafts":[{"stance":"neutral","text":"a","rationale":"","source_urls":[]}]}' };
    assert.throws(() => C.parseDrafts(msg, report), (e) => e.code === "decoding");
  });
});

describe("Cliente de la API", () => {
  test("continúa el turno tras pause_turn y suma el uso", async () => {
    const calls = [];
    const paused = { id: "m1", model: "claude-opus-5-5", stop_reason: "pause_turn", content: [{ type: "server_tool_use", id: "s1", name: "web_search", input: {} }],
      usage: { input_tokens: 100, output_tokens: 10, server_tool_use: { web_search_requests: 1 } } };
    const f = fakeFetch([paused, fakeResearchResponse()], calls);
    const msg = await C.callClaude({ max_tokens: 10, messages: [{ role: "user", content: "x" }] }, { apiKey: "sk-ant-test-123456789", model: "claude-opus-5-5", fetchImpl: f });
    assert.equal(calls.length, 2);
    const second = JSON.parse(calls[1].init.body);
    assert.equal(second.messages.length, 2);
    assert.equal(second.messages[1].role, "assistant");
    assert.equal(msg.usage.inputTokens, 100 + 2000);
    assert.equal(msg.usage.webSearches, 1 + 2);
    assert.ok(msg.text.includes("<json>"));
  });

  test("errores: sin saldo, clave mala, saturada, rechazo", async () => {
    const call = (resp, status) => C.callClaude({ messages: [] }, { apiKey: "sk-ant-test-123456789", model: "m", fetchImpl: fakeFetch([resp], [], status) });
    await assert.rejects(call({ error: { message: "Your credit balance is too low" } }, 400), (e) => e.code === "noCredits");
    await assert.rejects(call({}, 401), (e) => e.code === "unauthorized" && !e.retryable);
    await assert.rejects(call({}, 529), (e) => e.code === "overloaded" && e.retryable);
    await assert.rejects(call({ stop_reason: "refusal", stop_details: { category: "cyber" }, content: [] }, 200), (e) => e.code === "refusal" && /cyber/.test(e.message));
    await assert.rejects(call({ stop_reason: "max_tokens", content: [] }, 200), (e) => e.code === "truncated");
  });

  test("reintenta y cambia al modelo de respaldo si la API sigue saturada", async () => {
    const models = [];
    const v = await C.withRecovery(async (m) => {
      models.push(m);
      if (models.length < 3) throw new C.XCError("overloaded", "saturada");
      return 7;
    }, { model: "claude-opus-5-5", fallbackModel: "claude-sonnet-5-5", sleep: async () => {} });
    assert.equal(v, 7);
    assert.deepEqual(models, ["claude-opus-5-5", "claude-opus-5-5", "claude-sonnet-5-5"]);
  });

  test("no reintenta errores de clave", async () => {
    let n = 0;
    await assert.rejects(C.withRecovery(async () => { n++; throw new C.XCError("unauthorized", "x"); }, { sleep: async () => {} }));
    assert.equal(n, 1);
  });

  test("coste estimado (= Pricing.swift)", () => {
    const u = { model: "claude-opus-5-5", inputTokens: 1_000_000, outputTokens: 100_000, cacheReadTokens: 0, cacheWriteTokens: 0, webSearches: 5 };
    assert.ok(Math.abs(C.cost(u) - (4 + 2 + 0.05)) < 1e-9);
  });
});

describe("Flujo completo (API simulada)", () => {
  test("post → investigación → 3 borradores ordenados por preferencia", async () => {
    const calls = [];
    const stages = [];
    let prefs = C.emptyPrefs();
    for (let i = 0; i < 4; i++) prefs = C.recordEvent(prefs, { kind: "copied", topic: "Paro en España", stance: "critical" });
    const post = C.makePost({ text: "El paro bajó al 2% en 2025, récord histórico https://x.com/a/status/1" });
    const r = await C.analyze(post, {
      apiKey: "sk-ant-test-123456789", style: C.EMPTY_STYLE, prefs, fetchImpl: fakeFetch([fakeResearchResponse(), fakeDraftsResponse()], calls),
      wiki: async () => [], progress: (s) => stages.push(s), today: "2026-11-05",
    });
    assert.deepEqual(stages, ["researching", "drafting", "done"]);
    assert.equal(calls.length, 2);
    assert.equal(r.drafts[0].stance, "critical");
    assert.equal(r.predictedFavorite, "critical");
    assert.ok(r.totalCostUSD > 0);
  });

  test("si la búsqueda web falla, sigue solo con Wikipedia", async () => {
    const calls = [];
    const bad = { error: { message: "web search unavailable" } };
    const f = async (url, init) => {
      calls.push({ url, init });
      const body = JSON.parse(init.body);
      if (body.tools) return { status: 400, headers: new Map(), json: async () => bad };
      const data = body.output_config.format ? fakeDraftsResponse() : fakeResearchResponse();
      return { status: 200, headers: new Map(), json: async () => data };
    };
    const post = C.makePost({ text: "El paro bajó al 2% en 2025" });
    const r = await C.analyze(post, { apiKey: "sk-ant-test-123456789", style: C.EMPTY_STYLE, prefs: C.emptyPrefs(), fetchImpl: f, sleep: async () => {} });
    assert.equal(r.drafts.length, 3);
    assert.ok(calls.some((c) => !JSON.parse(c.init.body).tools));
  });
});

describe("Estilo", () => {
  const js = `window.YTD.tweets.part0 = [
    {"tweet": {"full_text": "@fulano Totalmente de acuerdo, los datos del INE lo confirman", "favorite_count": "12", "retweet_count": "3", "in_reply_to_status_id_str": "99", "in_reply_to_screen_name": "fulano", "lang": "es"}},
    {"tweet": {"full_text": "RT @otro: algo", "favorite_count": "0", "retweet_count": "0", "lang": "es"}},
    {"tweet": {"full_text": "¿Alguien ha leído el informe del Banco de España? Muy interesante", "favorite_count": "40", "retweet_count": "10", "lang": "es"}}
  ]`;

  test("importa el archivo de X", () => {
    const s = C.parseTweetsJS(js);
    assert.equal(s.length, 3);
    assert.ok(s[0].text.startsWith("Totalmente"));
    assert.equal(s[0].replyToHandle, "fulano");
    const p = C.buildStyle(s);
    assert.equal(p.sampleCount, 2);
    assert.equal(p.questionRate, 0.5);
    assert.ok(C.exemplars(p, "informe del Banco de España").length > 0);
    assert.ok(C.styleDescription(p).includes("Analizados 2 posts"));
  });

  test("sin muestras ni notas, estilo genérico", () => {
    assert.ok(C.styleDescription(C.EMPTY_STYLE).startsWith("Aún no tengo muestras"));
    assert.ok(C.styleDescription({ ...C.EMPTY_STYLE, manualNotes: "tuteo" }).includes("tuteo"));
  });
});

describe("Aprendizaje (= LearningTests en Swift)", () => {
  test("aprende la postura preferida", () => {
    let m = C.emptyPrefs();
    for (let i = 0; i < 5; i++) {
      m = C.recordEvent(m, { kind: "shown", topic: "guerra Ucrania" });
      m = C.recordEvent(m, { kind: "copied", topic: "guerra Ucrania", stance: "critical", finalText: "a".repeat(150) });
    }
    assert.equal(C.ranking(m, "guerra Ucrania")[0], "critical");
    assert.equal(C.predictedFavorite(m, "guerra Ucrania"), "critical");
    assert.ok(Math.abs(m.preferredLength - 150) < 1);
  });

  test("preferencias por tema", () => {
    let m = C.emptyPrefs();
    for (let i = 0; i < 6; i++) m = C.recordEvent(m, { kind: "copied", topic: "economía", stance: "neutral" });
    for (let i = 0; i < 6; i++) m = C.recordEvent(m, { kind: "copied", topic: "geopolítica", stance: "critical" });
    assert.equal(C.ranking(m, "economía")[0], "neutral");
    assert.equal(C.ranking(m, "geopolítica")[0], "critical");
  });

  test("recuerda ediciones", () => {
    const m = C.recordEvent(C.emptyPrefs(), { kind: "edited", topic: "t", stance: "neutral", originalText: "¡Gran punto! Los datos…", finalText: "Los datos…" });
    assert.ok(C.promptHints(m, "t").includes("DESPUÉS: Los datos…"));
  });

  test("no modifica el modelo original", () => {
    const a = C.emptyPrefs();
    C.recordEvent(a, { kind: "copied", topic: "x", stance: "neutral" });
    assert.deepEqual(a.totals, {});
  });
});
