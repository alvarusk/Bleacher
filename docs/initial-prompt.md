# Prompt inicial

El concepto de la app es simple:

- Abrir un PDF.
- Con el dedo o un lápiz táctil, borrar zonas del PDF, como una goma de borrar.
- Ajustar el grosor del borrador.
- Poder eliminar una página entera.
- Posibilidad de deshacer o rehacer cambios.
- Cada cambio debería ser la acción completa que va desde que toco con el dedo o el lápiz hasta que lo suelto, no cada círculo individual de borrado.
- Guardar PDF.
- Los PDF se subirán desde PC y se abrirán en la app.
- La UI debería permitir delimitar una zona, como con la función Lazo de algunas apps, copiarla y pegarla en otro sitio.

## Pregunta pendiente

Definir el mejor flujo de entrada/salida de archivos:

- iCloud Drive
- Google Drive
- OneDrive
- Compartir desde Archivos de iPadOS
- Importación/exportación local dentro de la app

## Opinión inicial

Para una primera versión de iPad, lo más robusto es integrarse con el selector de documentos de iPadOS. Así el usuario puede abrir PDFs desde iCloud Drive, Google Drive, OneDrive, almacenamiento local o cualquier proveedor compatible con Archivos, sin casarnos con una nube concreta.

Después podemos decidir si conviene añadir sincronización propia, pero no lo haría en la primera versión salvo que haya una necesidad clara.
