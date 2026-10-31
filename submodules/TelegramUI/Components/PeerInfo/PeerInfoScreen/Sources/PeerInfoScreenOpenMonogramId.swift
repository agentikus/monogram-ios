import Foundation
import UIKit
import Display
import AccountContext
import SwiftSignalKit
import TelegramCore
import AsyncDisplayKit
import UndoUI
import ContextUI

extension PeerInfoScreenNode {
    func openMonogramIdContextMenu(node: ASDisplayNode, gesture: ContextGesture?, text: String) {
        let copyAction = { [weak self] in
            guard let self else {
                return
            }
            UIPasteboard.general.string = text
            self.controller?.present(UndoOverlayController(presentationData: self.presentationData, content: .copy(text: "ID скопирован"), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .current)
        }

        guard let sourceNode = node as? ContextExtractedContentContainingNode else {
            copyAction()
            return
        }

        var items: [ContextMenuItem] = []
        items.append(.action(ContextMenuActionItem(text: self.presentationData.strings.MyProfile_BirthdayActionCopy, icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.contextMenu.primaryColor) }, action: { c, _ in
            c?.dismiss {
                copyAction()
            }
        })))

        let actions = ContextController.Items(content: .list(items))
        let contextController = makeContextController(presentationData: self.presentationData, source: .extracted(PeerInfoContextExtractedContentSource(sourceNode: sourceNode)), items: .single(actions), gesture: gesture)
        self.controller?.present(contextController, in: .window(.root))
    }
}
