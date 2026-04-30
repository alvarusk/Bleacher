import Foundation
import PDFKit
import SwiftUI
import UIKit

enum EditingTool: String, CaseIterable, Identifiable {
    case eraser
    case lasso
    case paste

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eraser:
            return "Borrador"
        case .lasso:
            return "Lazo"
        case .paste:
            return "Pegar"
        }
    }
}

struct BleachStroke: Identifiable, Equatable {
    let id: UUID
    let pageID: UUID
    let width: CGFloat
    let points: [CGPoint]

    init(id: UUID = UUID(), pageID: UUID, width: CGFloat, points: [CGPoint]) {
        self.id = id
        self.pageID = pageID
        self.width = width
        self.points = points
    }
}

struct LassoSelection {
    let pageID: UUID
    let points: [CGPoint]

    var bounds: CGRect {
        guard let firstPoint = points.first else { return .null }

        return points.dropFirst().reduce(CGRect(origin: firstPoint, size: .zero)) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }.standardized
    }
}

struct LassoClip {
    let image: UIImage
    let size: CGSize
}

struct PastedClip: Identifiable {
    let id: UUID
    let pageID: UUID
    let image: UIImage
    let origin: CGPoint
    let size: CGSize

    init(id: UUID = UUID(), pageID: UUID, image: UIImage, origin: CGPoint, size: CGSize) {
        self.id = id
        self.pageID = pageID
        self.image = image
        self.origin = origin
        self.size = size
    }
}

enum BleacherError: LocalizedError {
    case invalidPDF
    case missingDocument

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "No se pudo abrir el PDF."
        case .missingDocument:
            return "No hay ningún PDF abierto."
        }
    }
}

private enum EditCommand {
    case addStroke(BleachStroke)
    case addPaste(PastedClip)
    case deletePage(index: Int, page: PDFPage, pageID: UUID, removedStrokes: [BleachStroke], removedPastes: [PastedClip])
}

@MainActor
final class DocumentModel: ObservableObject {
    @Published var pdfDocument: PDFDocument?
    @Published var fileName = "Sin título.pdf"
    @Published var eraserWidth: CGFloat = 36
    @Published var selectedTool: EditingTool = .eraser
    @Published var selectedPageID: UUID?
    @Published private(set) var strokes: [BleachStroke] = []
    @Published private(set) var lassoSelection: LassoSelection?
    @Published private(set) var copiedClip: LassoClip?
    @Published private(set) var pastedClips: [PastedClip] = []
    @Published private(set) var currentPageIndex = 0
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var documentRevision = 0
    @Published private(set) var navigationRevision = 0

    private var pageIDs: [ObjectIdentifier: UUID] = [:]
    private var undoStack: [EditCommand] = []
    private var redoStack: [EditCommand] = []

    var displayTitle: String {
        pdfDocument == nil ? "Bleacher" : fileName
    }

    var canDeleteSelectedPage: Bool {
        selectedPageID != nil && (pdfDocument?.pageCount ?? 0) > 0
    }

    var canCopySelection: Bool {
        lassoSelection != nil
    }

    var canPaste: Bool {
        copiedClip != nil
    }

    var canGoToPreviousPage: Bool {
        currentPageIndex > 0
    }

    var canGoToNextPage: Bool {
        currentPageIndex + 1 < pageCount
    }

    var pageCount: Int {
        pdfDocument?.pageCount ?? 0
    }

    var pageStatus: String {
        guard pageCount > 0 else { return "Sin páginas" }
        return "Página \(currentPageIndex + 1) de \(pageCount)"
    }

    var exportFileName: String {
        let baseName = (fileName as NSString).deletingPathExtension
        return "\(baseName)-bleached.pdf"
    }

    func open(url: URL) throws {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: url) else {
            throw BleacherError.invalidPDF
        }

        pdfDocument = document
        fileName = url.lastPathComponent
        selectedTool = .eraser
        strokes = []
        lassoSelection = nil
        copiedClip = nil
        pastedClips = []
        pageIDs = [:]
        undoStack = []
        redoStack = []
        currentPageIndex = 0
        documentRevision += 1
        navigationRevision += 1

        for index in 0..<document.pageCount {
            if let page = document.page(at: index) {
                _ = pageID(for: page)
            }
        }

        selectedPageID = document.page(at: 0).map { pageID(for: $0) }
        refreshHistoryAvailability()
    }

    func pageID(for page: PDFPage) -> UUID {
        let key = ObjectIdentifier(page)
        if let existingID = pageIDs[key] {
            return existingID
        }

        let id = UUID()
        pageIDs[key] = id
        return id
    }

    func page(for pageID: UUID) -> PDFPage? {
        guard let document = pdfDocument else { return nil }

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if pageIDs[ObjectIdentifier(page)] == pageID {
                return page
            }
        }

        return nil
    }

    func page(at index: Int) -> PDFPage? {
        pdfDocument?.page(at: index)
    }

    func select(page: PDFPage?) {
        guard let page else {
            selectedPageID = nil
            currentPageIndex = 0
            return
        }

        selectedPageID = pageID(for: page)

        if let document = pdfDocument {
            let index = document.index(for: page)
            if index != NSNotFound {
                currentPageIndex = index
            }
        }
    }

    func goToPreviousPage() {
        goToPage(at: currentPageIndex - 1)
    }

    func goToNextPage() {
        goToPage(at: currentPageIndex + 1)
    }

    func goToPage(at index: Int) {
        guard let document = pdfDocument, document.pageCount > 0 else { return }

        let nextIndex = min(max(index, 0), document.pageCount - 1)
        guard let page = document.page(at: nextIndex) else { return }

        currentPageIndex = nextIndex
        selectedPageID = pageID(for: page)
        navigationRevision += 1
    }

    func setLassoSelection(_ selection: LassoSelection?) {
        lassoSelection = selection
    }

    func copyCurrentSelection() {
        guard
            let selection = lassoSelection,
            let page = page(for: selection.pageID),
            let clip = renderClip(from: selection, page: page)
        else {
            return
        }

        copiedClip = clip
        selectedTool = .paste
    }

    func pasteCopiedClip(at pagePoint: CGPoint, pageID: UUID) {
        guard let copiedClip else { return }

        let origin = CGPoint(
            x: pagePoint.x - copiedClip.size.width / 2,
            y: pagePoint.y - copiedClip.size.height / 2
        )
        let paste = PastedClip(
            pageID: pageID,
            image: copiedClip.image,
            origin: origin,
            size: copiedClip.size
        )

        pastedClips.append(paste)
        lassoSelection = nil
        undoStack.append(.addPaste(paste))
        redoStack.removeAll()
        refreshHistoryAvailability()
    }

    func addStroke(_ stroke: BleachStroke) {
        guard !stroke.points.isEmpty else { return }

        strokes.append(stroke)
        undoStack.append(.addStroke(stroke))
        redoStack.removeAll()
        refreshHistoryAvailability()
    }

    func deleteSelectedPage() {
        guard
            let document = pdfDocument,
            let selectedPageID,
            let page = page(for: selectedPageID)
        else {
            return
        }

        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return }

        let removedStrokes = strokes.filter { $0.pageID == selectedPageID }
        strokes.removeAll { $0.pageID == selectedPageID }
        let removedPastes = pastedClips.filter { $0.pageID == selectedPageID }
        pastedClips.removeAll { $0.pageID == selectedPageID }
        document.removePage(at: pageIndex)

        undoStack.append(.deletePage(
            index: pageIndex,
            page: page,
            pageID: selectedPageID,
            removedStrokes: removedStrokes,
            removedPastes: removedPastes
        ))
        redoStack.removeAll()
        documentRevision += 1
        selectNearestPage(afterRemovingAt: pageIndex)
        refreshHistoryAvailability()
    }

    func undo() {
        guard let command = undoStack.popLast() else { return }

        switch command {
        case .addStroke(let stroke):
            strokes.removeAll { $0.id == stroke.id }
            redoStack.append(command)

        case .addPaste(let paste):
            pastedClips.removeAll { $0.id == paste.id }
            redoStack.append(command)

        case .deletePage(let index, let page, let pageID, let removedStrokes, let removedPastes):
            guard let document = pdfDocument else { return }

            let insertionIndex = min(index, document.pageCount)
            document.insert(page, at: insertionIndex)
            pageIDs[ObjectIdentifier(page)] = pageID
            strokes.append(contentsOf: removedStrokes)
            pastedClips.append(contentsOf: removedPastes)
            selectedPageID = pageID
            currentPageIndex = insertionIndex
            documentRevision += 1
            redoStack.append(command)
        }

        refreshHistoryAvailability()
    }

    func redo() {
        guard let command = redoStack.popLast() else { return }

        switch command {
        case .addStroke(let stroke):
            strokes.append(stroke)
            undoStack.append(command)

        case .addPaste(let paste):
            pastedClips.append(paste)
            undoStack.append(command)

        case .deletePage(_, let page, let pageID, let fallbackStrokes, let fallbackPastes):
            guard let document = pdfDocument else { return }

            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { return }

            let removedStrokes = strokes.filter { $0.pageID == pageID }
            strokes.removeAll { $0.pageID == pageID }
            let removedPastes = pastedClips.filter { $0.pageID == pageID }
            pastedClips.removeAll { $0.pageID == pageID }
            document.removePage(at: pageIndex)
            undoStack.append(.deletePage(
                index: pageIndex,
                page: page,
                pageID: pageID,
                removedStrokes: removedStrokes.isEmpty ? fallbackStrokes : removedStrokes,
                removedPastes: removedPastes.isEmpty ? fallbackPastes : removedPastes
            ))
            documentRevision += 1
            selectNearestPage(afterRemovingAt: pageIndex)
        }

        refreshHistoryAvailability()
    }

    func renderExportData() throws -> Data {
        guard let document = pdfDocument else {
            throw BleacherError.missingDocument
        }

        let output = NSMutableData()
        UIGraphicsBeginPDFContextToData(output, .zero, nil)
        defer { UIGraphicsEndPDFContext() }

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }

            let bounds = page.bounds(for: .mediaBox)
            UIGraphicsBeginPDFPageWithInfo(bounds, nil)

            guard let context = UIGraphicsGetCurrentContext() else { continue }

            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()

            let id = pageID(for: page)
            let pageStrokes = strokes.filter { $0.pageID == id }

            if !pageStrokes.isEmpty {
                context.saveGState()
                context.translateBy(x: 0, y: bounds.height)
                context.scaleBy(x: 1, y: -1)
                for stroke in pageStrokes {
                    draw(stroke: stroke, in: context)
                }
                context.restoreGState()
            }

            let pagePastes = pastedClips.filter { $0.pageID == id }
            if !pagePastes.isEmpty {
                context.saveGState()
                context.translateBy(x: 0, y: bounds.height)
                context.scaleBy(x: 1, y: -1)
                for paste in pagePastes {
                    draw(paste: paste, in: context)
                }
                context.restoreGState()
            }
        }

        return Data(referencing: output)
    }

    private func selectNearestPage(afterRemovingAt removedIndex: Int) {
        guard let document = pdfDocument, document.pageCount > 0 else {
            selectedPageID = nil
            currentPageIndex = 0
            return
        }

        let nextIndex = min(removedIndex, document.pageCount - 1)
        currentPageIndex = nextIndex
        selectedPageID = document.page(at: nextIndex).map { pageID(for: $0) }
        navigationRevision += 1
    }

    private func refreshHistoryAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func draw(stroke: BleachStroke, in context: CGContext) {
        context.setStrokeColor(UIColor.white.cgColor)
        context.setFillColor(UIColor.white.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(stroke.width)

        if stroke.points.count == 1, let point = stroke.points.first {
            let radius = stroke.width / 2
            context.fillEllipse(in: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: stroke.width,
                height: stroke.width
            ))
            return
        }

        guard let firstPoint = stroke.points.first else { return }

        context.beginPath()
        context.move(to: firstPoint)
        for point in stroke.points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private func renderClip(from selection: LassoSelection, page: PDFPage) -> LassoClip? {
        let pageBounds = page.bounds(for: .mediaBox)
        let selectionBounds = selection.bounds.intersection(pageBounds).standardized

        guard selectionBounds.width > 2, selectionBounds.height > 2 else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let pageRenderer = UIGraphicsImageRenderer(size: pageBounds.size, format: format)
        let pageImage = pageRenderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: pageBounds.size))
            context.translateBy(x: -pageBounds.minX, y: pageBounds.height + pageBounds.minY)
            context.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context)
        }

        let cropRect = CGRect(
            x: selectionBounds.minX - pageBounds.minX,
            y: pageBounds.maxY - selectionBounds.maxY,
            width: selectionBounds.width,
            height: selectionBounds.height
        ).integral

        let imageBounds = CGRect(origin: .zero, size: pageBounds.size)
        guard
            let croppedImage = pageImage.cgImage?.cropping(to: cropRect.intersection(imageBounds))
        else {
            return nil
        }

        return LassoClip(
            image: UIImage(cgImage: croppedImage, scale: 1, orientation: .up),
            size: selectionBounds.size
        )
    }

    private func draw(paste: PastedClip, in context: CGContext) {
        guard let image = paste.image.cgImage else { return }

        context.saveGState()
        context.translateBy(x: paste.origin.x, y: paste.origin.y + paste.size.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: paste.size))
        context.restoreGState()
    }
}
