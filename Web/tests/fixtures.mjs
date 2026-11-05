// Respuestas simuladas de la API (formato real de /v1/messages). Ninguna prueba llama a la API de verdad.

export function fakeResearchResponse() {
  const report = {
    topic: "Paro en España",
    summary: "El post afirma que el paro bajó al 2% en 2025.",
    background: "La EPA del INE mide el paro cada trimestre.",
    key_facts: [
      { text: "La tasa de paro fue del 10,5% en el tercer trimestre de 2025 (EPA).", source_urls: ["https://www.ine.es/daco/daco42/daco4211/epa0325.pdf"] },
      { text: "Dato inventado.", source_urls: ["https://inventada.example.com/nada"] },
    ],
    claims: [
      { claim: "El paro bajó al 2%", verdict: "disputed", explanation: "La EPA da un 10,5%.", source_urls: ["https://ine.es/daco/daco42/daco4211/epa0325.pdf?x=1"] },
      { claim: "Es un récord histórico", verdict: "false", explanation: "Sin datos.", source_urls: [] },
    ],
    perspectives: [{ label: "Gobierno", text: "Destaca la creación de empleo." }],
  };
  return {
    id: "msg_research", model: "claude-opus-5-5", stop_reason: "end_turn",
    content: [
      { type: "server_tool_use", id: "srv_1", name: "web_search", input: { query: "EPA paro 2025" } },
      { type: "web_search_tool_result", tool_use_id: "srv_1", content: [
        { type: "web_search_result", url: "https://www.ine.es/daco/daco42/daco4211/epa0325.pdf", title: "EPA tercer trimestre 2025", encrypted_content: "x" },
      ] },
      { type: "text", text: "<json>" + JSON.stringify(report) + "</json>" },
    ],
    usage: { input_tokens: 2000, output_tokens: 800, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, server_tool_use: { web_search_requests: 2 } },
  };
}

export function fakeDraftsResponse() {
  const drafts = {
    drafts: [
      { stance: "neutral", text: "Para situarlo: la EPA del INE mide el paro cada trimestre; el último dato es del 10,5%.", rationale: "Aporta el dato oficial.", source_urls: ["https://www.ine.es/daco/daco42/daco4211/epa0325.pdf"] },
      { stance: "supportive", text: "El empleo mejora, aunque el 2% no cuadra con la EPA.", rationale: "Apoya con matiz.", source_urls: [] },
      { stance: "critical", text: "@a El dato no es del 2%: la EPA del INE lo sitúa en el 10,5% (3T 2025).", rationale: "Refuta con la EPA.", source_urls: ["https://ine.es/daco/daco42/daco4211/epa0325.pdf"] },
    ],
  };
  return {
    id: "msg_drafts", model: "claude-opus-5-5", stop_reason: "end_turn",
    content: [{ type: "text", text: JSON.stringify(drafts) }],
    usage: { input_tokens: 1500, output_tokens: 400, cache_read_input_tokens: 1000, cache_creation_input_tokens: 0 },
  };
}

/** fetch simulado que devuelve las respuestas en orden y guarda las llamadas. */
export function fakeFetch(responses, calls = [], status = 200) {
  let i = 0;
  return async (url, init) => {
    calls.push({ url, init });
    const data = responses[Math.min(i++, responses.length - 1)];
    return { status, headers: new Map(), json: async () => data };
  };
}
