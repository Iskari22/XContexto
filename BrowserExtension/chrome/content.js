// XContexto: solo LEE el post (texto, autor, enlace) y lo pasa a la app de tu Mac.
// No tiene permisos, no hace peticiones de red y no puede escribir ni publicar en X.
(() => {
  const MARK = "data-xcx";
  const MAX_TEXT = 4000;

  function postInfo(article) {
    const textEl = article.querySelector('[data-testid="tweetText"]');
    const timeLink = article.querySelector('a[href*="/status/"] time')?.closest("a");
    const nameEl = article.querySelector('[data-testid="User-Name"]');
    const url = timeLink ? new URL(timeLink.getAttribute("href"), location.origin).href : null;
    const handle = url ? url.split("/")[3] : "";
    const author = nameEl?.querySelector("span")?.innerText ?? handle;
    return { url, text: (textEl?.innerText ?? "").slice(0, MAX_TEXT), author, handle };
  }

  function open(info) {
    const q = new URLSearchParams();
    if (info.url) q.set("url", info.url);
    if (info.text) q.set("text", info.text);
    if (info.author) q.set("author", info.author);
    if (info.handle) q.set("handle", info.handle);
    // Esquema local: el sistema lo entrega a la app XContexto (Chrome pide permiso la primera vez).
    const a = document.createElement("a");
    a.href = "xcontexto://analyze?" + q.toString();
    a.rel = "noopener";
    a.click();
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
