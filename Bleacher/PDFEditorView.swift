import PDFKit
import SwiftUI
import UIKit

struct PDFEditorView: UIViewRepresentable {
    @ObservedObject var model: DocumentModel

    func makeUIView(context: Context) -> PDFEditorHostView {
        PDFEditorHostView()
    }

    func updateUIView(_ uiView: PDFEditorHostView, context: Context) {
        uiView.configure(model: model)
    }
}

final class PDFEditorHostView: UIView {
    private let pdfView = PDFView()
    private let overlayView = BleachOverlayView()
    private weak var model: DocumentModel?
    private var observedDocumentRevision: Int?
    private var observedNavigationRevision: Int?
    private var pageChangeObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        observePageChanges()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
        observePageChanges()
    }

    deinit {
        if let pageChangeObserver {
            NotificationCenter.default.removeObserver(pageChangeObserver)
        }
    }

    func configure(model: DocumentModel) {
        self.model = model
        overlayView.model = model
        overlayView.pdfView = pdfView

        if observedDocumentRevision != model.documentRevision || pdfView.document !== model.pdfDocument {
            pdfView.document = model.pdfDocument
            pdfView.autoScales = true
            observedDocumentRevision = model.documentRevision
            observedNavigationRevision = nil
        }

        if observedNavigationRevision != model.navigationRevision {
            goToCurrentPage(model: model)
            observedNavigationRevision = model.navigationRevision
        }

        overlayView.setNeedsDisplay()
    }

    private func setupViews() {
        backgroundColor = .systemGroupedBackground

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemGroupedBackground

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = .clear

        addSubview(pdfView)
        addSubview(overlayView)

        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),

            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func observePageChanges() {
        pageChangeObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { [weak self] _ in
            self?.syncCurrentPage()
        }
    }

    private func goToCurrentPage(model: DocumentModel) {
        guard let page = model.page(at: model.currentPageIndex) else {
            syncCurrentPage()
            return
        }

        pdfView.go(to: page)
        model.select(page: page)
    }

    private func syncCurrentPage() {
        model?.select(page: pdfView.currentPage)
    }
}

final class BleachOverlayView: UIView {
    weak var pdfView: PDFView?
    weak var model: DocumentModel?

    private var strokeDraft: StrokeDraft?
    private var lassoDraft: LassoDraft?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard
            let touch = touches.first,
            let model,
            let touchInfo = touchInfo(for: touch)
        else {
            return
        }

        model.select(page: touchInfo.page)

        switch model.selectedTool {
        case .eraser:
            let widthOnPage = max(1, model.eraserWidth / max(touchInfo.pdfView.scaleFactor, 0.01))
            strokeDraft = StrokeDraft(
                page: touchInfo.page,
                pageID: touchInfo.pageID,
                width: widthOnPage,
                points: [touchInfo.pointOnPage]
            )

        case .lasso:
            lassoDraft = LassoDraft(
                page: touchInfo.page,
                pageID: touchInfo.pageID,
                points: [touchInfo.pointOnPage]
            )

        case .paste:
            model.pasteCopiedClip(at: touchInfo.pointOnPage, pageID: touchInfo.pageID)
        }

        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

        if strokeDraft != nil {
            appendStroke(touch: touch)
        } else if lassoDraft != nil {
            appendLasso(touch: touch)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            if strokeDraft != nil {
                appendStroke(touch: touch)
            } else if lassoDraft != nil {
                appendLasso(touch: touch)
            }
        }

        finishStroke(cancelled: false)
        finishLasso(cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke(cancelled: true)
        finishLasso(cancelled: true)
    }

    override func draw(_ rect: CGRect) {
        guard
            let context = UIGraphicsGetCurrentContext(),
            let pdfView,
            let model
        else {
            return
        }

        for stroke in model.strokes {
            guard let page = model.page(for: stroke.pageID) else { continue }
            drawStroke(points: stroke.points, width: stroke.width, page: page, pdfView: pdfView, context: context)
        }

        for paste in model.pastedClips {
            guard let page = model.page(for: paste.pageID) else { continue }
            drawPaste(paste, page: page, pdfView: pdfView)
        }

        if let selection = model.lassoSelection, let page = model.page(for: selection.pageID) {
            drawLasso(points: selection.points, page: page, pdfView: pdfView, context: context, isDraft: false)
        }

        if let strokeDraft {
            drawStroke(
                points: strokeDraft.points,
                width: strokeDraft.width,
                page: strokeDraft.page,
                pdfView: pdfView,
                context: context
            )
        }

        if let lassoDraft {
            drawLasso(points: lassoDraft.points, page: lassoDraft.page, pdfView: pdfView, context: context, isDraft: true)
        }
    }

    private func configure() {
        isOpaque = false
        isMultipleTouchEnabled = false
        isUserInteractionEnabled = true
        contentMode = .redraw
    }

    private func touchInfo(for touch: UITouch) -> TouchInfo? {
        guard let pdfView else { return nil }

        let pointInPDFView = convert(touch.location(in: self), to: pdfView)
        guard let page = pdfView.page(for: pointInPDFView, nearest: true) else { return nil }

        let pointOnPage = pdfView.convert(pointInPDFView, to: page)
        guard let model else { return nil }

        return TouchInfo(
            pdfView: pdfView,
            page: page,
            pageID: model.pageID(for: page),
            pointOnPage: pointOnPage
        )
    }

    private func appendStroke(touch: UITouch) {
        guard
            var draft = strokeDraft,
            let pdfView
        else {
            return
        }

        let pointInPDFView = convert(touch.location(in: self), to: pdfView)
        let pointOnPage = pdfView.convert(pointInPDFView, to: draft.page)

        if let lastPoint = draft.points.last {
            let minimumDistance = max(0.5, draft.width / 8)
            guard lastPoint.distance(to: pointOnPage) >= minimumDistance else { return }
        }

        draft.points.append(pointOnPage)
        strokeDraft = draft
        setNeedsDisplay()
    }

    private func appendLasso(touch: UITouch) {
        guard
            var draft = lassoDraft,
            let pdfView
        else {
            return
        }

        let pointInPDFView = convert(touch.location(in: self), to: pdfView)
        let pointOnPage = pdfView.convert(pointInPDFView, to: draft.page)

        if let lastPoint = draft.points.last {
            guard lastPoint.distance(to: pointOnPage) >= 2 else { return }
        }

        draft.points.append(pointOnPage)
        lassoDraft = draft
        setNeedsDisplay()
    }

    private func finishStroke(cancelled: Bool) {
        defer {
            strokeDraft = nil
            setNeedsDisplay()
        }

        guard !cancelled, let strokeDraft, let model else { return }

        model.addStroke(BleachStroke(
            pageID: strokeDraft.pageID,
            width: strokeDraft.width,
            points: strokeDraft.points
        ))
    }

    private func finishLasso(cancelled: Bool) {
        defer {
            lassoDraft = nil
            setNeedsDisplay()
        }

        guard !cancelled, let lassoDraft, let model else { return }

        if lassoDraft.points.count > 2 {
            model.setLassoSelection(LassoSelection(pageID: lassoDraft.pageID, points: lassoDraft.points))
        } else {
            model.setLassoSelection(nil)
        }
    }

    private func drawStroke(
        points: [CGPoint],
        width: CGFloat,
        page: PDFPage,
        pdfView: PDFView,
        context: CGContext
    ) {
        guard !points.isEmpty else { return }

        let lineWidth = max(1, width * pdfView.scaleFactor)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setFillColor(UIColor.white.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(lineWidth)

        let viewPoints = convert(points: points, page: page, pdfView: pdfView)

        if viewPoints.count == 1, let point = viewPoints.first {
            let radius = lineWidth / 2
            context.fillEllipse(in: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: lineWidth,
                height: lineWidth
            ))
            return
        }

        guard let firstPoint = viewPoints.first else { return }

        context.beginPath()
        context.move(to: firstPoint)
        for point in viewPoints.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private func drawLasso(
        points: [CGPoint],
        page: PDFPage,
        pdfView: PDFView,
        context: CGContext,
        isDraft: Bool
    ) {
        guard points.count > 1 else { return }

        let viewPoints = convert(points: points, page: page, pdfView: pdfView)
        guard let firstPoint = viewPoints.first else { return }

        context.saveGState()
        context.setLineWidth(2)
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setFillColor(UIColor.systemBlue.withAlphaComponent(isDraft ? 0.08 : 0.14).cgColor)
        context.setLineDash(phase: 0, lengths: [8, 5])
        context.setLineJoin(.round)

        context.beginPath()
        context.move(to: firstPoint)
        for point in viewPoints.dropFirst() {
            context.addLine(to: point)
        }
        context.closePath()
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }

    private func drawPaste(_ paste: PastedClip, page: PDFPage, pdfView: PDFView) {
        let bottomLeft = pdfView.convert(paste.origin, from: page)
        let topRight = pdfView.convert(
            CGPoint(x: paste.origin.x + paste.size.width, y: paste.origin.y + paste.size.height),
            from: page
        )

        let bottomLeftInSelf = pdfView.convert(bottomLeft, to: self)
        let topRightInSelf = pdfView.convert(topRight, to: self)
        let rect = CGRect(
            x: min(bottomLeftInSelf.x, topRightInSelf.x),
            y: min(bottomLeftInSelf.y, topRightInSelf.y),
            width: abs(topRightInSelf.x - bottomLeftInSelf.x),
            height: abs(topRightInSelf.y - bottomLeftInSelf.y)
        )

        paste.image.draw(in: rect)
    }

    private func convert(points: [CGPoint], page: PDFPage, pdfView: PDFView) -> [CGPoint] {
        points.map { pointOnPage -> CGPoint in
            let pointInPDFView = pdfView.convert(pointOnPage, from: page)
            return pdfView.convert(pointInPDFView, to: self)
        }
    }
}

private struct TouchInfo {
    let pdfView: PDFView
    let page: PDFPage
    let pageID: UUID
    let pointOnPage: CGPoint
}

private struct StrokeDraft {
    let page: PDFPage
    let pageID: UUID
    let width: CGFloat
    var points: [CGPoint]
}

private struct LassoDraft {
    let page: PDFPage
    let pageID: UUID
    var points: [CGPoint]
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let deltaX = x - other.x
        let deltaY = y - other.y
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }
}

