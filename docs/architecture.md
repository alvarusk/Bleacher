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
- orden cronológico de capas entre borrados y recortes pegados

Cada trazo se agrupa desde que empieza el toque hasta que termina, así `Deshacer` revierte el trazo completo.

## Herramienta de lazo

La UI incluye una herramienta para delimitar una zona del PDF, similar a la función Lazo de algunas apps. Esa zona se puede copiar y pegar en otra posición del documento.

La primera versión del Lazo usa el rectángulo envolvente de la selección como contenido copiado. El pegado se hace con una previsualización semitransparente que sigue al dedo o al lápiz hasta que se levanta el toque.

Los recortes ya pegados pueden volver a moverse desde el modo `Pegar`.

Borrados y recortes pegados se renderizan por orden cronológico. Eso permite borrar una zona pegada después con el borrador y mantener el resultado al levantar el dedo y al exportar.

Queda pendiente afinar cómo se comportan la selección libre, el redimensionado de recortes y la exportación final en casos complejos.

## Zoom

El visor usa un factor de zoom relativo al ajuste elegido. `100%` equivale a encajar la página según el modo activo.

La UI ofrece:

- control deslizante de zoom
- ajuste horizontal por ancho
- ajuste vertical por alto
- pellizco con dos dedos
- desplazamiento con dos dedos cuando la página está ampliada
- herramienta `Mano` para desplazar la vista con un dedo
- barra lateral propia para indicar y arrastrar la posición vertical

## Navegación

La barra inferior mantiene botones `Anterior` y `Siguiente`, pero el número de página actual también es editable. Al escribir un número, el modelo limita el salto al rango válido del documento.

## Exportación

Al guardar, la app renderiza un nuevo PDF:

- dibuja cada página original
- aplica borrados y recortes pegados por orden cronológico de capas
- omite las páginas eliminadas

Esta primera versión funciona como "whiteout" visual. Si más adelante necesitamos redacción real para eliminar contenido sensible del PDF, habrá que añadir una fase específica que elimine o rasterice el contenido subyacente.
