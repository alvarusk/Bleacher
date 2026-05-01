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
- Borrar áreas con dedo o Apple Pencil.
- Ajustar el grosor del borrador.
- Eliminar la página actual.
- Deshacer y rehacer por trazo completo.
- Navegar entre páginas con controles explícitos.
- Ajustar zoom con control deslizante o pellizco.
- Delimitar una zona con Lazo, copiarla, arrastrarla para pegarla y moverla después.
- Exportar un PDF nuevo con las áreas borradas.

## Estrategia de archivos

Bleacher no se integra directamente con iCloud, Google Drive ni OneDrive. Usa la app Archivos de iPadOS, así cualquier proveedor compatible aparece automáticamente en el selector del sistema.

## Documentación

- [Arquitectura inicial](docs/architecture.md)
- [Uso básico](docs/usage.md)
- [Arranque en Xcode](docs/xcode-startup.md)
- [Roadmap](docs/roadmap.md)
