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
- selecciones de área para copiar y pegar, cuando se implemente la herramienta de lazo

Cada trazo se agrupa desde que empieza el toque hasta que termina, así `Deshacer` revierte el trazo completo.

## Herramienta de lazo

La UI debería incluir una herramienta para delimitar una zona del PDF, similar a la función Lazo de algunas apps. Esa zona se podrá copiar y pegar en otra posición del documento.

Esta función requiere definir cómo se comportan la selección, el pegado, el historial de deshacer/rehacer y la exportación final.

## Exportación

Al guardar, la app renderiza un nuevo PDF:

- dibuja cada página original
- aplica los trazos blancos encima
- omite las páginas eliminadas

Esta primera versión funciona como "whiteout" visual. Si más adelante necesitamos redacción real para eliminar contenido sensible del PDF, habrá que añadir una fase específica que elimine o rasterice el contenido subyacente.
