# Arquitectura inicial

## Decisión principal

La primera versión usa el selector de documentos de iPadOS. Esto evita implementar sincronización propia y permite abrir PDFs desde:

- iCloud Drive
- Google Drive
- OneDrive
- almacenamiento local del iPad
- cualquier proveedor compatible con la app Archivos

## Modelo de edición

Bleacher no modifica el PDF original al abrirlo. Mantiene una lista de acciones en memoria:

- trazos de borrado
- páginas eliminadas
- selecciones de área para copiar y pegar con la herramienta Lazo
- recortes pegados, con posición editable

Cada trazo se agrupa desde que empieza el toque hasta que termina, así `Deshacer` revierte el trazo completo.

## Herramienta de lazo

La UI incluye una herramienta para delimitar una zona del PDF, similar a la función Lazo de algunas apps. Esa zona se puede copiar y pegar en otra posición del documento.

La primera versión del Lazo usa el rectángulo envolvente de la selección como contenido copiado. El pegado se hace con una previsualización semitransparente que sigue al dedo o al lápiz hasta que se levanta el toque.

Los recortes ya pegados pueden volver a moverse desde el modo `Pegar`.

Queda pendiente afinar cómo se comportan la selección libre, el orden exacto de capas entre borrados y pegados, y la exportación final en casos complejos.

## Zoom

El visor usa un factor de zoom relativo al ajuste de página. `100%` equivale a encajar la página en el visor.

La UI ofrece:

- control deslizante de zoom
- botón para volver al ajuste de página
- pellizco con dos dedos
- desplazamiento con dos dedos cuando la página está ampliada

## Exportación

Al guardar, la app renderiza un nuevo PDF:

- dibuja cada página original
- aplica los trazos blancos encima
- omite las páginas eliminadas
- dibuja los recortes pegados con la herramienta Lazo

Esta primera versión funciona como "whiteout" visual. Si más adelante necesitamos redacción real para eliminar contenido sensible del PDF, habrá que añadir una fase específica que elimine o rasterice el contenido subyacente.
