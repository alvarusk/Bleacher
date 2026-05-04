import Foundation
import PDFKit
import SwiftUI
import UIKit

enum EditingTool: String, CaseIterable, Identifiable {
    case pan
    case eraser
    case lasso
    case paste

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pan:
            return "Hand"
        case .eraser:
            return "Eraser"
        case .lasso:
            return "Lasso"
        case .paste:
            return "Paste"
        }
    }

    var systemImage: String {
        switch self {
        case .pan:
            return "hand.raised"
        case .eraser:
            return "eraser"
        case .lasso:
            return "lasso"
        case .paste:
            return "doc.on.doc"
        }
    }
}

enum ZoomFitMode: String, CaseIterable, Identifiable {
    case width
    case height

    var id: String { rawValue }

    var title: String {
        switch self {
        case .width:
            return "Width"
        case .height:
            return "Height"
        }
    }
}

struct BleachStroke: Identifiable, Equatable {
    let id: UUID
    let pageID: UUID
    var layerIndex: Int
    let width: CGFloat
    let points: [CGPoint]

    init(id: UUID = UUID(), pageID: UUID, layerIndex: Int = 0, width: CGFloat, points: [CGPoint]) {
        self.id = id
        self.pageID = pageID
        self.layerIndex = layerIndex
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
    var layerIndex: Int
    let image: UIImage
    var origin: CGPoint
    let size: CGSize

    init(id: UUID = UUID(), pageID: UUID, layerIndex: Int = 0, image: UIImage, origin: CGPoint, size: CGSize) {
        self.id = id
        self.pageID = pageID
        self.layerIndex = layerIndex
        self.image = image
        self.origin = origin
        self.size = size
    }
}

enum PageEditLayer {
    case stroke(BleachStroke)
    case paste(PastedClip)

    var layerIndex: Int {
        switch self {
        case .stroke(let stroke):
            return stroke.layerIndex
        case .paste(let paste):
            return paste.layerIndex
        }
    }
}

enum BleacherError: LocalizedError {
    case invalidPDF
    case missingDocument

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "Could not open the PDF."
        case .missingDocument:
            return "No PDF is currently open."
        }
    }
}

private enum EditCommand {
    case addStroke(BleachStroke)
    case addPaste(PastedClip)
    case movePaste(id: UUID, from: CGPoint, to: CGPoint)
    case deletePage(index: Int, page: PDFPage, pageID: UUID, removedStrokes: [BleachStroke], removedPastes: [PastedClip])
}

@MainActor
final class DocumentModel: ObservableObject {
    let minZoomScale: CGFloat = 0.5
    let maxZoomScale: CGFloat = 4

    @Published var pdfDocument: PDFDocument?
    @Published var fileName = "Untitled.pdf"
    @Published var eraserWidth: CGFloat = 36
    @Published var selectedTool: EditingTool = .eraser
    @Published private(set) var zoomScale: CGFloat = 1
    @Published private(set) var zoomFitMode: ZoomFitMode = .width
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
    private var nextLayerIndex = 1

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
        guard pageCount > 0 else { return "No pages" }
        return "Page \(currentPageIndex + 1) of \(pageCount)"
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
        zoomScale = 1
        zoomFitMode = .width
        pageIDs = [:]
        undoStack = []
        redoStack = []
        nextLayerIndex = 1
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

    func setZoomScale(_ scale: CGFloat) {
        zoomScale = min(max(scale, minZoomScale), maxZoomScale)
    }

    func resetZoom() {
        zoomScale = 1
    }

    func fitZoom(_ mode: ZoomFitMode) {
        zoomFitMode = mode
        zoomScale = 1
    }

    func pastePreview(at pagePoint: CGPoint, pageID: UUID) -> PastedClip? {
        guard let copiedClip else { return nil }

        let origin = CGPoint(
            x: pagePoint.x - copiedClip.size.width / 2,
            y: pagePoint.y - copiedClip.size.height / 2
        )

        return PastedClip(
            pageID: pageID,
            image: copiedClip.image,
            origin: origin,
            size: copiedClip.size
        )
    }

    func addPastedClip(_ paste: PastedClip) {
        var orderedPaste = paste
        orderedPaste.layerIndex = nextLayerIndex
        nextLayerIndex += 1

        pastedClips.append(orderedPaste)
        lassoSelection = nil
        undoStack.append(.addPaste(orderedPaste))
        redoStack.removeAll()
        refreshHistoryAvailability()
    }

    func pastedClip(at pagePoint: CGPoint, pageID: UUID) -> PastedClip? {
        pastedClips
            .filter { $0.pageID == pageID }
            .sorted { $0.layerIndex > $1.layerIndex }
            .first { paste in
                CGRect(origin: paste.origin, size: paste.size).contains(pagePoint)
            }
    }

    func movePastedClip(id: UUID, to origin: CGPoint) {
        guard
            let index = pastedClips.firstIndex(where: { $0.id == id }),
            pastedClips[index].origin.distance(to: origin) > 0.5
        else {
            return
        }

        let oldOrigin = pastedClips[index].origin
        setPastedClipOrigin(id: id, origin: origin)
        undoStack.append(.movePaste(id: id, from: oldOrigin, to: origin))
        redoStack.removeAll()
        refreshHistoryAvailability()
    }

    func layers(for pageID: UUID) -> [PageEditLayer] {
        let pageStrokes = strokes
            .filter { $0.pageID == pageID }
            .map(PageEditLayer.stroke)
        let pagePastes = pastedClips
            .filter { $0.pageID == pageID }
            .map(PageEditLayer.paste)

        return (pageStrokes + pagePastes).sorted { lhs, rhs in
            lhs.layerIndex < rhs.layerIndex
        }
    }

    func addStroke(_ stroke: BleachStroke) {
        guard !stroke.points.isEmpty else { return }

        var orderedStroke = stroke
        orderedStroke.layerIndex = nextLayerIndex
        nextLayerIndex += 1

        strokes.append(orderedStroke)
        undoStack.append(.addStroke(orderedStroke))
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
        if lassoSelection?.pageID == selectedPageID {
            lassoSelection = nil
        }
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

        case .movePaste(let id, let oldOrigin, _):
            setPastedClipOrigin(id: id, origin: oldOrigin)
            redoStack.append(command)

        case .deletePage(let index, let page, let pageID, let removedStrokes, let removedPastes):
            guard let document = pdfDocument else { return }

            let insertionIndex = min(index, document.pageCount)
            document.insert(page, at: insertionIndex)
            pageIDs[ObjectIdentifier(page)] = pageID
            strokes.append(contentsOf: removedStrokes)
            pastedClips.append(contentsOf: removedPastes)
            bumpNextLayerIndex(after: removedStrokes)
            bumpNextLayerIndex(after: removedPastes)
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
            bumpNextLayerIndex(after: stroke)
            undoStack.append(command)

        case .addPaste(let paste):
            pastedClips.append(paste)
            bumpNextLayerIndex(after: paste)
            undoStack.append(command)

        case .movePaste(let id, _, let newOrigin):
            setPastedClipOrigin(id: id, origin: newOrigin)
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
            let pageLayers = layers(for: id)

            if !pageLayers.isEmpty {
                context.saveGState()
                context.translateBy(x: 0, y: bounds.height)
                context.scaleBy(x: 1, y: -1)
                for layer in pageLayers {
                    switch layer {
                    case .stroke(let stroke):
                        draw(stroke: stroke, in: context)
                    case .paste(let paste):
                        draw(paste: paste, in: context)
                    }
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

    private func setPastedClipOrigin(id: UUID, origin: CGPoint) {
        guard let index = pastedClips.firstIndex(where: { $0.id == id }) else { return }

        var movedPaste = pastedClips[index]
        movedPaste.origin = origin
        pastedClips[index] = movedPaste
    }

    private func bumpNextLayerIndex(after stroke: BleachStroke) {
        nextLayerIndex = max(nextLayerIndex, stroke.layerIndex + 1)
    }

    private func bumpNextLayerIndex(after paste: PastedClip) {
        nextLayerIndex = max(nextLayerIndex, paste.layerIndex + 1)
    }

    private func bumpNextLayerIndex(after strokes: [BleachStroke]) {
        for stroke in strokes {
            bumpNextLayerIndex(after: stroke)
        }
    }

    private func bumpNextLayerIndex(after pastes: [PastedClip]) {
        for paste in pastes {
            bumpNextLayerIndex(after: paste)
        }
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

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let deltaX = x - other.x
        let deltaY = y - other.y
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }
}
