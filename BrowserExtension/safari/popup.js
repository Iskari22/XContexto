const api = globalThis.browser ?? globalThis.chrome;
const $ = (s) => document.querySelector(s);
const saved = $("#saved");
const DEFAULTS = { target: "web", webURL: "https://iskari22.github.io/XContexto/", altClick: "app", styleNotes: "" };

api.storage.local.get(DEFAULTS).then((s) => {
  for (const name of ["target", "altClick"]) {
    const radio = document.querySelector(`input[name=${name}][value="${s[name]}"]`);
    if (radio) radio.checked = true;
  }
  $("#webURL").value = s.webURL;
  $("#styleNotes").value = s.styleNotes;
});

function save() {
  const target = document.querySelector("input[name=target]:checked")?.value ?? "app";
  const altClick = document.querySelector("input[name=altClick]:checked")?.value ?? "app";
  const webURL = $("#webURL").value.trim();
  const styleNotes = $("#styleNotes").value.trim().slice(0, 1000);
  if (target === "web" && !/^https:\/\//.test(webURL)) { saved.hidden = false; saved.textContent = "Escribe una dirección https://"; return; }
  api.storage.local.set({ target, webURL, altClick, styleNotes }).then(() => { saved.hidden = false; saved.textContent = "Guardado"; });
}
for (const r of document.querySelectorAll("input[name=target], input[name=altClick]")) r.addEventListener("change", save);
$("#webURL").addEventListener("change", save);
$("#styleNotes").addEventListener("change", save);
