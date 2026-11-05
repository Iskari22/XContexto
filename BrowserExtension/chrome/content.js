// XContexto para Chrome y Safari (mismo fichero en las dos extensiones; una prueba lo exige).
// Solo LEE el post (texto, autor, enlace) y lo abre en XContexto.
// No hace peticiones de red y no puede escribir ni publicar en X. El único permiso es "storage" (tus ajustes).
(() => {
  const api = globalThis.browser ?? globalThis.chrome;
  const MARK = "data-xcx";
  const MAX_TEXT = 4000;
  // Destino por defecto: la versión web. En el menú de la extensión se puede elegir la app del Mac/iPhone.
  const DEFAULTS = { target: "web", webURL: "https://iskari22.github.io/XContexto/" };
  let settings = { ...DEFAULTS };
  api?.storage?.local.get(DEFAULTS).then((s) => { settings = s; }).catch(() => {});
  api?.storage?.onChanged?.addListener((ch) => { for (const k in ch) settings[k] = ch[k].newValue; });

  function postInfo(article) {
    const textEl = article.querySelector('[data-testid="tweetText"]');
    const timeLink = article.querySelector('a[href*="/status/"] time')?.closest("a");
    const nameEl = article.querySelector('[data-testid="User-Name"]');
    const url = timeLink ? new URL(timeLink.getAttribute("href"), location.origin).href : null;
    const handle = url ? new URL(url).pathname.split("/")[1] ?? "" : "";
    const author = nameEl?.querySelector("span")?.innerText ?? handle;
    return { url, text: (textEl?.innerText ?? "").slice(0, MAX_TEXT), author, handle };
  }

  function destination(info) {
    const q = new URLSearchParams();
    for (const k of ["url", "text", "author", "handle"]) if (info[k]) q.set(k, info[k]);
    if (settings.target === "web" && /^https:\/\//.test(settings.webURL)) {
      return settings.webURL.replace(/[?#].*$/, "") + "?" + q.toString();
    }
    return "xcontexto://analyze?" + q.toString();
  }

  function open(info) {
    const href = destination(info);
    if (href.startsWith("https://")) {
      window.open(href, "_blank", "noopener,noreferrer");
    } else {
      // Esquema local: el sistema lo entrega a la app XContexto (Safari pide permiso la primera vez).
      const a = document.createElement("a");
      a.href = href;
      a.rel = "noopener";
      a.click();
    }
  }

  function decorate(article) {
    if (article.hasAttribute(MARK)) return;
    const bar = article.querySelector('[role="group"]');
    if (!bar) return;
    article.setAttribute(MARK, "1");
    const btn = document.createElement("button");
    btn.className = "xcx-btn";
    btn.type = "button";
    btn.title = "Contexto y borradores (XContexto)";
    btn.setAttribute("aria-label", "Contexto y borradores (XContexto)");
    btn.textContent = "ⓧ";
    btn.addEventListener("click", (e) => {
      e.preventDefault(); e.stopPropagation();
      open(postInfo(article));
    });
    bar.appendChild(btn);
  }

  const scan = () => document.querySelectorAll('article[data-testid="tweet"]').forEach(decorate);
  new MutationObserver(scan).observe(document.body, { childList: true, subtree: true });
  scan();
})();
