// La web y las apps de Apple deben usar exactamente los mismos prompts y la misma lista de fuentes.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { RESEARCH_SYSTEM, DRAFT_SYSTEM, DRAFT_SCHEMA } from "../js/prompts.js";
import { TRUSTED_DOMAINS, RATES, API_VERSION, DEFAULT_CONFIG } from "../js/core.js";

const root = fileURLToPath(new URL("../../", import.meta.url));
const swift = (p) => readFileSync(root + p, "utf8");

/** Texto de un `static let system = """ … """` de Swift, sin la sangría común. */
function swiftSystemPrompt(src) {
  const m = /static let system = """\n([\s\S]*?)\n( *)"""/.exec(src);
  assert.ok(m, "no encuentro `static let system` en el fichero Swift");
  const indent = m[2];
  return m[1].split("\n").map((l) => (l.startsWith(indent) ? l.slice(indent.length) : l.trimStart())).join("\n");
}

test("prompt de investigación igual en Swift y en la web", () => {
  assert.equal(swiftSystemPrompt(swift("Sources/XCResearch/ResearchService.swift")), RESEARCH_SYSTEM);
});

test("prompt de borradores igual en Swift y en la web", () => {
  assert.equal(swiftSystemPrompt(swift("Sources/XCEngine/DraftWriter.swift")), DRAFT_SYSTEM);
});

test("esquema de borradores con las mismas posturas", () => {
  const src = swift("Sources/XCEngine/DraftWriter.swift");
  for (const s of DRAFT_SCHEMA.properties.drafts.items.properties.stance.enum) assert.ok(src.includes(`"${s}"`));
  for (const k of DRAFT_SCHEMA.properties.drafts.items.required) assert.ok(src.includes(`"${k}"`), k);
});

test("misma lista de fuentes reputadas", () => {
  const src = swift("Sources/XCResearch/TrustedSources.swift");
  const block = /domains: \[String\] = \[([\s\S]*?)\n    \]/.exec(src)[1];
  const swiftDomains = [...block.matchAll(/"([^"]+)"/g)].map((m) => m[1]);
  assert.deepEqual(swiftDomains, TRUSTED_DOMAINS);
});

test("mismos precios, versión de la API y modelos", () => {
  const pricing = swift("Sources/XCCore/Pricing.swift");
  for (const [model, r] of Object.entries(RATES)) {
    const m = new RegExp(`"${model}": Rate\\(input: ([\\d.]+), output: ([\\d.]+), cacheRead: ([\\d.]+), cacheWrite: ([\\d.]+)\\)`).exec(pricing);
    assert.ok(m, model);
    assert.deepEqual(m.slice(1).map(Number), [r.input, r.output, r.cacheRead, r.cacheWrite], model);
  }
  assert.ok(pricing.includes("webSearchPerRequest = 0.01"));
  const client = swift("Sources/XCClaude/ClaudeClient.swift");
  assert.ok(client.includes(`apiVersion = "${API_VERSION}"`));
  assert.ok(client.includes(`model: String = "${DEFAULT_CONFIG.model}"`));
  assert.ok(client.includes(`fallbackModel: String = "${DEFAULT_CONFIG.fallbackModel}"`));
});

