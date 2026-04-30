# Prompt inicial

El concepto de la app es simple:

- Abrir un PDF.
- Con el dedo o un lapiz tactil, borrar zonas del PDF, como una goma de borrar.
- Ajustar el grosor del borrador.
- Poder eliminar una pagina entera.
- Posibilidad de deshacer o rehacer cambios.
- Cada cambio deberia ser la accion completa que va desde que toco con el dedo o el lapiz hasta que lo suelto, no cada circulo individual de borrado.
- Guardar PDF.
- Los PDF se subiran desde PC y se abriran en la app.

## Pregunta pendiente

Definir el mejor flujo de entrada/salida de archivos:

- iCloud Drive
- Google Drive
- OneDrive
- Compartir desde Archivos de iPadOS
- Importacion/exportacion local dentro de la app

## Opinion inicial

Para una primera version de iPad, lo mas robusto es integrarse con el selector de documentos de iPadOS. Asi el usuario puede abrir PDFs desde iCloud Drive, Google Drive, OneDrive, almacenamiento local o cualquier proveedor compatible con Archivos, sin casarnos con una nube concreta.

Despues podemos decidir si conviene anadir sincronizacion propia, pero no lo haria en la primera version salvo que haya una necesidad clara.

