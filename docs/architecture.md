# Arquitectura inicial

## Decision principal

La primera version usa el selector de documentos de iPadOS. Esto evita implementar sincronizacion propia y permite abrir PDFs desde:

- iCloud Drive
- Google Drive
- OneDrive
- almacenamiento local del iPad
- cualquier proveedor compatible con la app Archivos

## Modelo de edicion

Bleacher no modifica el PDF original al abrirlo. Mantiene una lista de acciones en memoria:

- trazos de borrado
- paginas eliminadas

Cada trazo se agrupa desde que empieza el toque hasta que termina, asi `Deshacer` revierte el trazo completo.

## Exportacion

Al guardar, la app renderiza un nuevo PDF:

- dibuja cada pagina original
- aplica los trazos blancos encima
- omite las paginas eliminadas

Esta primera version funciona como "whiteout" visual. Si mas adelante necesitamos redaccion real para eliminar contenido sensible del PDF, habra que anadir una fase especifica que elimine o rasterice el contenido subyacente.

