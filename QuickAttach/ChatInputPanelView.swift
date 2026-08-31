import UIKit

/// Telegram chat composer reproduced from ChatTextInputPanelNode (HEAD 6ad963e):
/// no panel background, three glass elements — 40pt attach circle, field capsule
/// with the sticker accessory, 40pt mic circle that slides off-screen when text
/// is entered, and a 40x34 accent send pill overlapping the field's right edge.
///
/// Quick-attach behavior follows the ChatGPT reference video (IMG_2842.MP4):
/// on release the field capsule EXPANDS upward and the photo becomes an
/// attachment preview INSIDE the input, with an "×" badge on its corner;
/// the message is sent only via the send button.
final class ChatInputPanelView: UIView {

    let attachButton = HitSlopButton(type: .custom)
    private let attachGlass = GlassSurfaceView(style: .regular, interactive: true)
    private let attachIcon = UIImageView()
    private let fieldBackground = GlassSurfaceView(style: .regular, interactive: true, cornerRadius: 20)
    private let textField = UITextField()
    private let stickerIcon = UIImageView()
    private let micButton = UIButton(type: .custom)
    private let micGlass = GlassSurfaceView(style: .regular, interactive: true)
    private let micIcon = UIImageView()
    private let sendContainer = UIView()
    private let sendPill = UIView()
    private let sendIconView = UIImageView()
    private let sendButton = UIButton(type: .custom)

    private let chipWrap = UIView()
    private let chipImageView = UIImageView()
    private let chipRemoveButton = UIButton(type: .custom)
    private let chipRemoveIcon = AttachmentBadge.makeIcon()

    private var fieldHeightConstraint: NSLayoutConstraint!
    private var fieldTrailingToMic: NSLayoutConstraint!
    private var fieldTrailingToEdge: NSLayoutConstraint!
    private var textFieldTrailing: NSLayoutConstraint!
    private var hasContentState = false

    private(set) var attachedImage: UIImage?

    var onAttachTap: (() -> Void)?
    var onSend: ((String?, UIImage?) -> Void)?

    private let chipSide: CGFloat = 64
    private let chipInset: CGFloat = 8
    private let fieldIdleHeight: CGFloat = 40
    private var fieldExpandedHeight: CGFloat { chipInset + chipSide + fieldIdleHeight }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // ChatControllerNode passes .clear: no panel background, no separator.
        backgroundColor = .clear

        // Attach button: 40pt glass circle, IconAttachment 30pt, black tint.
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        attachGlass.translatesAutoresizingMaskIntoConstraints = false
        attachGlass.isUserInteractionEnabled = false
        attachButton.addSubview(attachGlass)
        attachIcon.image = UIImage(named: "TGIconAttachment")
        attachIcon.tintColor = Theme.panelControl
        attachIcon.translatesAutoresizingMaskIntoConstraints = false
        attachGlass.contentView.addSubview(attachIcon)
        attachButton.hitSlop = 4 // 48x48 touch area behind the 40pt circle
        attachButton.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)
        addSubview(attachButton)

        // Field: glass rounded rect, radius 20 (== capsule at the idle 40pt height,
        // stays 20 like the ChatGPT reference when expanded with an attachment).
        fieldBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fieldBackground)

        textField.attributedPlaceholder = NSAttributedString(
            string: "Message",
            attributes: [.foregroundColor: Theme.inputPlaceholder]
        )
        textField.font = .systemFont(ofSize: 17)
        textField.textColor = Theme.inputText
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        textField.returnKeyType = .send
        textField.delegate = self
        fieldBackground.contentView.addSubview(textField)

        // Sticker accessory: 24pt, inputControl tint at view alpha 0.5.
        stickerIcon.image = UIImage(named: "TGAccessoryIconStickers")
        stickerIcon.tintColor = Theme.inputControl
        stickerIcon.alpha = 0.5
        stickerIcon.isUserInteractionEnabled = false
        stickerIcon.translatesAutoresizingMaskIntoConstraints = false
        fieldBackground.contentView.addSubview(stickerIcon)

        // Attachment preview inside the field (ChatGPT reference).
        chipWrap.translatesAutoresizingMaskIntoConstraints = false
        chipWrap.alpha = 0.0
        fieldBackground.contentView.addSubview(chipWrap)

        chipImageView.contentMode = .scaleAspectFill
        chipImageView.clipsToBounds = true
        chipImageView.layer.cornerRadius = 10
        chipImageView.translatesAutoresizingMaskIntoConstraints = false
        chipWrap.addSubview(chipImageView)

        // ChatGPT reference: × inside the thumbnail, black-40% circle, no border.
        // The glyph is an image view, not the button's own image: the flying
        // badge hands over to this one, so both are built by AttachmentBadge.
        chipRemoveButton.backgroundColor = AttachmentBadge.circleColor
        chipRemoveButton.layer.cornerRadius = AttachmentBadge.cornerRadius
        chipRemoveIcon.translatesAutoresizingMaskIntoConstraints = false
        chipRemoveButton.addSubview(chipRemoveIcon)
        chipRemoveButton.alpha = 0.0
        chipRemoveButton.translatesAutoresizingMaskIntoConstraints = false
        chipRemoveButton.addTarget(self, action: #selector(removeAttachment), for: .touchUpInside)
        fieldBackground.contentView.addSubview(chipRemoveButton)

        // Mic: 40pt glass circle, IconMicrophone 30pt, black tint.
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micGlass.translatesAutoresizingMaskIntoConstraints = false
        micGlass.isUserInteractionEnabled = false
        micButton.addSubview(micGlass)
        micIcon.image = UIImage(named: "TGIconMicrophone")
        micIcon.tintColor = Theme.panelControl
        micIcon.translatesAutoresizingMaskIntoConstraints = false
        micGlass.contentView.addSubview(micIcon)
        addSubview(micButton)

        // Send: 46x40 container overlapping the field's right edge;
        // pill inset (3,3) -> 40x34, radius 17, accent fill, send.pdf icon.
        sendContainer.translatesAutoresizingMaskIntoConstraints = false
        sendContainer.alpha = 0.0
        sendContainer.isUserInteractionEnabled = false
        addSubview(sendContainer)

        sendPill.backgroundColor = Theme.sendPill
        sendPill.layer.cornerRadius = 17
        sendPill.transform = CGAffineTransform(scaleX: 0.001, y: 0.001)
        sendPill.translatesAutoresizingMaskIntoConstraints = false
        sendContainer.addSubview(sendPill)

        sendIconView.image = UIImage(named: "TGSendIcon")
        sendIconView.tintColor = Theme.sendIcon
        sendIconView.translatesAutoresizingMaskIntoConstraints = false
        sendPill.addSubview(sendIconView)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        addSubview(sendButton)

        fieldHeightConstraint = fieldBackground.heightAnchor.constraint(equalToConstant: fieldIdleHeight)
        fieldTrailingToMic = fieldBackground.trailingAnchor.constraint(equalTo: micButton.leadingAnchor, constant: -6)
        fieldTrailingToEdge = fieldBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        textFieldTrailing = textField.trailingAnchor.constraint(equalTo: fieldBackground.trailingAnchor, constant: -21)

        NSLayoutConstraint.activate([
            // Attach: x = 8, bottom-aligned with the field's text row.
            attachButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            attachButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 40),
            attachButton.heightAnchor.constraint(equalToConstant: 40),

            attachGlass.leadingAnchor.constraint(equalTo: attachButton.leadingAnchor),
            attachGlass.topAnchor.constraint(equalTo: attachButton.topAnchor),
            attachGlass.trailingAnchor.constraint(equalTo: attachButton.trailingAnchor),
            attachGlass.bottomAnchor.constraint(equalTo: attachButton.bottomAnchor),
            attachIcon.centerXAnchor.constraint(equalTo: attachGlass.centerXAnchor),
            attachIcon.centerYAnchor.constraint(equalTo: attachGlass.centerYAnchor),

            // Field: leading = attach + 6, grows upward from the panel bottom.
            fieldBackground.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 6),
            fieldBackground.topAnchor.constraint(equalTo: topAnchor),
            fieldBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            fieldHeightConstraint,
            fieldTrailingToMic,

            // Text row pinned to the field bottom: left 12, right toggled -47/-82.
            textField.leadingAnchor.constraint(equalTo: fieldBackground.leadingAnchor, constant: 12),
            textFieldTrailing,
            textField.bottomAnchor.constraint(equalTo: fieldBackground.bottomAnchor),
            textField.heightAnchor.constraint(equalToConstant: 40),

            stickerIcon.trailingAnchor.constraint(equalTo: fieldBackground.trailingAnchor, constant: -8),
            stickerIcon.centerYAnchor.constraint(equalTo: fieldBackground.bottomAnchor, constant: -20),
            stickerIcon.widthAnchor.constraint(equalToConstant: 24),
            stickerIcon.heightAnchor.constraint(equalToConstant: 24),

            // Attachment preview at the field's top-left (inside).
            chipWrap.leadingAnchor.constraint(equalTo: fieldBackground.leadingAnchor, constant: chipInset),
            chipWrap.topAnchor.constraint(equalTo: fieldBackground.topAnchor, constant: chipInset),
            chipWrap.widthAnchor.constraint(equalToConstant: chipSide),
            chipWrap.heightAnchor.constraint(equalToConstant: chipSide),

            chipImageView.leadingAnchor.constraint(equalTo: chipWrap.leadingAnchor),
            chipImageView.topAnchor.constraint(equalTo: chipWrap.topAnchor),
            chipImageView.trailingAnchor.constraint(equalTo: chipWrap.trailingAnchor),
            chipImageView.bottomAnchor.constraint(equalTo: chipWrap.bottomAnchor),

            chipRemoveButton.trailingAnchor.constraint(equalTo: chipWrap.trailingAnchor, constant: -AttachmentBadge.inset),
            chipRemoveButton.topAnchor.constraint(equalTo: chipWrap.topAnchor, constant: AttachmentBadge.inset),
            chipRemoveButton.widthAnchor.constraint(equalToConstant: AttachmentBadge.side),
            chipRemoveButton.heightAnchor.constraint(equalToConstant: AttachmentBadge.side),

            chipRemoveIcon.leadingAnchor.constraint(equalTo: chipRemoveButton.leadingAnchor),
            chipRemoveIcon.trailingAnchor.constraint(equalTo: chipRemoveButton.trailingAnchor),
            chipRemoveIcon.topAnchor.constraint(equalTo: chipRemoveButton.topAnchor),
            chipRemoveIcon.bottomAnchor.constraint(equalTo: chipRemoveButton.bottomAnchor),

            // Mic: trailing 8, bottom-aligned with the field.
            micButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            micButton.bottomAnchor.constraint(equalTo: fieldBackground.bottomAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 40),
            micButton.heightAnchor.constraint(equalToConstant: 40),

            micGlass.leadingAnchor.constraint(equalTo: micButton.leadingAnchor),
            micGlass.topAnchor.constraint(equalTo: micButton.topAnchor),
            micGlass.trailingAnchor.constraint(equalTo: micButton.trailingAnchor),
            micGlass.bottomAnchor.constraint(equalTo: micButton.bottomAnchor),
            micIcon.centerXAnchor.constraint(equalTo: micGlass.centerXAnchor),
            micIcon.centerYAnchor.constraint(equalTo: micGlass.centerYAnchor),

            // Send: 46x40 at the right edge of the field's text row.
            sendContainer.trailingAnchor.constraint(equalTo: fieldBackground.trailingAnchor),
            sendContainer.bottomAnchor.constraint(equalTo: fieldBackground.bottomAnchor),
            sendContainer.widthAnchor.constraint(equalToConstant: 46),
            sendContainer.heightAnchor.constraint(equalToConstant: 40),

            sendPill.leadingAnchor.constraint(equalTo: sendContainer.leadingAnchor, constant: 3),
            sendPill.topAnchor.constraint(equalTo: sendContainer.topAnchor, constant: 3),
            sendPill.trailingAnchor.constraint(equalTo: sendContainer.trailingAnchor, constant: -3),
            sendPill.bottomAnchor.constraint(equalTo: sendContainer.bottomAnchor, constant: -3),

            sendIconView.centerXAnchor.constraint(equalTo: sendPill.centerXAnchor),
            sendIconView.centerYAnchor.constraint(equalTo: sendPill.centerYAnchor),
            sendIconView.widthAnchor.constraint(equalToConstant: 30),
            sendIconView.heightAnchor.constraint(equalToConstant: 30),

            sendButton.leadingAnchor.constraint(equalTo: sendContainer.leadingAnchor),
            sendButton.topAnchor.constraint(equalTo: sendContainer.topAnchor),
            sendButton.trailingAnchor.constraint(equalTo: sendContainer.trailingAnchor),
            sendButton.bottomAnchor.constraint(equalTo: sendContainer.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Attachment preview (ChatGPT reference behavior)

    /// Expands the field to its FULL target state in one motion — height for
    /// the preview slot, width to the panel edge, mic slide-off, and the send
    /// pill — all in a single spring that matches the thumbnail flight in
    /// QuickAttachOverlayView.dismiss (0.32s / damping 0.82 / velocity 0.4).
    /// Returns the frame the flying thumbnail should land in, in `view`'s
    /// coordinate space. The preview itself is revealed via `revealAttachment`.
    func prepareAttachmentSlot(in view: UIView, image: UIImage) -> CGRect {
        attachedImage = image
        chipImageView.image = image
        chipWrap.alpha = 0.0
        chipRemoveButton.alpha = 0.0
        fieldHeightConstraint.constant = fieldExpandedHeight

        if !hasContentState {
            hasContentState = true
            fieldTrailingToMic.isActive = false
            fieldTrailingToEdge.isActive = true
            textFieldTrailing.constant = -67
            sendContainer.isUserInteractionEnabled = true
            sendButton.isUserInteractionEnabled = true
            sendIconView.transform = CGAffineTransform(translationX: -22, y: 18)
            UIView.animate(withDuration: 0.2, delay: 0.0, options: [.curveEaseInOut]) {
                self.sendContainer.alpha = 1.0
            }
        }

        UIView.animate(withDuration: 0.32, delay: 0.0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4) {
            self.superview?.layoutIfNeeded()
            self.micButton.transform = CGAffineTransform(translationX: 56, y: 0)
            self.stickerIcon.transform = CGAffineTransform(translationX: -46, y: 0)
            self.sendPill.transform = .identity
            self.sendIconView.transform = .identity
        }
        superview?.layoutIfNeeded()
        return chipImageView.convert(chipImageView.bounds, to: view)
    }

    func revealAttachment(_ image: UIImage) {
        attachedImage = image
        chipImageView.image = image
        chipWrap.alpha = 1.0
        // The badge already arrived visually on the flying thumbnail — show
        // the real one instantly, no pop.
        chipRemoveButton.transform = .identity
        chipRemoveButton.alpha = 1.0
        updateSendButton()
    }

    @objc private func removeAttachment() {
        attachedImage = nil
        // Preview blinks out fast (~70ms), then the capsule resizes back down
        // with a spring.
        UIView.animate(withDuration: 0.07, delay: 0.0, options: [.curveLinear]) {
            self.chipWrap.alpha = 0.0
            self.chipRemoveButton.alpha = 0.0
        }
        fieldHeightConstraint.constant = fieldIdleHeight
        UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.4) {
            self.superview?.layoutIfNeeded()
        } completion: { _ in
            self.chipImageView.image = nil
        }
        updateSendButton()
    }

    func clearAfterSend() {
        textField.text = nil
        attachedImage = nil
        chipImageView.image = nil
        chipWrap.alpha = 0.0
        chipRemoveButton.alpha = 0.0
        fieldHeightConstraint.constant = fieldIdleHeight
        UIView.animate(withDuration: 0.25) {
            self.superview?.layoutIfNeeded()
        }
        updateSendButton()
    }

    // MARK: - Frames for the send transition

    /// Current attachment preview frame in `view` coordinates (send source).
    func chipFrame(in view: UIView) -> CGRect {
        chipImageView.convert(chipImageView.bounds, to: view)
    }

    /// Field capsule frame in `view` coordinates (send source for text).
    /// The attach button's hit slop reaches past the panel's own bounds (the
    /// button is flush with the panel's bottom edge), and a point outside those
    /// bounds never reaches the button on its own. Hand it over explicitly.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let hit = super.hitTest(point, with: event) { return hit }
        let inAttach = attachButton.point(inside: convert(point, to: attachButton), with: event)
        return inAttach ? attachButton : nil
    }

    func fieldFrame(in view: UIView) -> CGRect {
        fieldBackground.convert(fieldBackground.bounds, to: view)
    }

    // MARK: - Actions

    @objc private func attachTapped() {
        onAttachTap?()
    }

    @objc private func textChanged() {
        updateSendButton()
    }

    @objc private func sendTapped() {
        let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (text?.isEmpty == false) || attachedImage != nil else { return }
        onSend?(text?.isEmpty == false ? text : nil, attachedImage)
    }

    /// Telegram behavior: entering text slides the mic off-screen to the right
    /// (ChatTextInputPanelNode.swift:3432), the field extends to the panel edge,
    /// and the send pill materializes inside the field's right edge with a
    /// 0.2s fade + scale-up + icon slide-in from (-22, 18).
    private func updateSendButton() {
        let hasContent = (textField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) || attachedImage != nil
        guard hasContent != hasContentState else { return }
        hasContentState = hasContent

        if hasContent {
            fieldTrailingToMic.isActive = false
            fieldTrailingToEdge.isActive = true
        } else {
            fieldTrailingToEdge.isActive = false
            fieldTrailingToMic.isActive = true
        }
        textFieldTrailing.constant = hasContent ? -67 : -21
        sendContainer.isUserInteractionEnabled = hasContent
        sendButton.isUserInteractionEnabled = hasContent

        // Telegram runs the layout motion on a 0.4s spring transition; only the
        // send container's alpha uses the 0.2s easeInOut fade.
        UIView.animate(withDuration: 0.2, delay: 0.0, options: [.curveEaseInOut]) {
            self.sendContainer.alpha = hasContent ? 1.0 : 0.0
        }
        UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3) {
            self.superview?.layoutIfNeeded()
            self.micButton.transform = hasContent ? CGAffineTransform(translationX: 56, y: 0) : .identity
            self.stickerIcon.transform = hasContent ? CGAffineTransform(translationX: -46, y: 0) : .identity
            self.sendPill.transform = hasContent ? .identity : CGAffineTransform(scaleX: 0.001, y: 0.001)
        }
        if hasContent {
            sendIconView.transform = CGAffineTransform(translationX: -22, y: 18)
            UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3) {
                self.sendIconView.transform = .identity
            }
        }
    }
}

/// Button whose touch area is larger than its artwork. The attach circle is
/// 40pt because that is what Telegram draws; the finger gets a bit more.
final class HitSlopButton: UIButton {
    var hitSlop: CGFloat = 0

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point)
    }
}

extension ChatInputPanelView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return false
    }
}
