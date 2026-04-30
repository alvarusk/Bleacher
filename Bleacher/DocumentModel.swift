import Foundation
import PDFKit
import SwiftUI
import UIKit

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

enum BleacherError: LocalizedError {
    case invalidPDF
    case missingDocument

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "No se pudo abrir el PDF."
        case .missingDocument:
            return "No hay ningun PDF abierto."
        }
    }
}

private enum EditCommand {
    case addStroke(BleachStroke)
    case deletePage(index: Int, page: PDFPage, pageID: UUID, removedStrokes: [BleachStroke])
}

@MainActor
final class DocumentModel: ObservableObject {
    @Published var pdfDocument: PDFDocument?
    @Published var fileName = "Sin titulo.pdf"
    @Published var eraserWidth: CGFloat = 36
    @Published var selectedPageID: UUID?
    @Published private(set) var strokes: [BleachStroke] = []
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var documentRevision = 0

    private var pageIDs: [ObjectIdentifier: UUID] = [:]
    private var undoStack: [EditCommand] = []
    private var redoStack: [EditCommand] = []

    var displayTitle: String {
        pdfDocument == nil ? "Bleacher" : fileName
    }

    var canDeleteSelectedPage: Bool {
        selectedPageID != nil && (pdfDocument?.pageCount ?? 0) > 0
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
        strokes = []
        pageIDs = [:]
        undoStack = []
        redoStack = []
        documentRevision += 1

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

    func select(page: PDFPage?) {
        selectedPageID = page.map { pageID(for: $0) }
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
        document.removePage(at: pageIndex)

        undoStack.append(.deletePage(
            index: pageIndex,
            page: page,
            pageID: selectedPageID,
            removedStrokes: removedStrokes
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

        case .deletePage(let index, let page, let pageID, let removedStrokes):
            guard let document = pdfDocument else { return }

            let insertionIndex = min(index, document.pageCount)
            document.insert(page, at: insertionIndex)
            pageIDs[ObjectIdentifier(page)] = pageID
            strokes.append(contentsOf: removedStrokes)
            selectedPageID = pageID
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

        case .deletePage(_, let page, let pageID, let fallbackStrokes):
            guard let document = pdfDocument else { return }

            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { return }

            let removedStrokes = strokes.filter { $0.pageID == pageID }
            strokes.removeAll { $0.pageID == pageID }
            document.removePage(at: pageIndex)
            undoStack.append(.deletePage(
                index: pageIndex,
                page: page,
                pageID: pageID,
                removedStrokes: removedStrokes.isEmpty ? fallbackStrokes : removedStrokes
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
            guard !pageStrokes.isEmpty else { continue }

            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            for stroke in pageStrokes {
                draw(stroke: stroke, in: context)
            }
            context.restoreGState()
        }

        return Data(referencing: output)
    }

    private func selectNearestPage(afterRemovingAt removedIndex: Int) {
        guard let document = pdfDocument, document.pageCount > 0 else {
            selectedPageID = nil
            return
        }

        let nextIndex = min(removedIndex, document.pageCount - 1)
        selectedPageID = document.page(at: nextIndex).map { pageID(for: $0) }
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
}
