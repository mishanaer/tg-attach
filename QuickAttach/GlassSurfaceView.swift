import UIKit

/// Analog of Telegram-iOS `GlassBackgroundView` (GlassBackgroundComponent.swift),
/// `.panel` kind, light theme. iOS 26+: native UIGlassEffect(.regular) with a
/// white-10% tint (.clear gets no tint in light mode; Telegram additionally
/// tweaks private luma parameters we cannot reach). Pre-26 fallback approximates
/// their LegacyGlassView: soft blur + white-70% fill + edge highlight + drop shadow
/// (generateLegacyGlassImage / generateLegacyShadowImage).
final class GlassSurfaceView: UIView {
    enum GlassStyle { case regular, clear }

    let effectView = UIVisualEffectView()
    private let legacyFillView = UIView()
    private let fixedCornerRadius: CGFloat?
    private let forceLegacy: Bool
    var contentView: UIView { effectView.contentView }

    /// - Parameter tint: overrides the default material tint. Telegram's
    ///   GlassBackgroundView takes a tint kind the same way (.panel is denser
    ///   than the default surface tint); a flat fill inside contentView is
    ///   swallowed by the iOS 26 glass pipeline, so the tint IS the lever.
    /// - Parameter forceLegacy: render as blur + fill even on iOS 26. The
    ///   native UIGlassEffect tone-maps its backdrop and caps how dense a
    ///   surface can get; Telegram's own GlassBackgroundView (blur + fill)
    ///   has no such ceiling, and the attachment panel visibly relies on it.
    init(style: GlassStyle = .regular, interactive: Bool = false, cornerRadius: CGFloat? = nil, tint: UIColor? = nil, forceLegacy: Bool = false) {
        self.fixedCornerRadius = cornerRadius
        self.forceLegacy = forceLegacy
        super.init(frame: .zero)
        addSubview(effectView)
        if #available(iOS 26.0, *), !forceLegacy {
            let glass = UIGlassEffect(style: style == .clear ? .clear : .regular)
            glass.isInteractive = interactive
            if let tint {
                glass.tintColor = tint
            } else if style == .regular {
                glass.tintColor = UIColor(white: 1.0, alpha: 0.1) // GlassBackgroundComponent.swift:752-754
            }
            effectView.effect = glass
            if let cornerRadius {
                effectView.cornerConfiguration = .uniformCorners(radius: .fixed(cornerRadius))
            } else {
                effectView.cornerConfiguration = .capsule()
            }
        } else {
            effectView.effect = UIBlurEffect(style: .light)
            effectView.clipsToBounds = true
            legacyFillView.backgroundColor = tint ?? UIColor(white: 1.0, alpha: 0.7) // LegacyGlassView, :710-718
            effectView.contentView.addSubview(legacyFillView)
            // Edge highlight + drop shadow per generateLegacyGlassImage/-ShadowImage.
            effectView.layer.borderWidth = 1.0
            effectView.layer.borderColor = UIColor(white: 1.0, alpha: 0.5).cgColor
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.08
            layer.shadowRadius = 8
            layer.shadowOffset = CGSize(width: 0, height: 2)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        effectView.frame = bounds
        if forceLegacy {
            effectView.layer.cornerRadius = fixedCornerRadius ?? bounds.height / 2
            legacyFillView.frame = effectView.contentView.bounds
        } else if #unavailable(iOS 26.0) {
            effectView.layer.cornerRadius = fixedCornerRadius ?? bounds.height / 2
            legacyFillView.frame = effectView.contentView.bounds
        }
    }
}
