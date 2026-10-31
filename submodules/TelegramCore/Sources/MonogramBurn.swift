import Foundation
import Postbox
import SwiftSignalKit

public func monogramBurnMessage(account: Account, messageId: MessageId) -> Signal<Void, NoError> {
    MonogramSettings.shared.markBurned(messageId)
    let postbox = account.postbox
    return _internal_markMessageContentAsConsumedInteractively(postbox: postbox, messageId: messageId)
    |> then(postbox.transaction { transaction -> Void in
        _internal_deleteMessages(transaction: transaction, mediaBox: postbox.mediaBox, ids: [messageId])
    })
}
