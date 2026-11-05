# XContexto

Haz clic en un post de X → ventana con **contexto ampliado** (Wikipedia + fuentes reputadas + verificación de afirmaciones)
y **3 borradores con tu estilo**: neutro (amplía), a favor (refuerza con datos) y crítico (refuta con datos).

La app **no puede publicar**: no tiene credenciales de X y su cortafuegos interno bloquea cualquier escritura que no sea hacia
`api.anthropic.com`. Tú copias el borrador o lo abres en X y pulsas Publicar.

## Estructura (paquetes independientes que se unen en el motor)

| Paquete | Qué hace |
|---|---|
| `XCCore` | Modelos, errores, precios, almacenamiento |
| `XCSecurity` | Cortafuegos de red (también en redirecciones), Llavero, Face ID, URL de "Abrir en X", borrado de claves en logs |
| `XCDiagnostics` | Registro de fallos, reintentos con arreglo automático, chequeo de salud, informe exportable |
| `XCClaude` | Cliente de la API de Claude (Opus 5.5, respaldo automático) |
| `XCResearch` | Lectura del post (oEmbed), Wikipedia, búsqueda web limitada a ~60 medios fiables, descarte de URLs no verificadas |
| `XCStyle` | Importa tu archivo de X y calcula tu estilo |
| `XCLearning` | Aprende de lo que copias, editas y valoras (Beta-Bernoulli por postura y tema), control de gasto |
| `XCEngine` | Une todo: post → contexto → borradores → orden por tus preferencias |
| `XCUI` | Interfaz SwiftUI común a macOS e iOS |
| `Apps/` | App de macOS (ventana y barra de menú), app de iOS y extensión de Compartir |
| `BrowserExtension/chrome` | Botón ⓧ en cada post de x.com |
| `BrowserExtension/safari` | Lo mismo para Safari en macOS e iOS; abre la app o la versión web ([cómo instalarla](BrowserExtension/safari/README.md)) |
| `Web/` | Versión web (PWA) para el iPhone o cualquier navegador, con la misma lógica y los mismos prompts ([detalles](Web/README.md)) |

## Versión web (iPhone sin Xcode)

`Web/` es una PWA sin dependencias: pega la URL o el texto de un post y obtienes el mismo contexto y los mismos 3 borradores.
Se publica sola en GitHub Pages al fusionar en `main` (activa una vez *Settings → Pages → Source: GitHub Actions*).
En el iPhone: ábrela en Safari → Compartir → *Añadir a pantalla de inicio*. Tu clave se queda en tu navegador.

## Uso rápido

```bash
swift test                                   # pruebas
swift run xcx set-key                        # guarda tu clave en el Llavero
swift run xcx fetch https://x.com/u/status/1 # lee un post (gratis)
swift run xcx analyze https://x.com/u/status/1
swift run xcx import-archive ~/Downloads/twitter-archivo/data/tweets.js --notes "tuteo, sin emojis"
swift run xcx health
```

Apps: abre `Apps/XContexto.xcodeproj` en Xcode, elige tu equipo en *Signing & Capabilities* (o
`python3 tools/gen_xcodeproj.py --team TU_TEAM_ID`) y ejecuta `XContexto-macOS` o `XContexto-iOS`.

Extensión de Chrome: `chrome://extensions` → Modo de desarrollador → *Cargar descomprimida* → `BrowserExtension/chrome`.

## Coste

Cada análisis hace 2 llamadas (investigación con búsqueda web + borradores). La app estima el gasto, lo enseña en
*Aprendizaje* y se para al llegar al límite (100 USD por defecto). La cifra real está en console.anthropic.com → Usage.

## Pruebas

```bash
swift test          # motor Swift (en el Mac)
npm test            # web: núcleo, seguridad y paridad de prompts con Swift
npm run test:e2e    # web en un iPhone emulado y extensiones, con la API simulada (sin gasto)
```

## Pendiente o con límites

- Extensión de Safari: el código está en `BrowserExtension/safari`; falta convertirla con Xcode en el Mac (ver su README).
- Si X cambia el HTML de su web, el botón ⓧ puede dejar de aparecer (hay que ajustar los selectores de `content.js`).
- Posts protegidos o borrados: oEmbed no los devuelve; la extensión envía el texto leído en pantalla, y en iOS puedes pegarlo.
- App Groups y el Llavero compartido entre la app de iOS y su extensión necesitan firmar con tu equipo de Apple.
