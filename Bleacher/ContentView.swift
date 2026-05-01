import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = DocumentModel()
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument = PDFExportDocument(data: Data())
    @State private var errorMessage: String?
    @State private var pageInput = ""
    @FocusState private var pageInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                if model.pdfDocument == nil {
                    emptyState
                } else {
                    PDFEditorView(model: model)
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
                            Label("Borrar página", systemImage: "trash")
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
                    editorControls
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
            .onChange(of: model.currentPageIndex) { _, _ in
                syncPageInput()
            }
            .onChange(of: model.pageCount) { _, _ in
                syncPageInput()
            }
            .onChange(of: pageInputFocused) { _, isFocused in
                if isFocused {
                    pageInput = "\(model.currentPageIndex + 1)"
                } else {
                    commitPageInput()
                }
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

    private var editorControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    model.goToPreviousPage()
                } label: {
                    Label("Anterior", systemImage: "chevron.left")
                }
                .disabled(!model.canGoToPreviousPage)

                HStack(spacing: 6) {
                    TextField("Página", text: $pageInput)
                        .keyboardType(.numberPad)
                        .submitLabel(.go)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .monospacedDigit()
                        .frame(width: 64)
                        .focused($pageInputFocused)
                        .onSubmit(commitPageInput)

                    Button {
                        pageInputFocused = false
                        commitPageInput()
                    } label: {
                        Label("Ir a página", systemImage: "arrow.right.to.line")
                            .labelStyle(.iconOnly)
                    }

                    Text("de \(model.pageCount)")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 158)
                .onAppear(perform: syncPageInput)

                Button {
                    model.goToNextPage()
                } label: {
                    Label("Siguiente", systemImage: "chevron.right")
                }
                .disabled(!model.canGoToNextPage)

                Spacer(minLength: 12)

                Button {
                    exportPDF()
                } label: {
                    Label("Exportar PDF", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 14) {
                Picker("Herramienta", selection: $model.selectedTool) {
                    ForEach(EditingTool.allCases) { tool in
                        Label(tool.title, systemImage: tool.systemImage).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                toolSpecificControls
            }

            HStack(spacing: 14) {
                Label("Zoom", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
                    .font(.title3)

                Slider(value: zoomBinding, in: model.minZoomScale...model.maxZoomScale, step: 0.05)
                    .frame(maxWidth: 420)

                Text("\(Int(model.zoomScale * 100))%")
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)

                Menu {
                    Button {
                        model.fitZoom(.width)
                    } label: {
                        Label("Ajustar ancho", systemImage: "arrow.left.and.right")
                    }

                    Button {
                        model.fitZoom(.height)
                    } label: {
                        Label("Ajustar alto", systemImage: "arrow.up.and.down")
                    }
                } label: {
                    Label("Ajustar \(model.zoomFitMode.title.lowercased())", systemImage: "arrow.up.left.and.down.right")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var zoomBinding: Binding<CGFloat> {
        Binding(
            get: { model.zoomScale },
            set: { model.setZoomScale($0) }
        )
    }

    @ViewBuilder
    private var toolSpecificControls: some View {
        switch model.selectedTool {
        case .pan:
            Label("Arrastra con un dedo para mover la vista", systemImage: "hand.raised")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

        case .eraser:
            Label("Grosor", systemImage: "eraser")
                .labelStyle(.iconOnly)
                .font(.title3)

            Slider(value: $model.eraserWidth, in: 8...96, step: 1)
                .frame(maxWidth: 360)

            Text("\(Int(model.eraserWidth))")
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)

        case .lasso:
            Button {
                model.copyCurrentSelection()
            } label: {
                Label("Copiar selección", systemImage: "doc.on.doc")
            }
            .disabled(!model.canCopySelection)

            Spacer(minLength: 0)

        case .paste:
            Label("Toca y arrastra para colocar", systemImage: "hand.tap")
                .font(.callout)
                .foregroundStyle(model.canPaste ? .primary : .secondary)

            Spacer(minLength: 0)
        }
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
                syncPageInput()
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

    private func syncPageInput() {
        guard !pageInputFocused else { return }

        pageInput = model.pageCount > 0 ? "\(model.currentPageIndex + 1)" : ""
    }

    private func commitPageInput() {
        guard model.pageCount > 0 else {
            pageInput = ""
            return
        }

        let trimmedInput = pageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let requestedPage = Int(trimmedInput) else {
            syncPageInputAfterCommit()
            return
        }

        model.goToPage(at: requestedPage - 1)
        syncPageInputAfterCommit()
    }

    private func syncPageInputAfterCommit() {
        pageInput = "\(model.currentPageIndex + 1)"
    }
}

#Preview {
    ContentView()
}
