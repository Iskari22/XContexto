// Red del navegador: Wikipedia y lectura de posts de X. Nada de esto puede publicar ni escribir en X.
import { keywordQuery, wikiHost } from "./core.js";

const WIKI_HEADERS = { "Api-User-Agent": "XContexto-web/0.2 (app personal; contexto de posts)" };

async function getJSON(url, signal, ms = 10000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  signal?.addEventListener("abort", () => ctrl.abort(), { once: true });
  try {
    const r = await fetch(url, { headers: WIKI_HEADERS, signal: ctrl.signal, credentials: "omit", referrerPolicy: "no-referrer" });
    return r.ok ? await r.json() : null;
  } catch { return null; } finally { clearTimeout(t); }
}

/** Hasta 3 artículos de Wikipedia relacionados con el post (en paralelo; si falla, devuelve []). */
export async function wikipediaArticles(post, { limit = 3, signal } = {}) {
  const q = keywordQuery(post.text);
  if (!q) return [];
  const host = wikiHost(post.lang);
  const search = await getJSON(`https://${host}/w/rest.php/v1/search/page?q=${encodeURIComponent(q)}&limit=${limit}`, signal);
  const pages = (search?.pages ?? []).slice(0, limit);
  const out = await Promise.all(pages.map(async (p) => {
    if (!p?.key) return null;
    const s = await getJSON(`https://${host}/api/rest_v1/page/summary/${encodeURIComponent(p.key)}`, signal);
    if (!s?.extract) return null;
    return { title: s.title ?? p.key, extract: s.extract, url: s.content_urls?.desktop?.page ?? `https://${host}/wiki/${encodeURIComponent(p.key)}` };
  }));
  return out.filter(Boolean);
}

/**
 * Lee un post público con oEmbed de X. oEmbed no permite CORS, así que se usa JSONP DENTRO de un iframe
 * con `sandbox="allow-scripts"` (origen opaco): el script de X no puede leer tu clave ni nada de esta página.
 * Devuelve {html, author_name} o null (post protegido/borrado, o X lo bloquea): entonces se pide pegar el texto.
 */
export function fetchOEmbed(canonicalURL, { timeoutMs = 9000 } = {}) {
  return new Promise((resolve) => {
    const frame = document.createElement("iframe");
    frame.setAttribute("sandbox", "allow-scripts");
    frame.setAttribute("aria-hidden", "true");
    frame.style.display = "none";
    const nonce = crypto.getRandomValues(new Uint32Array(2)).join("");
    let done = false;
    const finish = (v) => {
      if (done) return;
      done = true;
      window.removeEventListener("message", onMsg);
      clearTimeout(timer);
      frame.remove();
      resolve(v);
    };
    const onMsg = (e) => {
      if (e.source !== frame.contentWindow || e.data?.nonce !== nonce) return;
      const d = e.data;
      if (d.ok && typeof d.html === "string" && d.html.length < 50000) {
        finish({ html: d.html, author_name: typeof d.author_name === "string" ? d.author_name.slice(0, 100) : "" });
      } else finish(null);
    };
    window.addEventListener("message", onMsg);
    const timer = setTimeout(() => finish(null), timeoutMs);
    frame.src = `oembed.html#${new URLSearchParams({ url: canonicalURL, nonce })}`;
    document.body.appendChild(frame);
  });
}
