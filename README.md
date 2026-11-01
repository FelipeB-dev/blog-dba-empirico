# Diario de un DBA empírico

Blog personal sobre lo que 11 años dando soporte N2/N3 y desarrollando en PL/SQL para una operación de facturación 7x24 me enseñaron de Oracle.

Es la **Actividad 1 de Desarrollo de Aplicaciones en Red** (Ingeniería Informática, UNIR): un sitio hecho desde cero con HTML5 y CSS3, sin frameworks.

- **Sitio publicado:** https://blog-dba-empirico.vercel.app
- **Autor:** Luis Felipe Baquero

## Qué tiene

- Una página de inicio con el listado de entradas en fichas, una página "Sobre mí" y tres entradas:
  1. *El cursor que tumbó un batch a las 3 a.m.*: cursores explícitos frente a BULK COLLECT y FORALL.
  2. *Índices: cuando "más" es peor*: índices B-tree, planes de ejecución y cuándo no indexar.
  3. *Errores de PL/SQL que todos cometemos (y yo también)*: excepciones, WHEN OTHERS y logging con transacciones autónomas.
- Cada entrada tiene texto, código SQL resaltado, un diagrama SVG propio, pantallazos reales de Oracle y un video de YouTube embebido con su crédito.
- Navegación: menú en todas las páginas, enlaces de entrada anterior y siguiente, y volver al inicio.
- Modo noche, diseño responsive (móvil primero) y una página 404 propia.

## Estructura de carpetas

```
/
├── index.html            Inicio: presentación y fichas de las entradas
├── about.html            Sobre mí
├── 404.html              Página de error (Vercel la sirve sola)
├── posts/
│   ├── cursor-batch-3am.html
│   ├── indices-mas-es-peor.html
│   └── errores-plsql.html
├── css/styles.css        Todos los estilos, comentados por secciones
├── js/main.js            Modo noche y componente <sitio-pie> (footer)
├── img/                  Diagramas SVG propios, pantallazos, foto y favicon
├── sql/                  Scripts para reproducir las demos de cada entrada
└── README.md
```

## Decisiones de diseño

- **Que no parezca una plantilla.** La idea visual es un cuaderno de ingeniero: fondo de papel cálido, tinta oscura y un solo color de acento (rojo de lápiz de corrección). Sin degradados, sin sombras difusas y sin íconos decorativos.
- **Tipografía.** *Source Serif 4* para el texto, porque las entradas son largas, e *IBM Plex Mono* para el código y los datos (fechas, etiquetas, números de entrada), como si fueran líneas de un log. Las dos vienen de Google Fonts.
- **Colores en variables CSS** (`:root`). El modo oscuro solo redefine esas variables, ya sea por la preferencia del sistema o por el botón "modo noche", que guarda la elección en `localStorage`.
- **Móvil primero.** Los estilos base son para pantallas pequeñas y desde 768 px y 1090 px se agregan columnas. En pantallas grandes, las notas al margen se van a una columna lateral.
- **Resaltado de código hecho a mano** con `<span class="kw|str|com|num|fn">`. No depende de librerías externas, funciona sin internet y pasa el validador.
- **El footer como componente.** HTML no tiene "include", así que el pie de página se define una sola vez en `js/main.js` como Custom Element (`<sitio-pie>`). No usé `fetch()` de un archivo aparte porque el navegador lo bloquea al abrir las páginas con doble clic (`file://`).
- **Rutas relativas** en todo el sitio, para que funcione igual abriendo `index.html` desde el disco que publicado en Vercel.
- **Accesibilidad.** HTML semántico (`header`, `nav`, `main`, `article`, `aside`, `footer`), `alt` en todas las imágenes, enlace "saltar al contenido" y foco visible con teclado.
- **Videos** embebidos desde `youtube-nocookie.com`, dentro de una caja que mantiene la proporción 16:9.

## Las demos SQL (`/sql`)

Todos los datos son ficticios: tablas `CLIENTES`, `FACTURAS` y `CONSUMOS` con nombres como "Cliente 00001". No hay nada real de ningún cliente.

| Script | Para qué |
|---|---|
| `setup_demo.sql` | Crea el esquema y genera 5.000 clientes y 50.000 consumos. Ejecutarlo primero. |
| `demo_cursor.sql` | La misma carga fila a fila y con BULK COLLECT + FORALL, midiendo tiempos (entrada 1). |
| `demo_indices.sql` | `EXPLAIN PLAN` sin índice y con índice, con `DBMS_XPLAN.DISPLAY` (entrada 2). |
| `demo_errores.sql` | Tabla `LOG_ERRORES`, logging con `PRAGMA AUTONOMOUS_TRANSACTION` y un proceso que falla a propósito (entrada 3). |

> **Nota:** los pantallazos de las entradas salen de correr estos scripts en **Oracle FreeSQL** (freesql.com) con el esquema de 50.000 consumos. Mis resultados fueron: fila a fila 0,79 s contra 0,05 s por lotes, y un costo de plan de 102 sin índice contra 11 con índice. En otra máquina los números cambian, pero la diferencia se mantiene.

## Cómo verlo en local

No necesita instalar nada ni compilar. Basta con abrir `index.html` en el navegador (doble clic).

Lo único que no funciona desde `file://` son los videos de YouTube, que muestran un error de configuración. Para verlos en local hay que servir la carpeta con cualquier servidor estático, por ejemplo:

```bash
python3 -m http.server 8000
# y abrir http://localhost:8000
```

## Cómo desplegarlo en Vercel

Es un sitio estático: no tiene build ni dependencias, y no necesita `vercel.json`.

**Desde la terminal:**

```bash
npx vercel deploy --prod
```

**Desde GitHub:** en vercel.com → *Add New → Project* → importar el repositorio → *Framework Preset*: **Other**, con *Build Command* y *Output Directory* vacíos → *Deploy*.

El archivo `.vercelignore` evita que se publiquen archivos que no son del sitio (los originales de la foto y de los pantallazos, la configuración local).

## Créditos

- Videos: Steven Feuerstein (*Practically Perfect PL/SQL*) y Chris Saxon (*The Magic of SQL*), en YouTube.
- Tipografías: Source Serif 4 e IBM Plex Mono, de Google Fonts.
- Diagramas, textos, código y fotos: propios.
