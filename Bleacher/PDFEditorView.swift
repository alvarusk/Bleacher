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
            syncCurrentPage()
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

    private func syncCurrentPage() {
        model?.select(page: pdfView.currentPage)
    }
}

final class BleachOverlayView: UIView {
    weak var pdfView: PDFView?
    weak var model: DocumentModel?

    private var draft: StrokeDraft?

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
            let pdfView,
            let model
        else {
            return
        }

        let pointInPDFView = convert(touch.location(in: self), to: pdfView)
        guard let page = pdfView.page(for: pointInPDFView, nearest: true) else { return }

        let pointOnPage = pdfView.convert(pointInPDFView, to: page)
        let widthOnPage = max(1, model.eraserWidth / max(pdfView.scaleFactor, 0.01))
        draft = StrokeDraft(
            page: page,
            pageID: model.pageID(for: page),
            width: widthOnPage,
            points: [pointOnPage]
        )
        model.select(page: page)
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        append(touch: touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            append(touch: touch)
        }
        finishStroke(cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke(cancelled: true)
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
            draw(points: stroke.points, width: stroke.width, page: page, pdfView: pdfView, context: context)
        }

        if let draft {
            draw(points: draft.points, width: draft.width, page: draft.page, pdfView: pdfView, context: context)
        }
    }

    private func configure() {
        isOpaque = false
        isMultipleTouchEnabled = false
        isUserInteractionEnabled = true
        contentMode = .redraw
    }

    private func append(touch: UITouch) {
        guard
            var draft,
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
        self.draft = draft
        setNeedsDisplay()
    }

    private func finishStroke(cancelled: Bool) {
        defer {
            draft = nil
            setNeedsDisplay()
        }

        guard !cancelled, let draft, let model else { return }

        model.addStroke(BleachStroke(
            pageID: draft.pageID,
            width: draft.width,
            points: draft.points
        ))
    }

    private func draw(
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

        let viewPoints = points.map { pointOnPage -> CGPoint in
            let pointInPDFView = pdfView.convert(pointOnPage, from: page)
            return pdfView.convert(pointInPDFView, to: self)
        }

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
}

private struct StrokeDraft {
    let page: PDFPage
    let pageID: UUID
    let width: CGFloat
    var points: [CGPoint]
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let deltaX = x - other.x
        let deltaY = y - other.y
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }
}

