import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = DocumentModel()
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument = PDFExportDocument(data: Data())
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if model.pdfDocument == nil {
                    emptyState
                } else {
                    PDFEditorView(model: model)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(model.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        isImporting = true
                    } label: {
                        Label("Abrir PDF", systemImage: "doc.badge.plus")
                    }
                }

                if model.pdfDocument != nil {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            model.undo()
                        } label: {
                            Label("Deshacer", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!model.canUndo)

                        Button {
                            model.redo()
                        } label: {
                            Label("Rehacer", systemImage: "arrow.uturn.forward")
                        }
                        .disabled(!model.canRedo)

                        Button(role: .destructive) {
                            model.deleteSelectedPage()
                        } label: {
                            Label("Borrar pagina", systemImage: "trash")
                        }
                        .disabled(!model.canDeleteSelectedPage)

                        Button {
                            exportPDF()
                        } label: {
                            Label("Guardar PDF", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.pdfDocument != nil {
                    eraserControls
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                importPDF(result)
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .pdf,
                defaultFilename: model.exportFileName
            ) { result in
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
            }
            .alert("Bleacher", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.secondary)

            Button {
                isImporting = true
            } label: {
                Label("Abrir PDF", systemImage: "folder")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var eraserControls: some View {
        HStack(spacing: 14) {
            Label("Grosor", systemImage: "eraser")
                .labelStyle(.iconOnly)
                .font(.title3)

            Slider(value: $model.eraserWidth, in: 8...96, step: 1)
                .frame(maxWidth: 420)

            Text("\(Int(model.eraserWidth))")
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func importPDF(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try model.open(url: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func exportPDF() {
        do {
            exportDocument = PDFExportDocument(data: try model.renderExportData())
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}

