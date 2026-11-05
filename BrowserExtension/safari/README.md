# Extensión de Safari (macOS e iOS)

Añade un botón **ⓧ** a cada post de x.com. Al pulsarlo, abre ese post en XContexto:

- por defecto, en la **versión web** (`https://iskari22.github.io/XContexto/`), o
- en la **app** de tu Mac o iPhone (`xcontexto://analyze?…`), si lo eliges en el menú de la extensión.

Solo lee el post que eliges (texto, autor y enlace). No hace peticiones de red y no puede publicar ni escribir en X.
Su único permiso es `storage`, para recordar tus ajustes.

## Convertirla en el Mac (una vez)

```bash
xcrun safari-web-extension-converter BrowserExtension/safari \
  --project-location Apps/SafariExtension \
  --app-name "XContexto para Safari" \
  --bundle-identifier com.xcontexto.safari \
  --swift --copy-resources --no-open --no-prompt
```

Después, en Xcode:

1. Abre `Apps/SafariExtension/XContexto para Safari/XContexto para Safari.xcodeproj`.
2. En cada *target* (macOS, iOS y sus extensiones) elige tu equipo en *Signing & Capabilities*.
3. **macOS**: ejecuta el esquema de macOS → Safari → Ajustes → Extensiones → activa *XContexto*.
   Si no aparece: Safari → Ajustes → Avanzado → «Mostrar funciones para desarrolladores», y en el menú
   Desarrollo → «Permitir extensiones sin firmar» (hay que repetirlo cada vez que abres Safari).
4. **iPhone**: ejecuta el esquema de iOS en tu iPhone → Ajustes → Apps → Safari → Extensiones → *XContexto* →
   actívala y permite x.com.

Sin cuenta de pago de Apple Developer, la app de iOS instalada desde Xcode caduca a los 7 días (hay que volver a
ejecutarla desde Xcode). En el Mac no caduca.

## App en lugar de la versión web

Pulsa el icono de la extensión en la barra de Safari → «La app XContexto (Mac / iPhone)».

## Pruebas

`node BrowserExtension/tests/extension.e2e.mjs` comprueba los scripts de Safari y Chrome sobre una página de X simulada.

## ⌥ + clic: analizar en Claude (sin API)

Mantén pulsada **⌥ Opción** (Alt en Windows) y haz clic en cualquier parte de un post. La extensión copia el post con
las instrucciones de análisis (contexto, verificación y 3 borradores: neutro, a favor y crítico) y abre la **app de
escritorio de Claude** con el texto. Usa tu suscripción de Claude, no la API, así que no gasta créditos.

- Si Claude se abre sin el texto escrito, pégalo con ⌘V (Ctrl+V) y pulsa Intro: ya está copiado.
- La primera vez el navegador pregunta si quieres abrir la app de Claude: marca «Permitir siempre».
- En el menú de la extensión puedes elegir abrir **claude.ai** en el navegador en vez de la app, desactivar el atajo,
  o escribir cómo escribes tú (tuteo, sin emojis…) para que los borradores suenen a ti.
