const api = globalThis.browser ?? globalThis.chrome;
const $ = (s) => document.querySelector(s);
const saved = $("#saved");

api.storage.local.get({ target: "web", webURL: "https://iskari22.github.io/XContexto/" }).then((s) => {
  const radio = document.querySelector(`input[name=target][value="${s.target}"]`);
  if (radio) radio.checked = true;
  $("#webURL").value = s.webURL;
});

function save() {
  const target = document.querySelector("input[name=target]:checked")?.value ?? "app";
  const webURL = $("#webURL").value.trim();
  if (target === "web" && !/^https:\/\//.test(webURL)) { saved.hidden = false; saved.textContent = "Escribe una dirección https://"; return; }
  api.storage.local.set({ target, webURL }).then(() => { saved.hidden = false; saved.textContent = "Guardado"; });
}
for (const r of document.querySelectorAll("input[name=target]")) r.addEventListener("change", save);
$("#webURL").addEventListener("change", save);
