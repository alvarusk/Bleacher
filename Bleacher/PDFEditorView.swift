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
    private var observedZoomScale: CGFloat?
    private var observedZoomFitMode: ZoomFitMode?
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

    override func layoutSubviews() {
        super.layoutSubviews()

        if let model {
            applyZoom(model: model, force: false)
            overlayView.setNeedsDisplay()
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
            observedZoomScale = nil
            observedZoomFitMode = nil
        }

        if observedNavigationRevision != model.navigationRevision {
            goToCurrentPage(model: model)
            observedNavigationRevision = model.navigationRevision
        }

        if observedZoomScale == nil ||
            observedZoomFitMode != model.zoomFitMode ||
            abs((observedZoomScale ?? 0) - model.zoomScale) > 0.0001 {
            applyZoom(model: model, force: true)
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
        configureScrollIndicators()

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

    private func applyZoom(model: DocumentModel, force: Bool) {
        guard pdfView.document != nil else { return }

        let fitScale = max(fitScale(for: model.zoomFitMode), 0.01)
        pdfView.minScaleFactor = fitScale * model.minZoomScale
        pdfView.maxScaleFactor = fitScale * model.maxZoomScale

        let targetScale = fitScale * model.zoomScale
        if force || abs(pdfView.scaleFactor - targetScale) > 0.001 {
            pdfView.autoScales = false
            pdfView.scaleFactor = targetScale
        }

        observedZoomScale = model.zoomScale
        observedZoomFitMode = model.zoomFitMode
        configureScrollIndicators()
    }

    private func fitScale(for mode: ZoomFitMode) -> CGFloat {
        guard let page = pdfView.currentPage ?? pdfView.document?.page(at: 0) else {
            return pdfView.scaleFactorForSizeToFit
        }

        let pageBounds = page.bounds(for: .cropBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return pdfView.scaleFactorForSizeToFit
        }

        let availableWidth = max(1, pdfView.bounds.width - 24)
        let availableHeight = max(1, pdfView.bounds.height - 24)

        switch mode {
        case .width:
            return availableWidth / pageBounds.width
        case .height:
            return availableHeight / pageBounds.height
        }
    }

    private func syncCurrentPage() {
        model?.select(page: pdfView.currentPage)
    }

    private func configureScrollIndicators() {
        guard let scrollView = pdfView.firstSubview(of: UIScrollView.self) else { return }

        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.indicatorStyle = .black
        scrollView.flashScrollIndicators()
    }
}

final class BleachOverlayView: UIView, UIGestureRecognizerDelegate {
    weak var pdfView: PDFView?
    weak var model: DocumentModel?

    private var strokeDraft: StrokeDraft?
    private var lassoDraft: LassoDraft?
    private var pasteDraft: PasteDraft?
    private var moveDraft: MoveDraft?
    private var panDraft: PanDraft?
    private var scrollBarDraft: ScrollBarDraft?
    private var pinchStartZoomScale: CGFloat = 1
    private var pinchRecognizer: UIPinchGestureRecognizer?
    private var twoFingerPanRecognizer: UIPanGestureRecognizer?

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
            touches.count == 1,
            let touch = touches.first,
            let model
        else {
            return
        }

        if model.selectedTool == .pan {
            if !beginScrollBarDrag(touch: touch) {
                beginPan(touch: touch)
            }
            return
        }

        guard let touchInfo = touchInfo(for: touch) else { return }

        model.select(page: touchInfo.page)

        switch model.selectedTool {
        case .pan:
            break

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
            if let pastedClip = model.pastedClip(at: touchInfo.pointOnPage, pageID: touchInfo.pageID) {
                moveDraft = MoveDraft(
                    page: touchInfo.page,
                    clip: pastedClip,
                    currentOrigin: pastedClip.origin,
                    touchOffset: CGPoint(
                        x: touchInfo.pointOnPage.x - pastedClip.origin.x,
                        y: touchInfo.pointOnPage.y - pastedClip.origin.y
                    )
                )
            } else if let preview = model.pastePreview(at: touchInfo.pointOnPage, pageID: touchInfo.pageID) {
                pasteDraft = PasteDraft(page: touchInfo.page, paste: preview)
            }
        }

        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.count == 1, let touch = touches.first else { return }

        if strokeDraft != nil {
            appendStroke(touch: touch)
        } else if lassoDraft != nil {
            appendLasso(touch: touch)
        } else if pasteDraft != nil {
            updatePasteDraft(touch: touch)
        } else if moveDraft != nil {
            updateMoveDraft(touch: touch)
        } else if panDraft != nil {
            updatePan(touch: touch)
        } else if scrollBarDraft != nil {
            updateScrollBarDrag(touch: touch)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touches.count == 1, let touch = touches.first {
            if strokeDraft != nil {
                appendStroke(touch: touch)
            } else if lassoDraft != nil {
                appendLasso(touch: touch)
            } else if pasteDraft != nil {
                updatePasteDraft(touch: touch)
            } else if moveDraft != nil {
                updateMoveDraft(touch: touch)
            } else if panDraft != nil {
                updatePan(touch: touch)
            } else if scrollBarDraft != nil {
                updateScrollBarDrag(touch: touch)
            }
        }

        finishStroke(cancelled: false)
        finishLasso(cancelled: false)
        finishPaste(cancelled: false)
        finishMove(cancelled: false)
        finishPan(cancelled: false)
        finishScrollBarDrag(cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke(cancelled: true)
        finishLasso(cancelled: true)
        finishPaste(cancelled: true)
        finishMove(cancelled: true)
        finishPan(cancelled: true)
        finishScrollBarDrag(cancelled: true)
    }

    override func draw(_ rect: CGRect) {
        guard
            let context = UIGraphicsGetCurrentContext(),
            let pdfView,
            let model
        else {
            return
        }

        let movingClipID = moveDraft?.clip.id
        let editedPageIDs = Set(model.strokes.map(\.pageID) + model.pastedClips.map(\.pageID))

        for pageID in editedPageIDs {
            guard let page = model.page(for: pageID) else { continue }

            for layer in model.layers(for: pageID) {
                switch layer {
                case .stroke(let stroke):
                    drawStroke(points: stroke.points, width: stroke.width, page: page, pdfView: pdfView, context: context)
                case .paste(var paste):
                    if let movingClipID = movingClipID, paste.id == movingClipID {
                        paste.origin = moveDraft?.currentOrigin ?? paste.origin
                        drawPaste(paste, page: page, pdfView: pdfView, context: context, alpha: 0.7)
                    } else {
                        drawPaste(paste, page: page, pdfView: pdfView, context: context, alpha: 1)
                    }
                }
            }
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

        if let pasteDraft {
            drawPaste(pasteDraft.paste, page: pasteDraft.page, pdfView: pdfView, context: context, alpha: 0.55)
        }

        drawScrollBar(in: context)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    private func configure() {
        isOpaque = false
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
        contentMode = .redraw

        let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchRecognizer.delegate = self
        addGestureRecognizer(pinchRecognizer)
        self.pinchRecognizer = pinchRecognizer

        let twoFingerPanRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPanRecognizer.minimumNumberOfTouches = 2
        twoFingerPanRecognizer.maximumNumberOfTouches = 2
        twoFingerPanRecognizer.delegate = self
        addGestureRecognizer(twoFingerPanRecognizer)
        self.twoFingerPanRecognizer = twoFingerPanRecognizer
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let model else { return }

        switch recognizer.state {
        case .began:
            pinchStartZoomScale = model.zoomScale
            cancelDrafts()
        case .changed, .ended:
            model.setZoomScale(pinchStartZoomScale * recognizer.scale)
        case .cancelled, .failed:
            cancelDrafts()
        default:
            break
        }

        setNeedsDisplay()
    }

    @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        guard let scrollView = pdfScrollView() else { return }

        if recognizer.state == .began {
            cancelDrafts()
        }

        let translation = recognizer.translation(in: self)
        var nextOffset = CGPoint(
            x: scrollView.contentOffset.x - translation.x,
            y: scrollView.contentOffset.y - translation.y
        )
        clampContentOffset(&nextOffset, in: scrollView)

        scrollView.setContentOffset(nextOffset, animated: false)
        recognizer.setTranslation(.zero, in: self)
        setNeedsDisplay()
    }

    private func clampContentOffset(_ offset: inout CGPoint, in scrollView: UIScrollView) {
        let minX = -scrollView.adjustedContentInset.left
        let minY = -scrollView.adjustedContentInset.top
        let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right)
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)

        offset.x = min(max(offset.x, minX), maxX)
        offset.y = min(max(offset.y, minY), maxY)
    }

    private func cancelDrafts() {
        strokeDraft = nil
        lassoDraft = nil
        pasteDraft = nil
        moveDraft = nil
        panDraft = nil
        scrollBarDraft = nil
    }

    private func pdfScrollView() -> UIScrollView? {
        pdfView?.firstSubview(of: UIScrollView.self)
    }

    private func beginPan(touch: UITouch) {
        guard let scrollView = pdfScrollView() else { return }

        panDraft = PanDraft(
            startLocation: touch.location(in: self),
            startContentOffset: scrollView.contentOffset
        )
        scrollView.flashScrollIndicators()
    }

    private func updatePan(touch: UITouch) {
        guard
            let panDraft,
            let scrollView = pdfScrollView()
        else {
            return
        }

        let location = touch.location(in: self)
        var nextOffset = CGPoint(
            x: panDraft.startContentOffset.x + panDraft.startLocation.x - location.x,
            y: panDraft.startContentOffset.y + panDraft.startLocation.y - location.y
        )
        clampContentOffset(&nextOffset, in: scrollView)
        scrollView.setContentOffset(nextOffset, animated: false)
        setNeedsDisplay()
    }

    private func finishPan(cancelled: Bool) {
        panDraft = nil
        if !cancelled {
            pdfScrollView()?.flashScrollIndicators()
        }
    }

    private func beginScrollBarDrag(touch: UITouch) -> Bool {
        guard
            let scrollView = pdfScrollView(),
            let metrics = scrollBarMetrics(for: scrollView)
        else {
            return false
        }

        let location = touch.location(in: self)
        guard metrics.hitRect.contains(location) else { return false }

        var nextOffset = scrollView.contentOffset
        if !metrics.thumbRect.insetBy(dx: -10, dy: -8).contains(location) {
            let rawProgress = (location.y - metrics.trackRect.minY - metrics.thumbRect.height / 2) / metrics.thumbTravel
            let progress = min(max(rawProgress, 0), 1)
            nextOffset.y = metrics.minOffsetY + progress * metrics.offsetTravel
            clampContentOffset(&nextOffset, in: scrollView)
            scrollView.setContentOffset(nextOffset, animated: false)
        }

        scrollBarDraft = ScrollBarDraft(
            startLocationY: location.y,
            startContentOffsetY: scrollView.contentOffset.y
        )
        scrollView.flashScrollIndicators()
        setNeedsDisplay()
        return true
    }

    private func updateScrollBarDrag(touch: UITouch) {
        guard
            let scrollBarDraft,
            let scrollView = pdfScrollView(),
            let metrics = scrollBarMetrics(for: scrollView)
        else {
            return
        }

        let deltaY = touch.location(in: self).y - scrollBarDraft.startLocationY
        var nextOffset = scrollView.contentOffset
        nextOffset.y = scrollBarDraft.startContentOffsetY + deltaY / metrics.thumbTravel * metrics.offsetTravel
        clampContentOffset(&nextOffset, in: scrollView)
        scrollView.setContentOffset(nextOffset, animated: false)
        setNeedsDisplay()
    }

    private func finishScrollBarDrag(cancelled: Bool) {
        scrollBarDraft = nil
        if !cancelled {
            pdfScrollView()?.flashScrollIndicators()
        }
        setNeedsDisplay()
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

    private func updatePasteDraft(touch: UITouch) {
        guard
            var draft = pasteDraft,
            let pdfView
        else {
            return
        }

        let pointInPDFView = convert(touch.location(in: self), to: pdfView)
        let pointOnPage = pdfView.convert(pointInPDFView, to: draft.page)
        draft.paste.origin = CGPoint(
            x: pointOnPage.x - draft.paste.size.width / 2,
            y: pointOnPage.y - draft.paste.size.height / 2
        )
        pasteDraft = draft
        setNeedsDisplay()
    }

    private func updateMoveDraft(touch: UITouch) {
        guard
            var draft = moveDraft,
            let pdfView
        else {
            return
        }

        let pointInPDFView = convert(touch.location(in: self), to: pdfView)
        let pointOnPage = pdfView.convert(pointInPDFView, to: draft.page)
        draft.currentOrigin = CGPoint(
            x: pointOnPage.x - draft.touchOffset.x,
            y: pointOnPage.y - draft.touchOffset.y
        )
        moveDraft = draft
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

    private func finishPaste(cancelled: Bool) {
        defer {
            pasteDraft = nil
            setNeedsDisplay()
        }

        guard !cancelled, let pasteDraft, let model else { return }
        model.addPastedClip(pasteDraft.paste)
    }

    private func finishMove(cancelled: Bool) {
        defer {
            moveDraft = nil
            setNeedsDisplay()
        }

        guard !cancelled, let moveDraft, let model else { return }
        model.movePastedClip(id: moveDraft.clip.id, to: moveDraft.currentOrigin)
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

    private func drawPaste(
        _ paste: PastedClip,
        page: PDFPage,
        pdfView: PDFView,
        context: CGContext,
        alpha: CGFloat
    ) {
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

        context.saveGState()
        context.setAlpha(alpha)
        paste.image.draw(in: rect)

        if alpha < 1 {
            context.setAlpha(1)
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.setLineWidth(2)
            context.stroke(rect)
        }

        context.restoreGState()
    }

    private func drawScrollBar(in context: CGContext) {
        guard
            let scrollView = pdfScrollView(),
            let metrics = scrollBarMetrics(for: scrollView)
        else {
            return
        }

        context.saveGState()

        let trackPath = UIBezierPath(roundedRect: metrics.trackRect, cornerRadius: metrics.trackRect.width / 2)
        context.setFillColor(UIColor.secondaryLabel.withAlphaComponent(0.18).cgColor)
        context.addPath(trackPath.cgPath)
        context.fillPath()

        let thumbPath = UIBezierPath(roundedRect: metrics.thumbRect, cornerRadius: metrics.thumbRect.width / 2)
        let thumbAlpha: CGFloat = scrollBarDraft == nil ? 0.34 : 0.55
        context.setFillColor(UIColor.label.withAlphaComponent(thumbAlpha).cgColor)
        context.addPath(thumbPath.cgPath)
        context.fillPath()

        context.restoreGState()
    }

    private func scrollBarMetrics(for scrollView: UIScrollView) -> ScrollBarMetrics? {
        let minOffsetY = -scrollView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        let offsetTravel = maxOffsetY - minOffsetY
        guard offsetTravel > 1, bounds.height > 80 else { return nil }

        let trackInset: CGFloat = 14
        let trackRect = CGRect(
            x: bounds.maxX - 12,
            y: bounds.minY + trackInset,
            width: 4,
            height: bounds.height - trackInset * 2
        )
        guard trackRect.height > 44 else { return nil }

        let visibleRatio = min(1, scrollView.bounds.height / max(scrollView.contentSize.height, 1))
        let thumbHeight = min(trackRect.height, max(44, trackRect.height * visibleRatio))
        let thumbTravel = max(1, trackRect.height - thumbHeight)
        let progress = min(max((scrollView.contentOffset.y - minOffsetY) / offsetTravel, 0), 1)
        let thumbRect = CGRect(
            x: trackRect.minX,
            y: trackRect.minY + thumbTravel * progress,
            width: trackRect.width,
            height: thumbHeight
        )
        let hitRect = trackRect.insetBy(dx: -20, dy: 0)

        return ScrollBarMetrics(
            minOffsetY: minOffsetY,
            offsetTravel: offsetTravel,
            thumbTravel: thumbTravel,
            trackRect: trackRect,
            thumbRect: thumbRect,
            hitRect: hitRect
        )
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

private struct PasteDraft {
    let page: PDFPage
    var paste: PastedClip
}

private struct MoveDraft {
    let page: PDFPage
    let clip: PastedClip
    var currentOrigin: CGPoint
    let touchOffset: CGPoint
}

private struct PanDraft {
    let startLocation: CGPoint
    let startContentOffset: CGPoint
}

private struct ScrollBarDraft {
    let startLocationY: CGFloat
    let startContentOffsetY: CGFloat
}

private struct ScrollBarMetrics {
    let minOffsetY: CGFloat
    let offsetTravel: CGFloat
    let thumbTravel: CGFloat
    let trackRect: CGRect
    let thumbRect: CGRect
    let hitRect: CGRect
}

private extension UIView {
    func firstSubview<T: UIView>(of type: T.Type) -> T? {
        if let view = self as? T {
            return view
        }

        for subview in subviews {
            if let match = subview.firstSubview(of: type) {
                return match
            }
        }

        return nil
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let deltaX = x - other.x
        let deltaY = y - other.y
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }
}
