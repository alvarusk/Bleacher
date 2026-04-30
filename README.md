# Bleacher

Bleacher es una app nativa para iPad pensada para borrar zonas de PDFs con una experiencia directa, similar a usar una goma sobre el documento.

## Estado inicial

- Workspace Xcode: `Bleacher.xcworkspace`
- Proyecto Xcode: `Bleacher.xcodeproj`
- Workspace VS Code: `Bleacher.code-workspace`
- Plataforma inicial: iPadOS 17+
- Frameworks: SwiftUI, PDFKit, UIKit y UniformTypeIdentifiers

## Funciones base

- Abrir PDFs con el selector de documentos de iPadOS.
- Borrar areas con dedo o Apple Pencil.
- Ajustar el grosor del borrador.
- Eliminar la pagina actual.
- Deshacer y rehacer por trazo completo.
- Exportar un PDF nuevo con las areas borradas.

## Estrategia de archivos

Bleacher no se integra directamente con iCloud, Google Drive ni OneDrive. Usa la app Archivos de iPadOS, asi cualquier proveedor compatible aparece automaticamente en el selector del sistema.

