import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AttachmentUI
import TelegramPresentationData

final class EmptyAttachmentScreen: ViewController, AttachmentContainable {
    var requestAttachmentMenuExpansion: () -> Void = {}
    var updateNavigationStack: (@escaping ([AttachmentContainable]) -> ([AttachmentContainable], AttachmentMediaPickerContext?)) -> Void = { _ in }
    var parentController: () -> ViewController? = {
        return nil
    }
    var updateTabBarAlpha: (CGFloat, ContainedViewLayoutTransition) -> Void = { _, _ in }
    var updateTabBarVisibility: (Bool, ContainedViewLayoutTransition) -> Void = { _, _ in }
    var cancelPanGesture: () -> Void = {}
    var isContainerPanning: () -> Bool = {
        return false
    }
    var isContainerExpanded: () -> Bool = {
        return false
    }
    var isMinimized: Bool = false

    var mediaPickerContext: AttachmentMediaPickerContext? {
        return nil
    }

    private let backgroundColor: UIColor

    init(presentationData: PresentationData) {
        self.backgroundColor = presentationData.theme.list.plainBackgroundColor

        super.init(navigationBarPresentationData: nil)

        self.navigationPresentation = .modal
        self._hasGlassStyle = true
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        let displayNode = ASDisplayNode()
        displayNode.backgroundColor = self.backgroundColor
        self.displayNode = displayNode

        self.displayNodeDidLoad()
    }
}
