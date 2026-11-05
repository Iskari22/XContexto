# Extensión de Safari (macOS e iOS)

Añade un botón **ⓧ** a cada post de x.com. Al pulsarlo, abre ese post en XContexto:

- en la **app** de tu Mac o iPhone (`xcontexto://analyze?…`), o
- en la **versión web** (PWA), si lo eliges en el menú de la extensión.

Solo lee el post que eliges (texto, autor y enlace). No hace peticiones de red y no puede publicar ni escribir en X.
Su único permiso es `storage`, para recordar a dónde abrir.

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

## Versión web en lugar de la app

Pulsa el icono de la extensión en la barra de Safari → «La versión web» → escribe la dirección de tu web
(p. ej. `https://iskari22.github.io/XContexto/`).

## Pruebas

`node BrowserExtension/tests/extension.e2e.mjs` comprueba los scripts de Safari y Chrome sobre una página de X simulada.
