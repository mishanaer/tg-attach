import UIKit

/// Telegram's attachment sheet reproduced from AttachmentUI (HEAD 6ad963e):
/// a bottom sheet that glass-morphs out of the attach button (AttachmentController
/// animateIn), top corner radius 38, collapsed at 24.88% of screen height with
/// drag-to-expand/dismiss (AttachmentContainer), a 3-column media grid with a
/// camera tile (MediaPickerUI), and a floating 62pt glass tab capsule
/// (AttachmentPanel) with the classic five tabs.
///
/// Documented substitutions: private _UILiquidLensView -> clear-glass pill;
/// icon gaussian-blur transition -> alpha crossfade; live camera -> static tile;
/// DeviceMetrics corner table -> _displayCornerRadius KVC.
final class AttachmentSheetController: UIViewController {

    var onSendImages: (([UIImage]) -> Void)?
    var onDismissed: (() -> Void)?

    private let images: [UIImage]
    private let sourceRect: CGRect

    private let dimView = UIView()
    private let wrappingView = UIView()
    private let clipView = UIView()
    private let bottomClipView = UIView()
    private let sheetContentView = UIView()
    private let pillView = UIImageView()
    private let headerBackground = UIView()
    private let titleLabel = UILabel()
    private let titleChevron = UIImageView()
    private let closeButton = UIButton(type: .custom)
    private let closeGlass = GlassSurfaceView(style: .regular, interactive: true)
    private let closeIcon = UIImageView()
    private let morphIcon = UIImageView()
    private var collectionView: UICollectionView!
    // GlassBackgroundView(tintColor: .panel) is a dense panel, not clear
    // glass: measured ~156 luminance over ~45 content in the capture, i.e.
    // roughly a 0.45 white tint over the blur.
    // Blur + fill like Telegram's own GlassBackgroundView: the native
    // UIGlassEffect tone-maps its backdrop and cannot reach the production
    // panel density (measured ceiling ~205 luminance whatever the tint).
    private let tabCapsule = GlassSurfaceView(style: .regular, interactive: true, cornerRadius: 31.0,
                                              tint: UIColor(white: 1.0, alpha: 0.55), forceLegacy: true)
    // Lens reads ~-30 luminance vs the capsule in the capture: dark dim.
    private let lensView = GlassSurfaceView(style: .clear, cornerRadius: 28.0)
    private let lensDim = UIView()
    // AttachmentPanel keeps TWO identical icon rows: a base one and an
    // accent-tinted one masked to the lens shape, so the recolor is literally
    // the lens sliding over the row (AttachmentPanel.swift:2556-2562).
    private let tabsBaseRow = UIView()
    private let tabsSelectedRow = UIView()
    private let selectedRowMask = UIView()
    private var selectedTabIndex = 0
    private var tabFrames: [CGRect] = []
    // Selection order = badge numbers (MediaPickerGridItem counter content).
    private var selectedItems: [Int] = []
    private let captionPlaceholder = UILabel()
    private let sendCircle = UIView()
    private let sendIcon = UIImageView()

    private enum SheetState { case collapsed, expanded }
    private var state: SheetState = .collapsed
    private var panStartY: CGFloat = 0
    private var isDismissing = false

    private let photoItemCount = 40
    private let headerHeight: CGFloat = 65.0 // measured 66.3pt to the first grid row in production
    private let capsuleHeight: CGFloat = 62.0    // AttachmentPanel glassPanelHeight
    private let capsuleSideInset: CGFloat = 20.0 // glassPanelSideInset
    private let topCornerRadius: CGFloat = 38.0  // AttachmentContainer glass top radius

    private var screenCornerRadius: CGFloat {
        (UIScreen.main.value(forKey: "_displayCornerRadius") as? CGFloat) ?? 53.0
    }
    private var bottomCornerRadius: CGFloat { max(24.0, screenCornerRadius) - 2.0 }
    private var collapsedTopInset: CGFloat {
        let size = view.bounds.size
        let factor: CGFloat = size.width <= 320.0 ? 0.15 : 0.2488
        return floor(max(size.width, size.height) * factor)
    }
    private var expandedTopInset: CGFloat { view.safeAreaInsets.top + 10.0 }

    init(images: [UIImage], sourceRect: CGRect) {
        self.images = images.isEmpty ? [UIImage()] : images
        self.sourceRect = sourceRect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Setup

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimView.backgroundColor = UIColor(white: 0.0, alpha: 0.25) // AttachmentController.swift:589-591
        dimView.alpha = 0.0
        view.addSubview(dimView)
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimTapped)))

        view.addSubview(wrappingView)

        clipView.clipsToBounds = true
        clipView.layer.cornerRadius = topCornerRadius
        clipView.layer.cornerCurve = .continuous
        clipView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        wrappingView.addSubview(clipView)

        bottomClipView.clipsToBounds = true
        bottomClipView.layer.cornerRadius = bottomCornerRadius
        bottomClipView.layer.cornerCurve = .continuous
        bottomClipView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        clipView.addSubview(bottomClipView)

        sheetContentView.backgroundColor = UIColor.white // list.plainBackgroundColor 0xFFFFFF
        bottomClipView.addSubview(sheetContentView)

        // Drag pill: 36x5 at y=5, black@0.07 (AttachmentContainer.swift:112-114, 627-629).
        pillView.image = Self.stretchableCircle(diameter: 5.0)
        pillView.tintColor = UIColor.black.withAlphaComponent(0.07)
        sheetContentView.addSubview(pillView)

        // Header (production): glass × circle on the left, centered
        // "Recents" (Font.semibold 17, monospaced digits — MediaPickerTitleView)
        // with the album-dropdown chevron (Navigation/TitleExpand at 40% black).
        titleLabel.text = "Recents"
        titleLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .black
        sheetContentView.addSubview(titleLabel)

        titleChevron.image = UIImage(named: "NavTitleExpand")?.withRenderingMode(.alwaysTemplate)
        titleChevron.tintColor = UIColor.black.withAlphaComponent(0.4)
        titleChevron.contentMode = .center
        sheetContentView.addSubview(titleChevron)

        closeGlass.isUserInteractionEnabled = false
        closeButton.addSubview(closeGlass)
        closeIcon.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        closeIcon.tintColor = .black
        closeIcon.contentMode = .center
        closeGlass.contentView.addSubview(closeIcon)
        closeButton.addTarget(self, action: #selector(dimTapped), for: .touchUpInside)
        sheetContentView.addSubview(closeButton)

        let layout = MediaGridLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.bounces = false
        collectionView.isScrollEnabled = false
        collectionView.register(SheetPhotoCell.self, forCellWithReuseIdentifier: "photo")
        collectionView.register(SheetCameraCell.self, forCellWithReuseIdentifier: "camera")
        // The grid scrolls BEHIND the header; the bar background is transparent
        // until scrolled (MediaPickerScreen.updateNavigation: alpha = offset/2).
        sheetContentView.insertSubview(collectionView, at: 0)
        headerBackground.backgroundColor = .white
        headerBackground.alpha = 0.0
        sheetContentView.insertSubview(headerBackground, aboveSubview: collectionView)
        sheetContentView.bringSubviewToFront(pillView)
        sheetContentView.bringSubviewToFront(titleLabel)
        sheetContentView.bringSubviewToFront(closeButton)

        setupTabCapsule()

        // Telegram's morph shows a duplicated attach icon fading out (0.15s;
        // gaussian blur 0->10 is private API — alpha crossfade substitute).
        morphIcon.image = UIImage(named: "TGIconAttachment")
        morphIcon.tintColor = Theme.panelControl
        morphIcon.contentMode = .center
        clipView.addSubview(morphIcon)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        wrappingView.addGestureRecognizer(pan)
    }

    private func setupTabCapsule() {
        sheetContentView.addSubview(tabCapsule)
        // Selection "lens" substitute behind the selected tab: LiquidLensView
        // (private liquid glass) -> clear glass pill, radius 28 (AP:2549),
        // dimmed to the measured production tint (~-30 luminance vs capsule).
        lensView.isUserInteractionEnabled = false
        tabCapsule.contentView.addSubview(lensView)
        // Inside the legacy (blur + fill) capsule fills composite normally:
        // 0.12 black over ~230 gives the measured production delta of ~-30.
        lensDim.backgroundColor = UIColor(white: 0.0, alpha: 0.12)
        lensDim.layer.cornerRadius = 28.0
        lensDim.layer.cornerCurve = .continuous
        lensDim.isUserInteractionEnabled = false
        tabCapsule.contentView.addSubview(lensDim)

        // Production tab set from the reference capture. Wallet is an attach
        // bot whose icon is served by the bot itself — SF symbol substitute.
        let tabs: [(UIImage?, String)] = [
            (UIImage(named: "AttachGallery")?.withRenderingMode(.alwaysTemplate), "Gallery"),
            (UIImage(named: "AttachArticle")?.withRenderingMode(.alwaysTemplate), "Article"),
            (UIImage(named: "AttachGift")?.withRenderingMode(.alwaysTemplate), "Gift"),
            (UIImage(systemName: "wallet.bifold.fill") ?? UIImage(systemName: "wallet.pass.fill"), "Wallet"),
            (UIImage(named: "AttachFile")?.withRenderingMode(.alwaysTemplate), "File"),
            (UIImage(named: "AttachLocation")?.withRenderingMode(.alwaysTemplate), "Location"),
        ]

        // Two identical rows; the selected row is masked to the lens rect so
        // the tint change is driven by the lens position itself.
        tabsBaseRow.isUserInteractionEnabled = false
        tabsSelectedRow.isUserInteractionEnabled = false
        tabCapsule.contentView.addSubview(tabsBaseRow)
        tabCapsule.contentView.addSubview(tabsSelectedRow)
        selectedRowMask.backgroundColor = .black
        selectedRowMask.layer.cornerRadius = 28.0
        selectedRowMask.layer.cornerCurve = .continuous
        tabsSelectedRow.mask = selectedRowMask

        let px = TelegramGraphics.screenPixel
        for (row, color) in [(tabsBaseRow, UIColor.black.withAlphaComponent(0.8)), (tabsSelectedRow, Theme.accent)] {
            for (index, tab) in tabs.enumerated() {
                let button = UIView()
                button.tag = 100 + index
                row.addSubview(button)

                let icon = UIImageView(image: tab.0)
                icon.tintColor = color
                icon.contentMode = .scaleAspectFit
                // Icon 30x30 at topInset 4 + px + 5 (AttachmentPanel.swift:281-286).
                icon.frame = CGRect(x: 21.0, y: 9.0 + px, width: 30.0, height: 30.0)
                button.addSubview(icon)

                let label = UILabel()
                label.text = tab.1
                label.font = .systemFont(ofSize: 10, weight: .medium) // glass Font.medium(10)
                label.textColor = color
                label.textAlignment = .center
                label.lineBreakMode = .byTruncatingTail
                let labelTop = icon.frame.midY + 15.0 + px + px
                label.frame = CGRect(x: 4.0, y: labelTop, width: 64.0, height: 12.0)
                button.addSubview(label)
            }
        }

        // Selecting mode (AttachmentPanel isSelecting): the tab row gives way
        // to a caption field + send. The field is a non-editable placeholder
        // here — the full ChatTextInputPanelNode is out of the demo's scope.
        captionPlaceholder.text = "Add a caption..."
        captionPlaceholder.font = .systemFont(ofSize: 17)
        captionPlaceholder.textColor = Theme.inputPlaceholder
        captionPlaceholder.alpha = 0.0
        tabCapsule.contentView.addSubview(captionPlaceholder)

        sendCircle.backgroundColor = Theme.sendPill
        sendCircle.layer.cornerRadius = 23.0
        sendCircle.alpha = 0.0
        tabCapsule.contentView.addSubview(sendCircle)
        sendIcon.image = UIImage(named: "TGSendIcon")
        sendIcon.tintColor = Theme.sendIcon
        sendIcon.contentMode = .center
        sendCircle.addSubview(sendIcon)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tabCapsuleTapped(_:)))
        tabCapsule.contentView.addGestureRecognizer(tap)
    }

    /// Crossfade between the tab row and the caption/send pair — the panel's
    /// isSelecting switch (AttachmentPanel.update(isSelecting:)).
    private func updateSelectionPanel() {
        let selecting = !selectedItems.isEmpty
        UIView.animate(withDuration: 0.2, delay: 0.0, options: [.curveEaseInOut]) {
            for view in [self.tabsBaseRow, self.tabsSelectedRow, self.lensView, self.lensDim] {
                view.alpha = selecting ? 0.0 : 1.0
            }
            self.captionPlaceholder.alpha = selecting ? 1.0 : 0.0
            self.sendCircle.alpha = selecting ? 1.0 : 0.0
        }
    }

    private func performSend() {
        guard !selectedItems.isEmpty else { return }
        let picked = selectedItems.map { images[($0 - 1) % images.count] }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSendImages?(picked)
        animateOut(velocity: 0) {}
    }

    /// Tab switch: the lens slides to the tapped tab with the panel's spring
    /// (.animated 0.4 .spring — AttachmentPanel.swift:1927). Tab CONTENT is out
    /// of scope for the demo; the switcher itself is the original interaction.
    @objc private func tabCapsuleTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: tabCapsule.contentView)
        if !selectedItems.isEmpty {
            if sendCircle.frame.insetBy(dx: -12, dy: -12).contains(location) {
                performSend()
            }
            return
        }
        guard !tabFrames.isEmpty else { return }
        var nearest = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, frame) in tabFrames.enumerated() {
            let d = abs(frame.midX - location.x)
            if d < bestDistance { bestDistance = d; nearest = index }
        }
        guard nearest != selectedTabIndex else { return }
        selectedTabIndex = nearest
        UISelectionFeedbackGenerator().selectionChanged()
        let target = tabFrames[nearest].insetBy(dx: 3.0, dy: 3.0)
        UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.0, options: [.allowUserInteraction]) {
            self.lensView.frame = target
            self.lensDim.frame = target
            self.selectedRowMask.frame = target
        }
    }

    // MARK: - Layout

    private func layoutSheet(topInset: CGFloat) {
        let size = view.bounds.size
        dimView.frame = CGRect(x: 0, y: -size.height, width: size.width, height: size.height * 2.0)
        wrappingView.frame = CGRect(x: 0, y: topInset, width: size.width, height: size.height - topInset)
        clipView.frame = wrappingView.bounds
        bottomClipView.frame = clipView.bounds
        sheetContentView.frame = bottomClipView.bounds
        layoutSheetContent()
    }

    private func layoutSheetContent() {
        let width = sheetContentView.bounds.width
        let height = sheetContentView.bounds.height
        let safeBottom = view.safeAreaInsets.bottom

        pillView.frame = CGRect(x: floor((width - 36.0) / 2.0), y: 5.0, width: 36.0, height: 5.0)
        titleLabel.sizeToFit()
        titleLabel.frame.origin = CGPoint(x: floor((width - titleLabel.bounds.width) / 2.0), y: 26.0)
        if let chevron = titleChevron.image {
            titleChevron.frame = CGRect(x: titleLabel.frame.maxX + 3.0,
                                        y: floor(titleLabel.frame.midY - chevron.size.height / 2.0),
                                        width: chevron.size.width, height: chevron.size.height)
        }
        closeButton.frame = CGRect(x: 20.0, y: floor(titleLabel.frame.midY - 22.0), width: 44.0, height: 44.0)
        closeGlass.frame = closeButton.bounds
        closeIcon.frame = closeButton.bounds

        headerBackground.frame = CGRect(x: 0, y: 0, width: width, height: headerHeight)
        collectionView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        collectionView.contentInset = UIEdgeInsets(top: headerHeight + 1.0, left: 0, bottom: safeBottom + 8.0 + capsuleHeight + 8.0, right: 0)

        // Floating glass capsule: panelY = height - panelHeight - panelOffset,
        // phone panelOffset = 8 (AttachmentController.swift:1475, 1493-1495).
        // No safe-area part: the home indicator floats over the glass.
        let capsuleWidth = width - capsuleSideInset * 2.0
        tabCapsule.frame = CGRect(x: capsuleSideInset,
                                  y: height - 8.0 - capsuleHeight,
                                  width: capsuleWidth,
                                  height: capsuleHeight)

        // Tab buttons: 72x62 at y=-3; screen-coord minX = 23 + i*pitch —
        // AttachmentPanel.swift:2021: (width - sideInset*2 - buttonWidth) / (count-1).
        tabsBaseRow.frame = tabCapsule.contentView.bounds
        tabsSelectedRow.frame = tabCapsule.contentView.bounds
        let tabCount = tabsBaseRow.subviews.count
        let pitch = floor((view.bounds.width - 23.0 * 2.0 - 72.0) / CGFloat(max(1, tabCount - 1)))
        tabFrames = (0..<tabCount).map { index in
            CGRect(x: 23.0 - capsuleSideInset + CGFloat(index) * pitch, y: -3.0, width: 72.0, height: 62.0)
        }
        for row in [tabsBaseRow, tabsSelectedRow] {
            for button in row.subviews {
                button.frame = tabFrames[button.tag - 100]
            }
        }
        captionPlaceholder.sizeToFit()
        captionPlaceholder.frame.origin = CGPoint(x: 20.0,
                                                  y: floor((capsuleHeight - captionPlaceholder.bounds.height) / 2.0))
        sendCircle.frame = CGRect(x: capsuleWidth - 46.0 - 8.0,
                                  y: floor((capsuleHeight - 46.0) / 2.0), width: 46.0, height: 46.0)
        sendIcon.frame = sendCircle.bounds

        let selectedFrame = tabFrames[selectedTabIndex].insetBy(dx: 3.0, dy: 3.0)
        lensView.frame = selectedFrame
        lensDim.frame = selectedFrame
        selectedRowMask.frame = selectedFrame
    }

    // MARK: - Presentation morph (AttachmentController.swift:1150-1216)

    func animateIn() {
        view.layoutIfNeeded()
        layoutSheet(topInset: collapsedTopInset)
        state = .collapsed

        let finalWrapFrame = wrappingView.frame
        let sourceRadius = sourceRect.width * 0.5

        sheetContentView.alpha = 0.0
        UIView.animate(withDuration: 0.2) {
            self.sheetContentView.alpha = 1.0
        }
        // Duplicated attach icon fades out inside the growing glass (0.15s).
        morphIcon.frame = CGRect(origin: .zero, size: sourceRect.size)
        morphIcon.alpha = 1.0
        UIView.animate(withDuration: 0.15, delay: 0.0, options: [.curveEaseInOut]) {
            self.morphIcon.alpha = 0.0
        }
        UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveLinear]) {
            self.dimView.alpha = 1.0
        }

        // Corner radii morph from the source circle: 0.2 easeInOut.
        animateCorner(clipView.layer, from: sourceRadius, to: topCornerRadius)
        animateCorner(bottomClipView.layer, from: sourceRadius, to: bottomCornerRadius)

        // Position: 0.4 customSpring(damping 110, iv 1.1); size: 0.45 (damping 110, iv 0).
        for (layer, finalFrame) in morphLayers(wrapFrame: finalWrapFrame) {
            let finalBounds = CGRect(origin: .zero, size: finalFrame.size)
            let finalPosition = CGPoint(x: finalFrame.midX, y: finalFrame.midY)
            let startBounds = CGRect(origin: .zero, size: sourceRect.size)
            let startPosition = layer === wrappingView.layer
                ? CGPoint(x: sourceRect.midX, y: sourceRect.midY)
                : CGPoint(x: sourceRect.width / 2.0, y: sourceRect.height / 2.0)

            layer.position = finalPosition
            layer.bounds = finalBounds
            layer.add(Self.spring(keyPath: "position", from: NSValue(cgPoint: startPosition), to: NSValue(cgPoint: finalPosition), duration: 0.4, damping: 110.0, initialVelocity: 1.1), forKey: "morphPos")
            layer.add(Self.spring(keyPath: "bounds", from: NSValue(cgRect: startBounds), to: NSValue(cgRect: finalBounds), duration: 0.45, damping: 110.0, initialVelocity: 0.0), forKey: "morphBounds")
        }
    }

    /// Morph back into the attach button (AttachmentController.swift:1244-1336).
    func animateOut(velocity: CGFloat = 0, completion: @escaping () -> Void) {
        guard !isDismissing else { return }
        isDismissing = true
        let sourceRadius = sourceRect.width * 0.5
        let positionDamping: CGFloat = velocity != 0 ? 180.0 : 110.0
        let initialVelocity: CGFloat = velocity != 0
            ? abs(velocity / max(1.0, view.bounds.height - wrappingView.frame.minY)) : 0.0

        UIView.animate(withDuration: 0.12) {
            self.sheetContentView.alpha = 0.0
        }
        UIView.animate(withDuration: 0.22, delay: 0.0, options: [.curveEaseInOut]) {
            self.morphIcon.alpha = 1.0
        }
        UIView.animate(withDuration: 0.25, delay: 0.0, options: [.curveEaseInOut]) {
            self.dimView.alpha = 0.0
        }
        UIView.animate(withDuration: 0.15, delay: 0.2, options: [.curveLinear]) {
            self.wrappingView.alpha = 0.0
        }

        animateCorner(clipView.layer, from: clipView.layer.cornerRadius, to: sourceRadius)
        animateCorner(bottomClipView.layer, from: bottomClipView.layer.cornerRadius, to: sourceRadius)

        for (layer, currentFrame) in morphLayers(wrapFrame: wrappingView.frame) {
            let startBounds = CGRect(origin: .zero, size: currentFrame.size)
            let startPosition = layer === wrappingView.layer
                ? CGPoint(x: currentFrame.midX, y: currentFrame.midY)
                : CGPoint(x: currentFrame.width / 2.0, y: currentFrame.height / 2.0)
            let endBounds = CGRect(origin: .zero, size: sourceRect.size)
            let endPosition = layer === wrappingView.layer
                ? CGPoint(x: sourceRect.midX, y: sourceRect.midY)
                : CGPoint(x: sourceRect.width / 2.0, y: sourceRect.height / 2.0)

            layer.position = endPosition
            layer.bounds = endBounds
            layer.add(Self.spring(keyPath: "position", from: NSValue(cgPoint: startPosition), to: NSValue(cgPoint: endPosition), duration: 0.4, damping: positionDamping, initialVelocity: initialVelocity), forKey: "morphPos")
            layer.add(Self.spring(keyPath: "bounds", from: NSValue(cgRect: startBounds), to: NSValue(cgRect: endBounds), duration: 0.3, damping: 124.0, initialVelocity: 0.0), forKey: "morphBounds")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            guard let self else { return }
            self.willMove(toParent: nil)
            self.view.removeFromSuperview()
            self.removeFromParent()
            completion()
            self.onDismissed?()
        }
    }

    private func morphLayers(wrapFrame: CGRect) -> [(CALayer, CGRect)] {
        [
            (wrappingView.layer, wrapFrame),
            (clipView.layer, CGRect(origin: .zero, size: wrapFrame.size)),
            (bottomClipView.layer, CGRect(origin: .zero, size: wrapFrame.size)),
        ]
    }

    private func animateCorner(_ layer: CALayer, from: CGFloat, to: CGFloat) {
        layer.cornerRadius = to
        let animation = CABasicAnimation(keyPath: "cornerRadius")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "cornerMorph")
    }

    /// Telegram .customSpring == CASpring with mass 5, stiffness 900
    /// (ContainedViewLayoutTransition.swift:17, UIKitUtils.m:86-104).
    private static func spring(keyPath: String, from: Any, to: Any, duration: CFTimeInterval, damping: CGFloat, initialVelocity: CGFloat) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 5.0
        animation.stiffness = 900.0
        animation.damping = damping
        animation.initialVelocity = initialVelocity
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = true
        animation.fillMode = .forwards
        return animation
    }

    // MARK: - Snap / drag (AttachmentContainer.swift:371-437)

    @objc private func dimTapped() {
        animateOut(velocity: 0) {}
    }

    private func snap(to newState: SheetState, velocity: CGFloat) {
        state = newState
        let inset = newState == .expanded ? expandedTopInset : collapsedTopInset
        collectionView.isScrollEnabled = newState == .expanded
        // 0.45 customSpring(damping 124) ~= UIView spring ratio 0.92.
        UIView.animate(withDuration: 0.45, delay: 0.0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0.2, options: []) {
            self.layoutSheet(topInset: inset)
        }
    }

    private func settleBack() {
        let inset = state == .expanded ? expandedTopInset : collapsedTopInset
        UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseInOut]) {
            self.layoutSheet(topInset: inset)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !isDismissing else { return }
        let translation = gesture.translation(in: view).y
        let velocity = gesture.velocity(in: view).y

        switch gesture.state {
        case .began:
            panStartY = wrappingView.frame.minY
        case .changed:
            if state == .expanded && collectionView.contentOffset.y > 0.5 {
                panStartY = wrappingView.frame.minY - translation
                return
            }
            let newTop = max(expandedTopInset, panStartY + translation)
            wrappingView.frame.origin.y = newTop
        case .ended, .cancelled:
            let offset = wrappingView.frame.minY - (state == .expanded ? expandedTopInset : collapsedTopInset)
            if state == .collapsed {
                if offset > 60.0 || (offset > 0 && velocity > 300.0) {
                    animateOut(velocity: velocity) {}
                } else if velocity < -300.0 || offset < -collapsedTopInset / 2.0 {
                    snap(to: .expanded, velocity: velocity)
                } else {
                    settleBack()
                }
            } else {
                if velocity > 1800.0 || offset > 180.0 {
                    animateOut(velocity: velocity) {}
                } else if velocity > 300.0 || offset > collapsedTopInset / 2.0 {
                    snap(to: .collapsed, velocity: velocity)
                } else {
                    settleBack()
                }
            }
        default:
            break
        }
    }

    // MARK: - Images

    /// Stretchable filled circle used for the pill (NavigationBarBadge-style).
    private static func stretchableCircle(diameter: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        }
        let cap = diameter / 2.0
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: cap, left: cap, bottom: cap, right: cap))
            .withRenderingMode(.alwaysTemplate)
    }

    /// Unselected selection ring: 29x29, white 1.5pt stroke, inset 2-px,
    /// shadow blur 2.5 black@0.22 (CheckNode.swift:50-57, MediaPickerGridItem:822).
    static let selectionRingImage: UIImage = {
        let px = TelegramGraphics.screenPixel
        let side: CGFloat = 29.0
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { rendererContext in
            let context = rendererContext.cgContext
            context.setShadow(offset: .zero, blur: 2.5, color: UIColor(white: 0.0, alpha: 0.22).cgColor)
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(1.5)
            let inset = (2.0 - px) + 0.75
            context.strokeEllipse(in: CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: inset, dy: inset))
        }
    }()
}

// MARK: - Grid data source / delegate

extension AttachmentSheetController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        photoItemCount + 1 // item 0 = camera tile
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.item == 0 {
            return collectionView.dequeueReusableCell(withReuseIdentifier: "camera", for: indexPath)
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "photo", for: indexPath) as! SheetPhotoCell
        cell.imageView.image = images[(indexPath.item - 1) % images.count]
        cell.setSelectionIndex(selectedItems.firstIndex(of: indexPath.item).map { $0 + 1 }, animated: false)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item > 0 else { return } // camera tile: no-op in the demo
        if let position = selectedItems.firstIndex(of: indexPath.item) {
            selectedItems.remove(at: position)
        } else {
            selectedItems.append(indexPath.item)
        }
        UISelectionFeedbackGenerator().selectionChanged()
        // Renumber every visible badge; only the tapped cell animates
        // (MediaPickerGridItem.updateSelectionState).
        for case let cell as SheetPhotoCell in collectionView.visibleCells {
            guard let item = collectionView.indexPath(for: cell)?.item else { continue }
            cell.setSelectionIndex(selectedItems.firstIndex(of: item).map { $0 + 1 },
                                   animated: item == indexPath.item)
        }
        updateSelectionPanel()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offset = scrollView.contentOffset.y + scrollView.contentInset.top
        headerBackground.alpha = max(0.0, min(2.0, offset)) / 2.0
    }
}

extension AttachmentSheetController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - Grid layout (MediaPickerScreen: 3 columns, 1pt gaps, camera cutout 1x2)

private final class MediaGridLayout: UICollectionViewLayout {
    private var attributes: [UICollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0

    override func prepare() {
        super.prepare()
        attributes.removeAll()
        guard let collectionView else { return }
        let width = collectionView.bounds.width
        let spacing: CGFloat = 1.0
        let itemWidth = floor((width - spacing * 2.0) / 3.0)
        let count = collectionView.numberOfItems(inSection: 0)

        // Camera tile: one column, two rows + the 1pt gap (MediaPickerScreen:1722-1731).
        let cameraAttr = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        cameraAttr.frame = CGRect(x: 0, y: 0, width: itemWidth, height: itemWidth * 2.0 + spacing)
        attributes.append(cameraAttr)

        var slot = 0
        for item in 1..<count {
            var row = 0, col = 0
            var remaining = slot
            while true {
                row = remaining / 3
                col = remaining % 3
                if row < 2 && col == 0 { remaining += 1; slot += 1; continue } // camera cutout
                break
            }
            let attr = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: item, section: 0))
            attr.frame = CGRect(x: CGFloat(col) * (itemWidth + spacing),
                                y: CGFloat(row) * (itemWidth + spacing),
                                width: itemWidth, height: itemWidth)
            attributes.append(attr)
            contentHeight = max(contentHeight, attr.frame.maxY)
            slot += 1
        }
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        attributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        attributes.first { $0.indexPath == indexPath }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }
}

// MARK: - Cells

private final class SheetPhotoCell: UICollectionViewCell {
    let imageView = UIImageView()
    private let ringView = UIImageView(image: AttachmentSheetController.selectionRingImage)
    // Selected state: accent-filled 29pt circle with the selection ordinal,
    // spring-scaled in from 0.2 (InteractiveCheckNode counter content,
    // MediaPickerGridItem.swift:246-262, 822-823).
    private let badgeView = UIView()
    private let badgeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor(red: 0.937, green: 0.937, blue: 0.957, alpha: 1.0) // 0xEFEFF4
        contentView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        contentView.addSubview(imageView)

        badgeView.backgroundColor = Theme.accent
        badgeView.layer.cornerRadius = 14.5
        badgeView.alpha = 0.0
        badgeLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeView.addSubview(badgeLabel)
        contentView.addSubview(badgeView)
        contentView.addSubview(ringView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSelectionIndex(_ index: Int?, animated: Bool) {
        if let index {
            badgeLabel.text = "\(index)"
            guard badgeView.alpha < 1.0 else { return }
            badgeView.alpha = 1.0
            if animated {
                badgeView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                UIView.animate(withDuration: 0.5, delay: 0.0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.0) {
                    self.badgeView.transform = .identity
                }
            }
        } else if badgeView.alpha > 0.0 {
            if animated {
                UIView.animate(withDuration: 0.2) { self.badgeView.alpha = 0.0 }
            } else {
                badgeView.alpha = 0.0
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = contentView.bounds
        let badgeFrame = CGRect(x: contentView.bounds.width - 29.0 - 3.0, y: 3.0, width: 29.0, height: 29.0)
        ringView.frame = badgeFrame
        badgeView.frame = badgeFrame
        badgeLabel.frame = badgeView.bounds
    }
}

private final class SheetCameraCell: UICollectionViewCell {
    private let iconView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black // static stand-in for the live camera feed
        contentView.clipsToBounds = true
        iconView.image = UIImage(named: "AttachCamera")
        iconView.tintColor = .white
        contentView.addSubview(iconView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let iconSize = iconView.image?.size ?? CGSize(width: 30, height: 30)
        iconView.frame = CGRect(x: contentView.bounds.width - iconSize.width - 3.0,
                                y: 3.0 - TelegramGraphics.screenPixel,
                                width: iconSize.width, height: iconSize.height)
    }
}
