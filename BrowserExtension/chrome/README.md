# Extensión de Chrome

Añade un botón **ⓧ** a cada post de x.com. Al pulsarlo abre ese post en XContexto, que investiga el contexto y
escribe 3 borradores:

- por defecto, en la **versión web**: `https://iskari22.github.io/XContexto/`;
- o en la **app del Mac** (`xcontexto://`), si lo eliges en el menú de la extensión.

Solo lee el post que eliges (texto, autor y enlace). No hace peticiones de red y no puede publicar ni escribir en X.
Su único permiso es `storage`, para recordar tus ajustes.

## Instalarla (2 minutos)

1. Descarga y descomprime `xcontexto-chrome.zip`, o usa directamente esta carpeta (`BrowserExtension/chrome`).
2. En Chrome, abre `chrome://extensions`.
3. Activa **Modo de desarrollador** (arriba a la derecha).
4. Pulsa **Cargar descomprimida** y elige la carpeta.
5. Fija la extensión: icono del puzle 🧩 → chincheta junto a *XContexto*.

Abre cualquier post en x.com: verás el botón ⓧ a la derecha de los iconos de respuesta, retuit y me gusta.

## ⌥ + clic: analizar en Claude (sin API)

Mantén pulsada **⌥ Opción** (Alt en Windows) y haz clic en cualquier parte de un post. La extensión copia el post con
las instrucciones de análisis (contexto, verificación y 3 borradores: neutro, a favor y crítico) y abre la **app de
escritorio de Claude** con el texto. Usa tu suscripción de Claude, no la API, así que no gasta créditos.

- Si Claude se abre sin el texto escrito, pégalo con ⌘V (Ctrl+V) y pulsa Intro: ya está copiado.
- La primera vez el navegador pregunta si quieres abrir la app de Claude: marca «Permitir siempre».
- En el menú de la extensión puedes elegir abrir **claude.ai** en el navegador en vez de la app, desactivar el atajo,
  o escribir cómo escribes tú (tuteo, sin emojis…) para que los borradores suenen a ti.

## Ajustes

Pulsa el icono de XContexto en la barra de Chrome para elegir entre la versión web y la app del Mac, o para usar otra
dirección web.

## Notas

- El código (`content.js`, menú e iconos) es el mismo que el de la extensión de Safari; solo cambia el manifiesto.
  La prueba `node BrowserExtension/tests/extension.e2e.mjs` falla si se desincronizan.
- Si X cambia el HTML de su web y el botón deja de aparecer, hay que ajustar los selectores de `content.js`.
