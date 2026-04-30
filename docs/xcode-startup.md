# Arranque en Xcode

Cuando el Mac este disponible:

1. Clonar el repo:

   ```bash
   git clone https://github.com/alvarusk/bleacher.git
   cd bleacher
   open Bleacher.xcworkspace
   ```

2. Seleccionar el target `Bleacher`.
3. Abrir `Signing & Capabilities`.
4. Elegir tu `Team`.
5. Compilar primero en un iPad Simulator.
6. Despues probar en iPad fisico.

## Build por terminal

Para comprobar una build de simulador sin firma:

```bash
xcodebuild \
  -workspace Bleacher.xcworkspace \
  -scheme Bleacher \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Primeras pruebas manuales

- Abrir un PDF desde Archivos.
- Dibujar un trazo corto.
- Comprobar que `Deshacer` elimina el trazo completo.
- Comprobar que `Rehacer` lo restaura.
- Cambiar el grosor y dibujar otro trazo.
- Borrar una pagina.
- Exportar el PDF.
- Abrir el PDF exportado y comprobar que las zonas aparecen borradas.

