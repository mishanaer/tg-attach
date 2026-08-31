import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

private struct QuickAttachDemoDialogMessage {
    let id: Int32
    let timestampOffset: Int32
    let incoming: Bool
    let text: String
}

private struct QuickAttachDemoDialog {
    let peerId: PeerId
    let firstName: String
    let lastName: String?
    let color: PeerNameColor
    let unreadCount: Int32
    let messages: [QuickAttachDemoDialogMessage]
}

private let quickAttachDemoDialogs: [QuickAttachDemoDialog] = [
    QuickAttachDemoDialog(
        peerId: QuickAttachDemo.chatPeerId,
        firstName: "Ksuscha",
        lastName: nil,
        color: .blue,
        unreadCount: 0,
        messages: [
            QuickAttachDemoDialogMessage(id: 101, timestampOffset: -420, incoming: true, text: "Hey! Are you home yet?"),
            QuickAttachDemoDialogMessage(id: 102, timestampOffset: -360, incoming: false, text: "Yep, just walked in 🙌"),
            QuickAttachDemoDialogMessage(id: 103, timestampOffset: -300, incoming: true, text: "Send me the photos from the walk before you forget"),
            QuickAttachDemoDialogMessage(id: 104, timestampOffset: -240, incoming: false, text: "Sure! Btw, try holding the paperclip — new quick attach 😏")
        ]
    ),
    QuickAttachDemoDialog(
        peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(900000003)),
        firstName: "Misha",
        lastName: nil,
        color: .green,
        unreadCount: 1,
        messages: [
            QuickAttachDemoDialogMessage(id: 201, timestampOffset: -540, incoming: true, text: "Анимация уже ощущается намного лучше")
        ]
    ),
    QuickAttachDemoDialog(
        peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(900000004)),
        firstName: "Design",
        lastName: "Team",
        color: .violet,
        unreadCount: 1,
        messages: [
            QuickAttachDemoDialogMessage(id: 301, timestampOffset: -900, incoming: true, text: "Катя: Финальный макет прикрепила")
        ]
    ),
    QuickAttachDemoDialog(
        peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(900000005)),
        firstName: "Sasha",
        lastName: nil,
        color: .orange,
        unreadCount: 0,
        messages: [
            QuickAttachDemoDialogMessage(id: 401, timestampOffset: -1320, incoming: false, text: "Окей, посмотрю вечером")
        ]
    ),
    QuickAttachDemoDialog(
        peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(900000006)),
        firstName: "Family",
        lastName: nil,
        color: .pink,
        unreadCount: 1,
        messages: [
            QuickAttachDemoDialogMessage(id: 501, timestampOffset: -2100, incoming: true, text: "Мама: Позвони, когда освободишься")
        ]
    ),
    QuickAttachDemoDialog(
        peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(900000007)),
        firstName: "Quick Attach",
        lastName: "QA",
        color: .cyan,
        unreadCount: 0,
        messages: [
            QuickAttachDemoDialogMessage(id: 601, timestampOffset: -3600, incoming: true, text: "Selection, preview and swipe gestures are ready to test")
        ]
    )
]

private func makeQuickAttachDemoUser(id: PeerId, firstName: String, lastName: String?, color: PeerNameColor?) -> TelegramUser {
    return TelegramUser(
        id: id,
        accessHash: nil,
        firstName: firstName,
        lastName: lastName,
        username: nil,
        phone: nil,
        photo: [],
        botInfo: nil,
        restrictionInfo: nil,
        flags: [],
        emojiStatus: nil,
        usernames: [],
        storiesHidden: nil,
        nameColor: color.map { .preset($0) },
        backgroundEmojiId: nil,
        profileColor: nil,
        profileBackgroundEmojiId: nil,
        subscriberCount: nil,
        verificationIconFileId: nil
    )
}

extension QuickAttachDemo {
    static func localDialogMessageIds(peerId: PeerId) -> [MessageId]? {
        guard let dialog = quickAttachDemoDialogs.first(where: { $0.peerId == peerId }) else {
            return nil
        }
        return dialog.messages.map { message in
            MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: message.id)
        }
    }

    static func seedLocalDialogs(postbox: Postbox) -> Signal<Void, NoError> {
        return postbox.transaction { transaction -> Void in
            let accountPeer = makeQuickAttachDemoUser(id: accountPeerId, firstName: "Quick Attach", lastName: nil, color: nil)
            let dialogPeers = quickAttachDemoDialogs.map { dialog in
                makeQuickAttachDemoUser(id: dialog.peerId, firstName: dialog.firstName, lastName: dialog.lastName, color: dialog.color)
            }
            transaction.updatePeersInternal([accountPeer] + dialogPeers, update: { _, updated in
                return updated
            })

            for hole in transaction.allChatListHoles(groupId: .root) {
                transaction.replaceChatListHole(groupId: .root, index: hole.index, hole: nil)
            }
            for hole in transaction.allChatListHoles(groupId: Namespaces.PeerGroup.archive) {
                transaction.replaceChatListHole(groupId: Namespaces.PeerGroup.archive, index: hole.index, hole: nil)
            }

            let now = Int32(Date().timeIntervalSince1970)
            var messages: [StoreMessage] = []
            var readStates: [PeerId: [MessageId.Namespace: PeerReadState]] = [:]

            for dialog in quickAttachDemoDialogs {
                for message in dialog.messages {
                    let messageId = MessageId(peerId: dialog.peerId, namespace: Namespaces.Message.Cloud, id: message.id)
                    if !transaction.messageExists(id: messageId) {
                        messages.append(StoreMessage(
                            id: messageId,
                            customStableId: nil,
                            globallyUniqueId: nil,
                            groupingKey: nil,
                            threadId: nil,
                            timestamp: now + message.timestampOffset,
                            flags: message.incoming ? [.Incoming] : [],
                            tags: [],
                            globalTags: [],
                            localTags: [],
                            forwardInfo: nil,
                            authorId: message.incoming ? dialog.peerId : accountPeerId,
                            text: message.text,
                            attributes: [],
                            media: []
                        ))
                    }
                }

                if let topMessage = dialog.messages.last {
                    readStates[dialog.peerId] = [
                        Namespaces.Message.Cloud: .idBased(
                            maxIncomingReadId: dialog.unreadCount == 0 ? topMessage.id : topMessage.id - 1,
                            maxOutgoingReadId: topMessage.id,
                            maxKnownId: topMessage.id,
                            count: dialog.unreadCount,
                            markedUnread: false
                        )
                    ]
                }
            }

            if !messages.isEmpty {
                let _ = transaction.addMessages(messages, location: .UpperHistoryBlock)
            }
            for dialog in quickAttachDemoDialogs {
                transaction.removeHole(
                    peerId: dialog.peerId,
                    threadId: nil,
                    namespace: Namespaces.Message.Cloud,
                    space: .everywhere,
                    range: 1 ... (Int32.max - 1)
                )
            }
            if !readStates.isEmpty {
                transaction.resetIncomingReadStates(readStates)
            }
            for dialog in quickAttachDemoDialogs {
                transaction.updatePeerChatListInclusion(
                    dialog.peerId,
                    inclusion: .ifHasMessagesOrOneOf(groupId: .root, pinningIndex: nil, minTimestamp: nil)
                )
            }
        }
    }
}
