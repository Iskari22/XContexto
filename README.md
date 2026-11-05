# XContexto web (PWA)

La misma lógica que las apps de Apple, en una página que funciona en Safari del iPhone, en el Mac o en cualquier navegador.

1. Pega la **URL** de un post de X (o su **texto**) y pulsa **Analizar**.
2. XContexto busca contexto en Wikipedia y en ~60 fuentes reputadas, comprueba las afirmaciones del post y escribe
   **3 borradores** (neutro, a favor, crítico) con tu estilo.
3. Revisa, edita y pulsa **Copiar** o **Abrir en X**. Publicar lo haces tú, dentro de X.

## Instalar en el iPhone

1. Abre la web en Safari (p. ej. `https://iskari22.github.io/XContexto/` cuando esté publicada).
2. Compartir → **Añadir a pantalla de inicio**. Se abre como una app, a pantalla completa.
3. Ajustes → pega tu clave de la API (console.anthropic.com → API Keys).
4. Opcional: Ajustes → *Desde X* → copia el **marcador** y guárdalo en Safari. Abierto sobre un post de x.com,
   te trae aquí ese post con su texto.

## Seguridad y privacidad

- **Tu clave** se guarda solo en este navegador (`localStorage`, o solo en la pestaña si desmarcas «Recordarla») y viaja
  directa a `api.anthropic.com`. No hay servidor intermedio.
- **No puede publicar**: la política de seguridad (CSP) de la página solo permite conectar con `api.anthropic.com` y con
  Wikipedia. La única salida hacia X es abrir `x.com/intent/post` con el texto, y ahí eres tú quien pulsa Publicar.
- **Leer un post por su URL** usa oEmbed de X dentro de un iframe aislado (`sandbox`, sin acceso a la clave ni a la página).
  Si el post es privado o X no responde, pega su texto.
- El estilo, lo aprendido, el historial y el gasto se guardan solo en este navegador. Ajustes → Datos para exportarlos o borrarlos.

## Coste

Igual que la app: 2 llamadas por análisis (investigación con hasta 5 búsquedas web + borradores) con Claude Opus 5.5.
Ves el gasto estimado de cada análisis y un acumulado con límite (100 USD por defecto). «Rehacer borradores» no repite
la investigación.

## Desarrollo

Sin dependencias ni compilación: HTML, CSS y módulos de JavaScript.

```bash
npm run serve        # http://localhost:8080
npm test             # 47 pruebas: núcleo, seguridad y paridad con el motor Swift
npm run test:e2e     # iPhone emulado con API simulada (necesita Playwright)
```

| Fichero | Qué hace |
|---|---|
| `js/prompts.js` | Prompts de investigación y borradores (idénticos a los de Swift; la prueba de paridad lo exige) |
| `js/core.js` | Lógica pura: posts, fuentes, llamadas a la API, verificación de URLs, estilo, aprendizaje, coste |
| `js/net.js` | Wikipedia y oEmbed en el navegador |
| `js/app.js` | Interfaz |
| `oembed.html` | iframe aislado que lee posts públicos de X |
| `sw.js` | Funciona sin conexión (nunca guarda llamadas a la API) |

Si cambias un prompt, cámbialo en `js/prompts.js` **y** en `Sources/XCResearch/ResearchService.swift` /
`Sources/XCEngine/DraftWriter.swift`.
