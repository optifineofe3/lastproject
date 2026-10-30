import Foundation
import UIKit
import tgapiC

@objc(TLParser)
class TLParser: NSObject {
    @objc static var sharedContext: Any?

    // Thread-safe set of message IDs saved from deletion.
    private static let deletedQueue = DispatchQueue(label: "com.lead.deletedIds",
                                                    attributes: .concurrent)
    private static var _deletedIds = Set<Int32>()
    private static let udKey = "LeadDeletedMsgIds"
    private static var _loaded = false
    private static var protectedChannelIds = Set<Int64>()

    /// Called from ObjC (Hooks.xm) before zeroing message IDs in anti-revoke.
    @objc static func addDeletedId(_ id: Int32) {
        guard id != 0 else { return }
        deletedQueue.async(flags: .barrier) {
            _deletedIds.insert(id)
            // Persist to UserDefaults for cross-session indicator support
            var saved = (UserDefaults.standard.array(forKey: udKey) as? [Int32]) ?? []
            if !saved.contains(id) {
                saved.append(id)
                // Keep only last 1000 IDs to avoid unbounded growth
                if saved.count > 1000 { saved.removeFirst(saved.count - 1000) }
                UserDefaults.standard.set(saved, forKey: udKey)
            }
        }
    }

    private static var deletedIds: Set<Int32> {
        deletedQueue.sync {
            if !_loaded {
                // First access: load persisted IDs from UserDefaults
                // (can't call deletedQueue.async inside sync, use flag trick)
            }
            return _deletedIds
        }
    }

    /// Load persisted deleted IDs from UserDefaults into memory (call once at startup).
    @objc static func loadPersistedIds() {
        deletedQueue.async(flags: .barrier) {
            guard !_loaded else { return }
            _loaded = true
            let saved = (UserDefaults.standard.array(forKey: udKey) as? [Int32]) ?? []
            _deletedIds.formUnion(saved)
        }
    }

    /// Dynamically extracts message.id.id from a ChatMessageItem using string description parsing.
    /// This is safer than Mirror because it bypasses computed properties and layout differences.
    @objc static func getMessageId(from item: Any) -> NSNumber? {
        let description = String(describing: item)
        
        let pattern = "MessageId\\(peerId: [^,]+, namespace: [^,]+, id: (\\d+)\\)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsRange = NSRange(description.startIndex..<description.endIndex, in: description)
            if let match = regex.firstMatch(in: description, options: [], range: nsRange) {
                if let idRange = Range(match.range(at: 1), in: description), let id = Int32(description[idRange]) {
                    return NSNumber(value: id)
                }
            }
        }
        
        // NEW PATTERN: Matches "id: 0:id(rawValue: 8310923053):0_11639"
        let rawValuePattern = "rawValue: \\d+\\):\\d+_(\\d+)"
        if let regex = try? NSRegularExpression(pattern: rawValuePattern, options: []) {
            let nsRange = NSRange(description.startIndex..<description.endIndex, in: description)
            if let match = regex.firstMatch(in: description, options: [], range: nsRange) {
                if let idRange = Range(match.range(at: 1), in: description), let id = Int32(description[idRange]) {
                    return NSNumber(value: id)
                }
            }
        }
        
        let fallbackPattern = "messageId: (\\d+)"
        if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: []) {
            let nsRange = NSRange(description.startIndex..<description.endIndex, in: description)
            if let match = regex.firstMatch(in: description, options: [], range: nsRange) {
                if let idRange = Range(match.range(at: 1), in: description), let id = Int32(description[idRange]) {
                    return NSNumber(value: id)
                }
            }
        }
        
        // Also try standard mirror reflection
        let mirror = Mirror(reflecting: item)
        for child in mirror.children {
            if child.label == "message" || child.label == "firstMessage" || child.label == "content" {
                if child.label == "content" {
                    let contentMirror = Mirror(reflecting: child.value)
                    for cChild in contentMirror.children {
                        if cChild.label == "firstMessage" || cChild.label == "message" {
                            if let id = extractId(fromMessage: cChild.value) { return id }
                        }
                    }
                }
                if let id = extractId(fromMessage: child.value) { return id }
            }
        }
        
        // Safe shallow dump. Limits depth to 5 to completely avoid the infinite recursion lag,
        // but goes deep enough to print the MessageId which is usually at depth 1 to 4.
        var dumpStr = ""
        dump(item, to: &dumpStr, maxDepth: 5, maxItems: 200)
        
        let dumpPattern = "MessageId.*?id: (\\d+)"
        if let regex = try? NSRegularExpression(pattern: dumpPattern, options: [.dotMatchesLineSeparators]) {
            let nsRange = NSRange(dumpStr.startIndex..<dumpStr.endIndex, in: dumpStr)
            if let match = regex.firstMatch(in: dumpStr, options: [], range: nsRange) {
                if let idRange = Range(match.range(at: 1), in: dumpStr), let id = Int32(dumpStr[idRange]) {
                    return NSNumber(value: id)
                }
            }
        }
        
        let dumpRawValuePattern = "rawValue: \\d+\\):\\d+_(\\d+)"
        if let regex = try? NSRegularExpression(pattern: dumpRawValuePattern, options: []) {
            let nsRange = NSRange(dumpStr.startIndex..<dumpStr.endIndex, in: dumpStr)
            if let match = regex.firstMatch(in: dumpStr, options: [], range: nsRange) {
                if let idRange = Range(match.range(at: 1), in: dumpStr), let id = Int32(dumpStr[idRange]) {
                    return NSNumber(value: id)
                }
            }
        }
        
        return nil
    }

    private static func extractId(fromMessage msg: Any) -> NSNumber? {
        let msgMirror = Mirror(reflecting: msg)
        for msgChild in msgMirror.children {
            if msgChild.label == "id" {
                let idMirror = Mirror(reflecting: msgChild.value)
                for idChild in idMirror.children {
                    if idChild.label == "id", let idVal = idChild.value as? Int32 {
                        return NSNumber(value: idVal)
                    }
                }
            }
        }
        return nil
    }

    /// Dynamically extracts message ID from a ChatMessageBubbleItemNode
    @objc static func getMessageIdFromNode(_ node: Any) -> NSNumber? {
        var currentMirror: Mirror? = Mirror(reflecting: node)
        while let mirror = currentMirror {
            for child in mirror.children {
                if child.label == "item" {
                    if let id = getMessageId(from: child.value) {
                        return id
                    }
                }
            }
            currentMirror = mirror.superclassMirror
        }
        
        // If reflection completely fails to find 'item', try parsing the node's string description.
        // This is 100% safe (unlike dump) and might reveal the message ID if the node implements CustomStringConvertible.
        let nodeDesc = String(describing: node)
        let pattern = "MessageId\\(peerId: [^,]+, namespace: [^,]+, id: (\\d+)\\)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsRange = NSRange(nodeDesc.startIndex..<nodeDesc.endIndex, in: nodeDesc)
            if let match = regex.firstMatch(in: nodeDesc, options: [], range: nsRange) {
                if let idRange = Range(match.range(at: 1), in: nodeDesc), let id = Int32(nodeDesc[idRange]) {
                    return NSNumber(value: id)
                }
            }
        }
        
        let fallbackPattern = "messageId: (\\d+)"
        if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: []) {
            let nsRange = NSRange(nodeDesc.startIndex..<nodeDesc.endIndex, in: nodeDesc)
            if let match = regex.firstMatch(in: nodeDesc, options: [], range: nsRange) {
                if let idRange = Range(match.range(at: 1), in: nodeDesc), let id = Int32(nodeDesc[idRange]) {
                    return NSNumber(value: id)
                }
            }
        }
        
        return nil
    }

    @objc static func getDebugDumpFromNode(_ node: Any) -> NSString {
        var currentMirror: Mirror? = Mirror(reflecting: node)
        while let mirror = currentMirror {
            for child in mirror.children {
                if child.label == "item" {
                    let item = child.value
                    var dumpStr = ""
                    dump(item, to: &dumpStr, maxDepth: 5, maxItems: 200)
                    return NSString(string: dumpStr)
                }
            }
            currentMirror = mirror.superclassMirror
        }
        return NSString(string: "ITEM NOT FOUND IN MIRROR")
    }

    @objc static func getPeerIdFromNode(_ node: Any) -> NSNumber? {
        // Try to sniff sharedContext from any node that might have it
        if sharedContext == nil, let obj = node as? NSObject {
            if obj.responds(to: NSSelectorFromString("context")), let ctx = obj.value(forKey: "context") {
                sharedContext = ctx
            }
        }

        // Try KVC first
        if let obj = node as? NSObject {
            for key in ["peer", "peerId", "_peer", "_peerId", "id"] {
                if obj.responds(to: NSSelectorFromString(key)), let val = obj.value(forKey: key) {
                    if let pid = extractId(fromPeer: val) { return pid }
                    if let pid = extractId(fromPeerId: val) { return pid }
                }
            }
        }

        // Try Mirror
        var currentMirror: Mirror? = Mirror(reflecting: node)
        while let mirror = currentMirror {
            for child in mirror.children {
                let label = child.label ?? ""
                if ["peer", "_peer", "peerId", "_peerId", "id"].contains(label) {
                    if let pid = extractId(fromPeer: child.value) { return pid }
                    if let pid = extractId(fromPeerId: child.value) { return pid }
                } else if label == "state" {
                    let stateMirror = Mirror(reflecting: child.value)
                    for stateChild in stateMirror.children {
                        if stateChild.label == "peer" || stateChild.label == "peerId" {
                            if let pid = extractId(fromPeer: stateChild.value) { return pid }
                        }
                    }
                }
            }
            currentMirror = mirror.superclassMirror
        }
        
        // NUCLEAR FALLBACK: Regex on full object description
        let fullDesc = String(describing: node)
        if let pid = extractId(fromPeer: fullDesc) { return pid }
        
        return nil
    }

    private static func extractId(fromPeer peer: Any) -> NSNumber? {
        let desc = String(describing: peer)
        if let range = desc.range(of: "(id|userId|channelId):\\s*(-?\\d+)", options: .regularExpression) {
            let match = desc[range]
            if let idRange = match.range(of: "-?\\d+", options: .regularExpression) {
                if let idVal = Int64(match[idRange]) { return NSNumber(value: idVal) }
            }
        }

        // Try direct access if it's an AnyObject
        if let obj = peer as? NSObject {
            if obj.responds(to: NSSelectorFromString("id")), let pid = obj.value(forKey: "id") {
                return extractId(fromPeerId: pid)
            }
        }

        let peerMirror = Mirror(reflecting: peer)
        for peerChild in peerMirror.children {
            if peerChild.label == "id" {
                return extractId(fromPeerId: peerChild.value)
            }
        }
        return nil
    }

    private static func extractId(fromPeerId pid: Any) -> NSNumber? {
        if let idVal = pid as? Int64 { return NSNumber(value: idVal) }
        if let idVal = pid as? Int32 { return NSNumber(value: Int64(idVal)) }
        
        let desc = String(describing: pid)
        if let range = desc.range(of: "-?\\d+", options: .regularExpression) {
            if let idVal = Int64(desc[range]) {
                return NSNumber(value: idVal)
            }
        }

        let pidMirror = Mirror(reflecting: pid)
        for pidChild in pidMirror.children {
             if pidChild.label == "id" || pidChild.label == "_value" || pidChild.label == "value" {
                 if let idVal = pidChild.value as? Int64 { return NSNumber(value: idVal) }
                 if let idVal = pidChild.value as? Int32 { return NSNumber(value: Int64(idVal)) }
             }
        }
        return nil
    }

    @objc static func getCurrentUserId() -> NSNumber? {
        if let context = sharedContext {
            let mirror = Mirror(reflecting: context)
            for child in mirror.children {
                if child.label == "account" {
                    let accMirror = Mirror(reflecting: child.value)
                    for accChild in accMirror.children {
                        if accChild.label == "peerId" {
                            return extractId(fromPeerId: accChild.value)
                        }
                    }
                }
            }
        }
        let savedId = UserDefaults.standard.integer(forKey: "LeadLastKnownUserId")
        if savedId != 0 { return NSNumber(value: Int64(savedId)) }
        return nil
    }

    @objc static func isDeleted(_ msgId: NSNumber) -> Bool {
        return deletedIds.contains(msgId.int32Value)
    }

    // Prepend 🗑️ to each message whose ID is in the deleted set.
    private static func applyDeletedIndicator(to msgs: [Api.Message]) -> (messages: [Api.Message], changed: Bool) {
        let ids = deletedIds
        guard !ids.isEmpty else { return (msgs, false) }
        var changed = false
        let result = msgs.map { apiMsg -> Api.Message in
            guard case let .message(data) = apiMsg,
                  ids.contains(data.id),
                  !data.message.hasPrefix("🗑️") else {
                return apiMsg
            }
            changed = true
            return .message(Api.Message.Cons_message(
                flags: data.flags, flags2: data.flags2, id: data.id, fromId: data.fromId,
                fromBoostsApplied: data.fromBoostsApplied, fromRank: data.fromRank, peerId: data.peerId,
                savedPeerId: data.savedPeerId, fwdFrom: data.fwdFrom,
                viaBotId: data.viaBotId, viaBusinessBotId: data.viaBusinessBotId,
                guestchatViaFrom: data.guestchatViaFrom,
                replyTo: data.replyTo, date: data.date,
                message: "🗑️ " + data.message,
                media: data.media, replyMarkup: data.replyMarkup, entities: data.entities,
                views: data.views, forwards: data.forwards, replies: data.replies,
                editDate: data.editDate, postAuthor: data.postAuthor, groupedId: data.groupedId,
                reactions: data.reactions, restrictionReason: data.restrictionReason,
                ttlPeriod: data.ttlPeriod, quickReplyShortcutId: data.quickReplyShortcutId,
                effect: data.effect, factcheck: data.factcheck,
                reportDeliveryUntilDate: data.reportDeliveryUntilDate,
                paidMessageStars: data.paidMessageStars,
                suggestedPost: data.suggestedPost, scheduleRepeatPeriod: data.scheduleRepeatPeriod,
                summaryFromLanguage: data.summaryFromLanguage
            ))
        }
        return (result, changed)
    }
    // IDs of messages that originally had a self-destruct timer (one-time media ttlSeconds)
    private static var selfDestructingMessageIds = Set<Int32>()

    @objc static func isMessageSelfDestructing(_ msgId: NSNumber) -> Bool {
        return selfDestructingMessageIds.contains(msgId.int32Value)
    }

    // IDs of messages in chats with auto-delete (ttlPeriod)
    private static var autoDeleteMessageIds = Set<Int32>()

    @objc static func isMessageAutoDelete(_ msgId: NSNumber) -> Bool {
        return autoDeleteMessageIds.contains(msgId.int32Value)
    }

    private static func stripTTLMedia(_ media: Api.MessageMedia, messageId: Int32) -> Api.MessageMedia {
        guard UserDefaults.standard.bool(forKey: "LeadAntiSelfDestruct") else { return media }
        switch media {
        case let .messageMediaPhoto(data):
            if data.ttlSeconds != nil || (Int(data.flags) & Int(1 << 2)) != 0 {
                selfDestructingMessageIds.insert(messageId)
            }
            // Clear ttlSeconds (bit 2) and spoiler (bit 3) and media_unread (bit 5) just in case
            return .messageMediaPhoto(Api.MessageMedia.Cons_messageMediaPhoto(flags: data.flags & ~(1 << 2) & ~(1 << 3) & ~(1 << 5), photo: data.photo, ttlSeconds: nil, video: data.video))
        case let .messageMediaDocument(data):
            if data.ttlSeconds != nil || (Int(data.flags) & Int(1 << 2)) != 0 {
                selfDestructingMessageIds.insert(messageId)
            }
            // Clear ttlSeconds (bit 2) and spoiler (bit 3) and video stuff
            return .messageMediaDocument(Api.MessageMedia.Cons_messageMediaDocument(flags: data.flags & ~(1 << 2) & ~(1 << 3), document: data.document, altDocuments: data.altDocuments, videoCover: data.videoCover, videoTimestamp: data.videoTimestamp, ttlSeconds: nil))
        default:
            return media
        }
    }

    private static var isNoForwardsBypassActive: Bool {
        if UserDefaults.standard.object(forKey: "disableForwardRestriction") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "disableForwardRestriction")
    }

    private static func stripNoForwards(_ chat: Api.Chat) -> (Api.Chat, Bool) {
        guard isNoForwardsBypassActive ||
              UserDefaults.standard.bool(forKey: "LeadAntiSelfDestruct") ||
              UserDefaults.standard.bool(forKey: "LeadAntiAutoDelete") else { return (chat, false) }
              
        switch chat {
        case let .channel(data):
            // Bit 16 is standard, bit 27 is used in neutralizedPayload, bit 5 is restricted
            // Bit 27: copyProtectionEnabled
            let mask: Int32 = ~( (1 << 16) | (1 << 27) | (1 << 5) )
            
            let newFlags = data.flags & mask
            let newFlags2 = data.flags2 & mask
            
            if newFlags == data.flags && newFlags2 == data.flags2 {
                return (chat, false)
            }

            return (.channel(Api.Chat.Cons_channel(
                flags: newFlags,
                flags2: newFlags2,
                id: data.id, accessHash: data.accessHash, title: data.title,
                username: data.username, photo: data.photo, date: data.date,
                restrictionReason: data.restrictionReason, adminRights: data.adminRights,
                bannedRights: data.bannedRights, defaultBannedRights: data.defaultBannedRights,
                participantsCount: data.participantsCount, usernames: data.usernames,
                storiesMaxId: data.storiesMaxId, color: data.color, profileColor: data.profileColor,
                emojiStatus: data.emojiStatus, level: data.level, subscriptionUntilDate: data.subscriptionUntilDate,
                botVerificationIcon: data.botVerificationIcon, sendPaidMessagesStars: data.sendPaidMessagesStars,
                linkedMonoforumId: data.linkedMonoforumId
            )), true)
        case let .chat(data):
            // Bit 14/16/25 are used for restrictions
            let mask: Int32 = ~( (1 << 14) | (1 << 16) | (1 << 25) )
            let newFlags = data.flags & mask
            if newFlags == data.flags {
                return (chat, false)
            }
            return (.chat(Api.Chat.Cons_chat(
                flags: newFlags,
                id: data.id, title: data.title, photo: data.photo,
                participantsCount: data.participantsCount, date: data.date, version: data.version,
                migratedTo: data.migratedTo, adminRights: data.adminRights,
                defaultBannedRights: data.defaultBannedRights
            )), true)
        default:
            return (chat, false)
        }
    }

    private static func stripNoForwardsFromChats(_ chats: [Api.Chat]) -> ([Api.Chat], Bool) {
        var modified = false
        let newChats = chats.map { chat -> Api.Chat in
            let (stripped, changed) = stripNoForwards(chat)
            if changed {
                modified = true
            }
            return stripped
        }
        return (newChats, modified)
    }
    
    private static func stripNoForwardsFromFullChat(_ chatFull: Api.ChatFull) -> (Api.ChatFull, Bool) {
        guard isNoForwardsBypassActive ||
              UserDefaults.standard.bool(forKey: "LeadAntiSelfDestruct") ||
              UserDefaults.standard.bool(forKey: "LeadAntiAutoDelete") else { return (chatFull, false) }
              
        switch chatFull {
        case let .channelFull(data):
            // Bit 10 is noforwards in some versions, clearing multiple bits for safety
            let mask: Int32 = ~( (1 << 10) | (1 << 27) | (1 << 16) | (1 << 26) )
            let newFlags = data.flags & mask
            let newFlags2 = data.flags2 & mask
            
            if newFlags == data.flags && newFlags2 == data.flags2 {
                return (chatFull, false)
            }
            
            return (.channelFull(Api.ChatFull.Cons_channelFull(
                flags: newFlags, flags2: newFlags2, id: data.id, about: data.about,
                participantsCount: data.participantsCount, adminsCount: data.adminsCount,
                kickedCount: data.kickedCount, bannedCount: data.bannedCount, onlineCount: data.onlineCount,
                readInboxMaxId: data.readInboxMaxId, readOutboxMaxId: data.readOutboxMaxId,
                unreadCount: data.unreadCount, chatPhoto: data.chatPhoto, notifySettings: data.notifySettings,
                exportedInvite: data.exportedInvite, botInfo: data.botInfo, migratedFromChatId: data.migratedFromChatId,
                migratedFromMaxId: data.migratedFromMaxId, pinnedMsgId: data.pinnedMsgId, stickerset: data.stickerset,
                availableMinId: data.availableMinId, folderId: data.folderId, linkedChatId: data.linkedChatId,
                location: data.location, slowmodeSeconds: data.slowmodeSeconds, slowmodeNextSendDate: data.slowmodeNextSendDate,
                statsDc: data.statsDc, pts: data.pts, call: data.call, ttlPeriod: data.ttlPeriod,
                pendingSuggestions: data.pendingSuggestions, groupcallDefaultJoinAs: data.groupcallDefaultJoinAs,
                themeEmoticon: data.themeEmoticon, requestsPending: data.requestsPending,
                recentRequesters: data.recentRequesters, defaultSendAs: data.defaultSendAs,
                availableReactions: data.availableReactions, reactionsLimit: data.reactionsLimit,
                stories: data.stories, wallpaper: data.wallpaper, boostsApplied: data.boostsApplied,
                boostsUnrestrict: data.boostsUnrestrict, emojiset: data.emojiset,
                botVerification: data.botVerification, stargiftsCount: data.stargiftsCount,
                sendPaidMessagesStars: data.sendPaidMessagesStars, mainTab: data.mainTab
            )), true)
        case let .chatFull(data):
            let mask: Int32 = ~( (1 << 10) | (1 << 27) | (1 << 16) | (1 << 26) )
            let newFlags = data.flags & mask
            if newFlags == data.flags {
                return (chatFull, false)
            }
            return (.chatFull(Api.ChatFull.Cons_chatFull(
                flags: newFlags, id: data.id, about: data.about, participants: data.participants,
                chatPhoto: data.chatPhoto, notifySettings: data.notifySettings, exportedInvite: data.exportedInvite,
                botInfo: data.botInfo, pinnedMsgId: data.pinnedMsgId, folderId: data.folderId, call: data.call,
                ttlPeriod: data.ttlPeriod, groupcallDefaultJoinAs: data.groupcallDefaultJoinAs,
                themeEmoticon: data.themeEmoticon, requestsPending: data.requestsPending,
                recentRequesters: data.recentRequesters, availableReactions: data.availableReactions,
                reactionsLimit: data.reactionsLimit
            )), true)
        }
    }

    private static func shiftEntities(_ entities: [Api.MessageEntity]?, by offset: Int32) -> [Api.MessageEntity] {
        guard let entities = entities else { return [] }
        return entities.map { entity in
            switch entity {
            case let .messageEntityUnknown(d): return .messageEntityUnknown(Api.MessageEntity.Cons_messageEntityUnknown(offset: d.offset + offset, length: d.length))
            case let .messageEntityMention(d): return .messageEntityMention(Api.MessageEntity.Cons_messageEntityMention(offset: d.offset + offset, length: d.length))
            case let .messageEntityHashtag(d): return .messageEntityHashtag(Api.MessageEntity.Cons_messageEntityHashtag(offset: d.offset + offset, length: d.length))
            case let .messageEntityBotCommand(d): return .messageEntityBotCommand(Api.MessageEntity.Cons_messageEntityBotCommand(offset: d.offset + offset, length: d.length))
            case let .messageEntityUrl(d): return .messageEntityUrl(Api.MessageEntity.Cons_messageEntityUrl(offset: d.offset + offset, length: d.length))
            case let .messageEntityEmail(d): return .messageEntityEmail(Api.MessageEntity.Cons_messageEntityEmail(offset: d.offset + offset, length: d.length))
            case let .messageEntityBold(d): return .messageEntityBold(Api.MessageEntity.Cons_messageEntityBold(offset: d.offset + offset, length: d.length))
            case let .messageEntityItalic(d): return .messageEntityItalic(Api.MessageEntity.Cons_messageEntityItalic(offset: d.offset + offset, length: d.length))
            case let .messageEntityCode(d): return .messageEntityCode(Api.MessageEntity.Cons_messageEntityCode(offset: d.offset + offset, length: d.length))
            case let .messageEntityPre(d): return .messageEntityPre(Api.MessageEntity.Cons_messageEntityPre(offset: d.offset + offset, length: d.length, language: d.language))
            case let .messageEntityTextUrl(d): return .messageEntityTextUrl(Api.MessageEntity.Cons_messageEntityTextUrl(offset: d.offset + offset, length: d.length, url: d.url))
            case let .messageEntityMentionName(d): return .messageEntityMentionName(Api.MessageEntity.Cons_messageEntityMentionName(offset: d.offset + offset, length: d.length, userId: d.userId))
            case let .messageEntityPhone(d): return .messageEntityPhone(Api.MessageEntity.Cons_messageEntityPhone(offset: d.offset + offset, length: d.length))
            case let .messageEntityCashtag(d): return .messageEntityCashtag(Api.MessageEntity.Cons_messageEntityCashtag(offset: d.offset + offset, length: d.length))
            case let .messageEntityUnderline(d): return .messageEntityUnderline(Api.MessageEntity.Cons_messageEntityUnderline(offset: d.offset + offset, length: d.length))
            case let .messageEntityStrike(d): return .messageEntityStrike(Api.MessageEntity.Cons_messageEntityStrike(offset: d.offset + offset, length: d.length))
            case let .messageEntityBlockquote(d): return .messageEntityBlockquote(Api.MessageEntity.Cons_messageEntityBlockquote(flags: d.flags, offset: d.offset + offset, length: d.length))
            case let .messageEntityBankCard(d): return .messageEntityBankCard(Api.MessageEntity.Cons_messageEntityBankCard(offset: d.offset + offset, length: d.length))
            case let .messageEntitySpoiler(d): return .messageEntitySpoiler(Api.MessageEntity.Cons_messageEntitySpoiler(offset: d.offset + offset, length: d.length))
            case let .messageEntityCustomEmoji(d): return .messageEntityCustomEmoji(Api.MessageEntity.Cons_messageEntityCustomEmoji(offset: d.offset + offset, length: d.length, documentId: d.documentId))
            default: return entity
            }
        }
    }

    private static func applyTTLIndicator(message: String, entities: [Api.MessageEntity]?, shouldApply: Bool) -> (String, [Api.MessageEntity]?) {
        var newMessageText = message
        var newEntities = entities ?? []
        
        if shouldApply {
            let marker = "dissapearing message "
            if !newMessageText.contains("dissapearing message") && !newMessageText.hasPrefix("🗑️") {
                 // Remove ⏱️ emoji if it was added in previous turns
                 if newMessageText.hasPrefix("⏱️ ") {
                     newMessageText.removeFirst(3)
                 }
                 
                 let markerLen = Int32(marker.count)
                 newEntities = shiftEntities(newEntities, by: markerLen)
                 
                 // Add italic and spoiler entities for the marker
                 let markerTextLen = Int32(marker.count - 1)
                 newEntities.insert(.messageEntityItalic(Api.MessageEntity.Cons_messageEntityItalic(offset: 0, length: markerTextLen)), at: 0)
                 newEntities.insert(.messageEntitySpoiler(Api.MessageEntity.Cons_messageEntitySpoiler(offset: 0, length: markerTextLen)), at: 0)
                 
                 newMessageText = marker + newMessageText
            }
        }
        return (newMessageText, newEntities)
    }

    private static func stripTTLMessage(_ apiMsg: Api.Message) -> (Api.Message, Bool) {
        guard isNoForwardsBypassActive || 
              UserDefaults.standard.bool(forKey: "LeadAntiSelfDestruct") else { return (apiMsg, false) }
        guard case let .message(data) = apiMsg else {
            return (apiMsg, false)
        }
        
        var isDestructing = false
        if data.ttlPeriod != nil || (Int(data.flags) & Int(1 << 25)) != 0 {
            isDestructing = true
            selfDestructingMessageIds.insert(data.id)
        }

        let newMedia = data.media.map { stripTTLMedia($0, messageId: data.id) }
        
        let isMediaDestructing = selfDestructingMessageIds.contains(data.id)
        let shouldStripFlags = isDestructing || isMediaDestructing
        
        let (newMessageText, newEntities) = applyTTLIndicator(message: data.message, entities: data.entities, shouldApply: shouldStripFlags)
        
        var newFlags = shouldStripFlags ? (data.flags & ~(1 << 25) & ~(1 << 5)) : data.flags
        var newFlags2 = data.flags2
        
        // Strip noforwards if requested
        if isNoForwardsBypassActive || 
           UserDefaults.standard.bool(forKey: "LeadAntiSelfDestruct") {
            // Bit 14 is standard, bit 26 is used in neutralizePayload
            let mask: Int32 = ~( (1 << 14) | (1 << 26) )
            newFlags &= mask
            newFlags2 &= mask
        }
        
        // Set entities flag (bit 7) if we have entities
        if (newEntities?.count ?? 0) > 0 {
            newFlags |= (1 << 7)
        }
        
        let resultMsg = Api.Message.message(Api.Message.Cons_message(
            flags: newFlags, flags2: newFlags2, id: data.id, fromId: data.fromId,
            fromBoostsApplied: data.fromBoostsApplied, fromRank: data.fromRank, peerId: data.peerId,
            savedPeerId: data.savedPeerId, fwdFrom: data.fwdFrom,
            viaBotId: data.viaBotId, viaBusinessBotId: data.viaBusinessBotId,
            guestchatViaFrom: data.guestchatViaFrom,
            replyTo: data.replyTo, date: data.date,
            message: newMessageText,
            media: newMedia, replyMarkup: data.replyMarkup, entities: newEntities,
            views: data.views, forwards: data.forwards, replies: data.replies,
            editDate: data.editDate, postAuthor: data.postAuthor, groupedId: data.groupedId,
            reactions: data.reactions, restrictionReason: data.restrictionReason,
            ttlPeriod: shouldStripFlags ? nil : data.ttlPeriod, quickReplyShortcutId: data.quickReplyShortcutId,
            effect: data.effect, factcheck: data.factcheck,
            reportDeliveryUntilDate: data.reportDeliveryUntilDate,
            paidMessageStars: data.paidMessageStars,
            suggestedPost: data.suggestedPost, scheduleRepeatPeriod: data.scheduleRepeatPeriod,
            summaryFromLanguage: data.summaryFromLanguage
        ))
        
        let modified = (newFlags != data.flags) || (newMessageText != data.message) || (newEntities?.count != data.entities?.count) || (newFlags2 != data.flags2)
        
        return (resultMsg, modified)
    }

    private static func stripTTLUpdates(_ updates: [Api.Update]) -> ([Api.Update], Bool) {
        var modified = false
        let result = updates.map { update -> Api.Update in
            let (stripped, changed) = stripTTLUpdate(update)
            if changed {
                modified = true
            }
            return stripped
        }
        return (result, modified)
    }

    private static func stripTTLUpdate(_ update: Api.Update) -> (Api.Update, Bool) {
        switch update {
        case let .updateNewMessage(data):
            let (strippedMsg, changed) = stripTTLMessage(data.message)
            if !changed {
                return (update, false)
            }
            return (.updateNewMessage(Api.Update.Cons_updateNewMessage(message: strippedMsg, pts: data.pts, ptsCount: data.ptsCount)), true)
        case let .updateNewChannelMessage(data):
            let (strippedMsg, changed) = stripTTLMessage(data.message)
            if !changed {
                return (update, false)
            }
            return (.updateNewChannelMessage(Api.Update.Cons_updateNewChannelMessage(message: strippedMsg, pts: data.pts, ptsCount: data.ptsCount)), true)
        default:
            return (update, false)
        }
    }

    @objc static func stripAntiSelfDestruct(_ data: NSData) -> NSData? {
        let isAntiSelfDestruct = UserDefaults.standard.bool(forKey: "LeadAntiSelfDestruct")
        let isNoForwardsBypass = isNoForwardsBypassActive
        
        guard isAntiSelfDestruct || isNoForwardsBypass else { return nil }
        let buffer = Buffer(data: data as Data)
        let reader = BufferReader(buffer)
        guard let signature = reader.readInt32() else { return nil }
        
        if signature == 0x73f1f8dc { // msg_container
            guard let count = reader.readInt32() else { return nil }
            let outBuf = Buffer()
            outBuf.appendInt32(0x73f1f8dc)
            outBuf.appendInt32(count)
            
            var modifiedContainer = false
            for _ in 0..<count {
                guard let msg_id = reader.readInt64(),
                      let seqno = reader.readInt32(),
                      let bytes = reader.readInt32() else { return nil }
                
                guard let bodyBuffer = reader.readBuffer(Int(bytes)) else { return nil }
                let bodyData = bodyBuffer.makeData() as NSData
                
                var newBodyData = bodyData
                if let stripped = stripAntiSelfDestruct(newBodyData) {
                    newBodyData = stripped
                    modifiedContainer = true
                }
                
                outBuf.appendInt64(msg_id)
                outBuf.appendInt32(seqno)
                outBuf.appendInt32(Int32(newBodyData.length))
                outBuf.appendBytes(newBodyData.bytes, length: UInt(newBodyData.length))
            }
            
            return modifiedContainer ? (outBuf.makeData() as NSData) : nil
        }
        // Do not reset the reader, because Api.parse(reader, signature:) expects the reader to be at offset 4
        guard let result = Api.parse(reader, signature: signature) else { return nil }
        
        var modified = false
        var newResult: Any = result

        if let updates = result as? Api.Updates {
            switch updates {
            case let .updates(data):
                let (stripped, anyStripped) = stripTTLUpdates(data.updates)
                let (newChats, anyChatsChanged) = stripNoForwardsFromChats(data.chats)
                if anyStripped || anyChatsChanged {
                    newResult = Api.Updates.updates(Api.Updates.Cons_updates(updates: stripped, users: data.users, chats: newChats, date: data.date, seq: data.seq))
                    modified = true
                }
            case let .updateShort(data):
                let (stripped, changed) = stripTTLUpdate(data.update)
                if changed {
                    newResult = Api.Updates.updateShort(Api.Updates.Cons_updateShort(update: stripped, date: data.date))
                    modified = true
                }
            case let .updateShortMessage(data):
                var isDestructing = false
                if data.ttlPeriod != nil || (Int(data.flags) & Int(1 << 25)) != 0 {
                    isDestructing = true
                    selfDestructingMessageIds.insert(data.id)
                }
                var newFlags = data.flags
                if isDestructing {
                    newFlags &= ~(1 << 25)
                    newFlags &= ~(1 << 5)
                }

                // Only clear noforwards flags if they are actually set —
                // unconditionally clearing them on every message caused
                // pересериализацию обычных сообщений и ломало rich notifications.
                let hasNoForwards = (Int(data.flags) & (1 << 14)) != 0 || (Int(data.flags) & (1 << 26)) != 0
                if hasNoForwards && (isNoForwardsBypassActive ||
                   UserDefaults.standard.bool(forKey: "LeadAntiSelfDestruct")) {
                    newFlags &= ~(1 << 14)
                    newFlags &= ~(1 << 26)
                }

                let (newMessageText, newEntities) = applyTTLIndicator(message: data.message, entities: data.entities, shouldApply: isDestructing)

                if newFlags != data.flags || newMessageText != data.message || (newEntities?.count ?? 0) != (data.entities?.count ?? 0) {
                    if (newEntities?.count ?? 0) > 0 {
                        newFlags |= (1 << 7)
                    }
                    newResult = Api.Updates.updateShortMessage(Api.Updates.Cons_updateShortMessage(flags: newFlags, id: data.id, userId: data.userId, message: newMessageText, pts: data.pts, ptsCount: data.ptsCount, date: data.date, fwdFrom: data.fwdFrom, viaBotId: data.viaBotId, replyTo: data.replyTo, entities: newEntities, ttlPeriod: isDestructing ? nil : data.ttlPeriod))
                    modified = true
                }
            case let .updateShortChatMessage(data):
                var isDestructing = false
                if data.ttlPeriod != nil || (Int(data.flags) & Int(1 << 25)) != 0 {
                    isDestructing = true
                    selfDestructingMessageIds.insert(data.id)
                }
                var newFlags = data.flags
                if isDestructing {
                    newFlags &= ~(1 << 25)
                    newFlags &= ~(1 << 5)
                }

                // Only clear noforwards flags if they are actually set
                let hasNoForwardsChatMsg = (Int(data.flags) & (1 << 14)) != 0 || (Int(data.flags) & (1 << 26)) != 0
                if hasNoForwardsChatMsg && (isNoForwardsBypassActive ||
                   UserDefaults.standard.bool(forKey: "LeadAntiSelfDestruct")) {
                    newFlags &= ~(1 << 14)
                    newFlags &= ~(1 << 26)
                }
                
                let (newMessageText, newEntities) = applyTTLIndicator(message: data.message, entities: data.entities, shouldApply: isDestructing)
                
                if newFlags != data.flags || newMessageText != data.message || (newEntities?.count ?? 0) != (data.entities?.count ?? 0) {
                    if (newEntities?.count ?? 0) > 0 {
                        newFlags |= (1 << 7)
                    }
                    newResult = Api.Updates.updateShortChatMessage(Api.Updates.Cons_updateShortChatMessage(flags: newFlags, id: data.id, fromId: data.fromId, chatId: data.chatId, message: newMessageText, pts: data.pts, ptsCount: data.ptsCount, date: data.date, fwdFrom: data.fwdFrom, viaBotId: data.viaBotId, replyTo: data.replyTo, entities: newEntities, ttlPeriod: isDestructing ? nil : data.ttlPeriod))
                    modified = true
                }
            case let .updateShortSentMessage(data):
                let newMedia = data.media.map { stripTTLMedia($0, messageId: data.id) }
                let isMediaDestructing = selfDestructingMessageIds.contains(data.id) || data.ttlPeriod != nil || (Int(data.flags) & Int(1 << 25)) != 0
                let newFlags = isMediaDestructing ? (data.flags & ~(1 << 25) & ~(1 << 5)) : data.flags
                
                if newFlags != data.flags || isMediaDestructing {
                    newResult = Api.Updates.updateShortSentMessage(Api.Updates.Cons_updateShortSentMessage(flags: newFlags, id: data.id, pts: data.pts, ptsCount: data.ptsCount, date: data.date, media: newMedia, entities: data.entities, ttlPeriod: isMediaDestructing ? nil : data.ttlPeriod))
                    modified = true
                }
            case let .updatesCombined(data):
                let (stripped, anyStripped) = stripTTLUpdates(data.updates)
                let (newChats, anyChatsChanged) = stripNoForwardsFromChats(data.chats)
                if anyStripped || anyChatsChanged {
                    newResult = Api.Updates.updatesCombined(Api.Updates.Cons_updatesCombined(updates: stripped, users: data.users, chats: newChats, date: data.date, seqStart: data.seqStart, seq: data.seq))
                    modified = true
                }
            default:
                break
            }
        } else if let msgs = result as? Api.messages.Messages {
            switch msgs {
            case let .messages(data):
                let (withInd, changedInd) = applyDeletedIndicator(to: data.messages)
                var changedMsgs = false
                let newMessages = withInd.map { msg -> Api.Message in
                    let (stripped, changed) = stripTTLMessage(msg)
                    if changed { changedMsgs = true }
                    return stripped
                }
                let (newChats, changedChats) = stripNoForwardsFromChats(data.chats)
                if changedInd || changedMsgs || changedChats {
                    newResult = Api.messages.Messages.messages(Api.messages.Messages.Cons_messages(messages: newMessages, topics: data.topics, chats: newChats, users: data.users))
                    modified = true
                }
            case let .messagesSlice(data):
                let (withInd, changedInd) = applyDeletedIndicator(to: data.messages)
                var changedMsgs = false
                let newMessages = withInd.map { msg -> Api.Message in
                    let (stripped, changed) = stripTTLMessage(msg)
                    if changed { changedMsgs = true }
                    return stripped
                }
                let (newChats, changedChats) = stripNoForwardsFromChats(data.chats)
                if changedInd || changedMsgs || changedChats {
                    newResult = Api.messages.Messages.messagesSlice(Api.messages.Messages.Cons_messagesSlice(flags: data.flags, count: data.count, nextRate: data.nextRate, offsetIdOffset: data.offsetIdOffset, searchFlood: data.searchFlood, messages: newMessages, topics: data.topics, chats: newChats, users: data.users))
                    modified = true
                }
            case let .channelMessages(data):
                let (withInd, changedInd) = applyDeletedIndicator(to: data.messages)
                var changedMsgs = false
                let newMessages = withInd.map { msg -> Api.Message in
                    let (stripped, changed) = stripTTLMessage(msg)
                    if changed { changedMsgs = true }
                    return stripped
                }
                let (newChats, changedChats) = stripNoForwardsFromChats(data.chats)
                if changedInd || changedMsgs || changedChats {
                    newResult = Api.messages.Messages.channelMessages(Api.messages.Messages.Cons_channelMessages(flags: data.flags, pts: data.pts, count: data.count, offsetIdOffset: data.offsetIdOffset, messages: newMessages, topics: data.topics, chats: newChats, users: data.users))
                    modified = true
                }
            default:
                break
            }
        } else if let chatFull = result as? Api.messages.ChatFull {
            switch chatFull {
            case let .chatFull(data):
                let (newFullChat, changedFull) = stripNoForwardsFromFullChat(data.fullChat)
                let (newChats, changedChats) = stripNoForwardsFromChats(data.chats)
                if changedFull || changedChats {
                    newResult = Api.messages.ChatFull.chatFull(Api.messages.ChatFull.Cons_chatFull(fullChat: newFullChat, chats: newChats, users: data.users))
                    modified = true
                }
            }
        } else if let chats = result as? Api.messages.Chats {
            switch chats {
            case let .chats(data):
                let (newChats, changed) = stripNoForwardsFromChats(data.chats)
                if changed {
                    newResult = Api.messages.Chats.chats(Api.messages.Chats.Cons_chats(chats: newChats))
                    modified = true
                }
            case let .chatsSlice(data):
                let (newChats, changed) = stripNoForwardsFromChats(data.chats)
                if changed {
                    newResult = Api.messages.Chats.chatsSlice(Api.messages.Chats.Cons_chatsSlice(count: data.count, chats: newChats))
                    modified = true
                }
            }
        } else if let update = result as? Api.Update {
            let (stripped, changed) = stripTTLUpdate(update)
            if changed {
                newResult = stripped
                modified = true
            }
        } else if let message = result as? Api.Message {
            let (stripped, changed) = stripTTLMessage(message)
            if changed {
                newResult = stripped
                modified = true
            }
        } else if let discussion = result as? Api.messages.DiscussionMessage {
            switch discussion {
            case let .discussionMessage(data):
                let (newChats, changedChats) = stripNoForwardsFromChats(data.chats)
                var changedMsgs = false
                let newMessages = data.messages.map { msg -> Api.Message in
                    let (stripped, changed) = stripTTLMessage(msg)
                    if changed { changedMsgs = true }
                    return stripped
                }
                if changedChats || changedMsgs {
                    newResult = Api.messages.DiscussionMessage.discussionMessage(Api.messages.DiscussionMessage.Cons_discussionMessage(flags: data.flags, messages: newMessages, maxId: data.maxId, readInboxMaxId: data.readInboxMaxId, readOutboxMaxId: data.readOutboxMaxId, unreadCount: data.unreadCount, chats: newChats, users: data.users))
                    modified = true
                }
            }
        } else if let peerDialogs = result as? Api.messages.PeerDialogs {
            switch peerDialogs {
            case let .peerDialogs(data):
                let (newChats, changedChats) = stripNoForwardsFromChats(data.chats)
                var changedMsgs = false
                let newMessages = data.messages.map { msg -> Api.Message in
                    let (stripped, changed) = stripTTLMessage(msg)
                    if changed { changedMsgs = true }
                    return stripped
                }
                if changedChats || changedMsgs {
                    newResult = Api.messages.PeerDialogs.peerDialogs(Api.messages.PeerDialogs.Cons_peerDialogs(dialogs: data.dialogs, messages: newMessages, chats: newChats, users: data.users, state: data.state))
                    modified = true
                }
            }
        }
        
        if modified {
            let outBuf = Buffer()
            Api.serializeObject(newResult, buffer: outBuf, boxed: true)
            return outBuf.makeData() as NSData
        }
        return nil
    }

    @objc static func handleResponse(_ data: NSData, functionID: NSNumber) -> NSData? {
        // Returns patched data only if something was actually modified.
        // Returning nil means "no change" — caller uses original data as-is.
        return stripAntiSelfDestruct(data)
    }
    // MARK: - Forward Cloning (Universal Forwarding)

    private struct ForwardRequest {
        let fromPeer: Api.InputPeer
        let ids: [Int32]
        let toPeer: Api.InputPeer
    }

    private static func parseForwardRequest(_ data: NSData) -> ForwardRequest? {
        let buffer = Buffer(data: data as Data)
        let reader = BufferReader(buffer)
        guard let signature = reader.readInt32() else { 
            NSLog("[Lead] parseForwardRequest: Failed to read signature")
            return nil 
        }
        
        if signature != 326126204 {
            // NSLog("[Lead] parseForwardRequest: Unexpected signature %d", signature)
            return nil
        }
        
        NSLog("[Lead] parseForwardRequest: Detected forwardMessages")
        
        let _ = reader.readInt32() ?? 0
        
        // fromPeer (boxed)
        guard let fromSig = reader.readInt32(),
              let fromPeer = Api.parse(reader, signature: fromSig) as? Api.InputPeer else { return nil }
              
        // id: [Int32] (Vector)
        guard let vecSig1 = reader.readInt32(), vecSig1 == 481674261,
              let countIds = reader.readInt32() else { return nil }
        var ids: [Int32] = []
        for _ in 0..<countIds {
            if let val = reader.readInt32() { ids.append(val) }
        }
        
        // randomId: [Int64] (Vector)
        guard let vecSig2 = reader.readInt32(), vecSig2 == 481674261,
              let countRand = reader.readInt32() else { return nil }
        for _ in 0..<countRand { reader.skip(8) }
        
        // toPeer (boxed)
        guard let toSig = reader.readInt32(),
              let toPeer = Api.parse(reader, signature: toSig) as? Api.InputPeer else { return nil }
        
        switch toPeer {
        case let .inputPeerUser(data): NSLog("[Lead]   Target User: id=%lld, hash=%lld", data.userId, data.accessHash)
        case let .inputPeerChannel(data): NSLog("[Lead]   Target Channel: id=%lld, hash=%lld", data.channelId, data.accessHash)
        default: break
        }
              
        return ForwardRequest(fromPeer: fromPeer, ids: ids, toPeer: toPeer)
    }

    @objc(handleForwardRequest:)
    static func handleForwardRequest(_ data: NSData) -> Bool {
        NSLog("[Lead] handleForwardRequest called")
        guard let request = parseForwardRequest(data) else { 
            NSLog("[Lead] handleForwardRequest: Failed to parse forward request")
            return false 
        }
        
        let fromId: Int64
        switch request.fromPeer {
        case let .inputPeerChannel(data): fromId = data.channelId
        case let .inputPeerChat(data): fromId = data.chatId
        case let .inputPeerUser(data): fromId = data.userId
        default: fromId = 0
        }
        
        NSLog("[Lead] handleForwardRequest: fromId = \(fromId)")
        // For now, if the setting is ON, we hijack ALL forwards from channels or chats to be safe.
        return fromId != 0
    }

    @objc(createGetMessagesRequest:)
    static func createGetMessagesRequest(fromForward data: NSData) -> NSData? {
        guard let request = parseForwardRequest(data) else { return nil }
        
        let msgIds = request.ids.map { Api.InputMessage.inputMessageID(Api.InputMessage.Cons_inputMessageID(id: $0)) }
        
        switch request.fromPeer {
        case let .inputPeerChannel(data):
            let getMsgs = Api.functions.channels.getMessages(channel: .inputChannel(Api.InputChannel.Cons_inputChannel(channelId: data.channelId, accessHash: data.accessHash)), id: msgIds)
            return getMsgs.1.makeData() as NSData
        default:
            let getMsgs = Api.functions.messages.getMessages(id: msgIds)
            return getMsgs.1.makeData() as NSData
        }
    }

    @objc(createSendMediaRequests:originalForwardData:)
    static func createSendMediaRequests(_ response: Any, originalForwardData: NSData) -> [NSData] {
        guard let messagesResponse = response as? Api.messages.Messages else { 
            NSLog("[Lead] Failed to cast response to Api.messages.Messages")
            return [] 
        }
        
        guard let originalRequest = parseForwardRequest(originalForwardData) else { return [] }
        
        var messages: [Api.Message] = []
        switch messagesResponse {
        case let .messages(data): messages = data.messages
        case let .messagesSlice(data): messages = data.messages
        case let .channelMessages(data): messages = data.messages
        default: break
        }
        
        NSLog("[Lead] Cloning %d messages", messages.count)
        
        return messages.compactMap { msg -> NSData? in
            guard case let .message(data) = msg else { return nil }
            
            var inputMedia: Api.InputMedia?
            if let media = data.media {
                switch media {
                case let .messageMediaPhoto(m):
                    if let photo = m.photo, case let .photo(p) = photo {
                        NSLog("[Lead]   Detected Photo: id=%lld, accessHash=%lld, refLen=%d", p.id, p.accessHash, p.fileReference.size)
                        inputMedia = .inputMediaPhoto(Api.InputMedia.Cons_inputMediaPhoto(flags: 0, id: .inputPhoto(Api.InputPhoto.Cons_inputPhoto(id: p.id, accessHash: p.accessHash, fileReference: p.fileReference)), ttlSeconds: nil, video: nil))
                    } else {
                        NSLog("[Lead]   Photo media but photo is empty")
                    }
                case let .messageMediaDocument(m):
                    if let document = m.document, case let .document(d) = document {
                        NSLog("[Lead]   Detected Document: id=%lld, accessHash=%lld, refLen=%d", d.id, d.accessHash, d.fileReference.size)
                        inputMedia = .inputMediaDocument(Api.InputMedia.Cons_inputMediaDocument(flags: 0, id: .inputDocument(Api.InputDocument.Cons_inputDocument(id: d.id, accessHash: d.accessHash, fileReference: d.fileReference)), videoCover: nil, videoTimestamp: nil, ttlSeconds: nil, query: nil))
                    } else {
                        NSLog("[Lead]   Document media but document is empty")
                    }
                case let .messageMediaGeo(m):
                    if case let .geoPoint(gp) = m.geo {
                        inputMedia = .inputMediaGeoPoint(Api.InputMedia.Cons_inputMediaGeoPoint(geoPoint: .inputGeoPoint(Api.InputGeoPoint.Cons_inputGeoPoint(flags: 0, lat: gp.lat, long: gp.long, accuracyRadius: nil))))
                    }
                case let .messageMediaContact(m):
                    inputMedia = .inputMediaContact(Api.InputMedia.Cons_inputMediaContact(phoneNumber: m.phoneNumber, firstName: m.firstName, lastName: m.lastName, vcard: m.vcard))
                case let .messageMediaVenue(m):
                    if case let .geoPoint(gp) = m.geo {
                        inputMedia = .inputMediaVenue(Api.InputMedia.Cons_inputMediaVenue(geoPoint: .inputGeoPoint(Api.InputGeoPoint.Cons_inputGeoPoint(flags: 0, lat: gp.lat, long: gp.long, accuracyRadius: nil)), title: m.title, address: m.address, provider: m.provider, venueId: m.venueId, venueType: m.venueType))
                    }
                case .messageMediaWebPage(_):
                    NSLog("[Lead]   Detected WebPage, sending as text fallback")
                    inputMedia = nil
                default:
                    NSLog("[Lead]   Unsupported media type: \(String(describing: media))")
                    inputMedia = nil
                }
            } else {
                NSLog("[Lead]   No media in message")
            }
            
            var flags: Int32 = 0x80
            if data.entities != nil && !data.entities!.isEmpty {
                flags |= (1 << 3)
            }
            
            let randomId = Int64.random(in: 1...Int64.max)
            
            if let im = inputMedia {
                // MATCHING NATIVE LOG: ID -> flags -> peer -> random_id -> media
                let buffer = Buffer()
                buffer.appendInt32(53536639) // 0x0330E77F (7F E7 30 03)
                buffer.appendInt32(flags)     // 0x80
                
                // 1. Peer
                originalRequest.toPeer.serialize(buffer, true)
                
                // 2. Random ID (8 bytes) - Native log shows it BEFORE media
                buffer.appendInt64(randomId)
                
                // 3. Media
                im.serialize(buffer, true)
                
                NSLog("[Lead]   Created NATIVE-ALIGNED sendMedia payload (len: %d)", buffer.size)
                return buffer.makeData() as NSData
            } else {
                // Send as text only if no media or media not supported
                let sendMessage = Api.functions.messages.sendMessage(
                    flags: flags, 
                    peer: originalRequest.toPeer, 
                    replyTo: nil, 
                    message: data.message, 
                    randomId: randomId, 
                    replyMarkup: nil, 
                    entities: data.entities, 
                    scheduleDate: nil, 
                    scheduleRepeatPeriod: nil, 
                    sendAs: nil, 
                    quickReplyShortcut: nil, 
                    effect: nil, 
                    allowPaidStars: nil, 
                    suggestedPost: nil
                )
                NSLog("[Lead]   Created sendMessage payload (len: %d)", sendMessage.1.size)
                return sendMessage.1.makeData() as NSData
            }
        }
    }

    @objc(parseMessagesResponse:)
    static func parseMessagesResponse(_ data: NSData) -> Any? {
        var workingData = data as Data
        if workingData.count >= 4 {
            let signature = workingData.withUnsafeBytes { $0.load(as: UInt32.self) }
            if signature == 0x3072CFA1 { // gzip_packed
                NSLog("[Lead] parseMessagesResponse: Detected GZIP, decompressing...")
                if let decompressed = decompressGzip(workingData.withUnsafeBytes { $0.baseAddress?.advanced(by: 4) }, workingData.count - 4) {
                    workingData = decompressed as Data
                    NSLog("[Lead] parseMessagesResponse: GZIP decompressed success (new len: \(workingData.count))")
                } else {
                    NSLog("[Lead] parseMessagesResponse: GZIP decompression FAILED")
                }
            }
        }

        let buffer = Buffer(data: workingData)
        let reader = BufferReader(buffer)
        guard let signature = reader.readInt32() else { 
            NSLog("[Lead] parseMessagesResponse: Failed to read signature")
            return nil 
        }
        return Api.parse(reader, signature: signature)
    }

    @objc static func fakeUpdatesResponse() -> NSData {
        let outBuf = Buffer()
        let updates = Api.Updates.updates(Api.Updates.Cons_updates(updates: [], users: [], chats: [], date: Int32(Date().timeIntervalSince1970), seq: 0))
        Api.serializeObject(updates, buffer: outBuf, boxed: true)
        return outBuf.makeData() as NSData
    }

    static func serializeBoxed(_ obj: Any) -> NSData {
        let outBuf = Buffer()
        Api.serializeObject(obj, buffer: outBuf, boxed: true)
        return outBuf.makeData() as NSData
    }

    // MARK: - Targeted Media File Resolver

    private static func safeGetProperty(_ obj: AnyObject, _ key: String) -> Any? {
        let sel = NSSelectorFromString(key)
        if obj.responds(to: sel) {
            if let result = obj.perform(sel) {
                return result.takeUnretainedValue()
            }
        }
        let mirror = Mirror(reflecting: obj)
        for child in mirror.children {
            if child.label == key {
                return child.value
            }
        }
        return nil
    }

    @objc static func findMediaFilePath(fromTarget target: Any?) -> String? {
        guard let target = target else { return nil }

        var objectsToInspect: [Any] = []

        if let vc = target as? UIViewController {
            var foundCentral = false
            let candidateNames = ["displayNode", "galleryNode", "controllerNode"]
            for name in candidateNames {
                if let dNode = safeGetProperty(vc, name) as? NSObject {
                    if let pager = safeGetProperty(dNode, "pager") as? NSObject {
                        if let central = safeGetProperty(pager, "centralItemNode") {
                            foundCentral = true
                            let cCls = String(describing: type(of: central))
                            // If user is looking at a photo item, do not resolve any video
                            if cCls.contains("Image") || cCls.contains("Photo") {
                                return nil
                            }
                            objectsToInspect.append(central)
                            if let cObj = central as? NSObject {
                                if let itm = safeGetProperty(cObj, "item") {
                                    objectsToInspect.append(itm)
                                }
                                if let vNode = safeGetProperty(cObj, "videoNode") {
                                    objectsToInspect.append(vNode)
                                }
                                if let v = safeGetProperty(cObj, "view") as? UIView {
                                    objectsToInspect.append(v)
                                    collectNodesAndViews(from: v, into: &objectsToInspect)
                                }
                            }
                        }
                    }
                }
            }
            if !foundCentral {
                objectsToInspect.append(vc)
                if vc.isViewLoaded, let v = vc.view {
                    objectsToInspect.append(v)
                    collectNodesAndViews(from: v, into: &objectsToInspect)
                }
            }
        } else if let view = target as? UIView {
            objectsToInspect.append(view)
            collectNodesAndViews(from: view, into: &objectsToInspect)
        } else {
            objectsToInspect.append(target)
            if let obj = target as? NSObject {
                if let tNode = safeGetProperty(obj, "targetNode") {
                    objectsToInspect.insert(tNode, at: 0)
                }
                if let tController = safeGetProperty(obj, "targetController") {
                    objectsToInspect.insert(tController, at: 0)
                }
                if let v = safeGetProperty(obj, "view") as? UIView {
                    objectsToInspect.append(v)
                    collectNodesAndViews(from: v, into: &objectsToInspect)
                }
                if let item = safeGetProperty(obj, "item") {
                    objectsToInspect.insert(item, at: 0)
                }
                if let vNode = safeGetProperty(obj, "videoNode") {
                    objectsToInspect.insert(vNode, at: 0)
                }
                if let media = safeGetProperty(obj, "media") {
                    objectsToInspect.insert(media, at: 0)
                }
            }
        }

        var fileIds: [Int64] = []
        var uniqueIds: [String] = []
        var tempPaths: [String] = []
        var visited = Set<ObjectIdentifier>()

        for obj in objectsToInspect {
            extractMediaInfo(from: obj, visited: &visited, fileIds: &fileIds, uniqueIds: &uniqueIds, tempPaths: &tempPaths)
        }

        let fm = FileManager.default

        // 1. Check tempPaths first
        for path in tempPaths {
            if fm.fileExists(atPath: path),
               let attrs = try? fm.attributesOfItem(atPath: path),
               let size = attrs[.size] as? UInt64, size >= 40 * 1024 {
                return path
            }
        }

        let folders = collectMediaFolders()

        // 2. Check exact uniqueIds in storage folders
        for folder in folders {
            for uid in uniqueIds {
                let complete = (folder as NSString).appendingPathComponent(uid)
                if fm.fileExists(atPath: complete),
                   let attrs = try? fm.attributesOfItem(atPath: complete),
                   let size = attrs[.size] as? UInt64, size >= 40 * 1024 {
                    return complete
                }
                let partial = (folder as NSString).appendingPathComponent("\(uid)_partial")
                if fm.fileExists(atPath: partial),
                   let attrs = try? fm.attributesOfItem(atPath: partial),
                   let size = attrs[.size] as? UInt64, size >= 40 * 1024 {
                    return partial
                }
            }
        }

        // 3. Search for fileId in filenames in storage folders
        for fid in fileIds {
            let fidStr = String(fid)
            for folder in folders {
                guard let items = try? fm.contentsOfDirectory(atPath: folder) else { continue }
                var partialCandidate: String? = nil
                for item in items {
                    if item.contains(fidStr) {
                        if item.hasSuffix(".meta") || item.hasSuffix(".lock") || item.hasSuffix(".json") { continue }
                        let full = (folder as NSString).appendingPathComponent(item)
                        guard let attrs = try? fm.attributesOfItem(atPath: full),
                              let size = attrs[.size] as? UInt64, size >= 40 * 1024 else { continue }

                        if item.hasSuffix("_partial") {
                            let nonPartial = String(item.dropLast(8))
                            let nonPartialFull = (folder as NSString).appendingPathComponent(nonPartial)
                            if fm.fileExists(atPath: nonPartialFull) {
                                return nonPartialFull
                            }
                            if partialCandidate == nil {
                                partialCandidate = full
                            }
                        } else {
                            // Non-partial complete file!
                            return full
                        }
                    }
                }
                if let candidate = partialCandidate {
                    return candidate
                }
            }
        }

        return nil
    }

    private static func collectNodesAndViews(from view: UIView, into list: inout [Any]) {
        if let node = safeGetProperty(view, "asyncdisplaykit_node") {
            list.append(node)
        }
        for sub in view.subviews {
            list.append(sub)
            collectNodesAndViews(from: sub, into: &list)
        }
    }

    private static func extractMediaInfo(from obj: Any, visited: inout Set<ObjectIdentifier>, fileIds: inout [Int64], uniqueIds: inout [String], tempPaths: inout [String]) {
        if type(of: obj) is AnyClass {
            let id = ObjectIdentifier(obj as AnyObject)
            if visited.contains(id) { return }
            visited.insert(id)
        }

        let desc = String(describing: obj)
        parseIdentifiers(fromText: desc, fileIds: &fileIds, uniqueIds: &uniqueIds, tempPaths: &tempPaths)

        var currentMirror: Mirror? = Mirror(reflecting: obj)
        var depth = 0
        while let mirror = currentMirror, depth < 5 {
            depth += 1
            for child in mirror.children {
                guard let label = child.label else { continue }
                if label == "tempFilePath", let path = child.value as? String, !path.isEmpty {
                    if !tempPaths.contains(path) { tempPaths.append(path) }
                } else if label == "fileId" {
                    if let fid = child.value as? Int64, fid != 0 {
                        if !fileIds.contains(fid) { fileIds.append(fid) }
                    } else if let fid = child.value as? Int32, fid != 0 {
                        let id64 = Int64(fid)
                        if !fileIds.contains(id64) { fileIds.append(id64) }
                    } else {
                        let idMirror = Mirror(reflecting: child.value)
                        for idChild in idMirror.children {
                            if idChild.label == "id", let idVal = idChild.value as? Int64, idVal != 0 {
                                if !fileIds.contains(idVal) { fileIds.append(idVal) }
                            }
                        }
                    }
                } else if label == "id", let idVal = child.value as? Int64, idVal > 1000000000 {
                    if !fileIds.contains(idVal) { fileIds.append(idVal) }
                } else if ["media", "fileReference", "resource", "content", "videoNode", "contentNode", "item", "entry", "message"].contains(label) {
                    let subDesc = String(describing: child.value)
                    parseIdentifiers(fromText: subDesc, fileIds: &fileIds, uniqueIds: &uniqueIds, tempPaths: &tempPaths)
                    extractMediaInfo(from: child.value, visited: &visited, fileIds: &fileIds, uniqueIds: &uniqueIds, tempPaths: &tempPaths)
                }
            }
            currentMirror = mirror.superclassMirror
        }
    }

    private static func parseIdentifiers(fromText text: String, fileIds: inout [Int64], uniqueIds: inout [String], tempPaths: inout [String]) {
        // 1. telegram-cloud-document-DC-FILEID
        if let regex = try? NSRegularExpression(pattern: "telegram-cloud-document-(\\d+)-(\\d+)", options: []) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                if let fullRange = Range(match.range(at: 0), in: text) {
                    let uid = String(text[fullRange])
                    if !uniqueIds.contains(uid) { uniqueIds.append(uid) }
                }
                if let idRange = Range(match.range(at: 2), in: text), let fid = Int64(text[idRange]) {
                    if !fileIds.contains(fid) { fileIds.append(fid) }
                }
            }
        }

        // 2. fileId: 1234567890123456
        if let regex = try? NSRegularExpression(pattern: "fileId:\\s*(\\d{10,22})", options: []) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                if let idRange = Range(match.range(at: 1), in: text), let fid = Int64(text[idRange]) {
                    if !fileIds.contains(fid) { fileIds.append(fid) }
                }
            }
        }

        // 3. MediaId(namespace: X, id: Y)
        if let regex = try? NSRegularExpression(pattern: "MediaId\\([^\\)]*?id:\\s*(\\d{10,22})", options: []) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                if let idRange = Range(match.range(at: 1), in: text), let fid = Int64(text[idRange]) {
                    if !fileIds.contains(fid) { fileIds.append(fid) }
                }
            }
        }

        // 4. tempFilePath: "..."
        if let regex = try? NSRegularExpression(pattern: "tempFilePath:[^\"\\n]*?\"([^\"]+)\"", options: []) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                if let pathRange = Range(match.range(at: 1), in: text) {
                    let p = String(text[pathRange])
                    if !tempPaths.contains(p) { tempPaths.append(p) }
                }
            }
        }
    }

    private static func collectMediaFolders() -> [String] {
        var folders: [String] = []
        let fm = FileManager.default

        folders.append(NSTemporaryDirectory())
        folders.append((NSHomeDirectory() as NSString).appendingPathComponent("tmp"))

        var roots: [String] = []
        if let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            roots.append((docs as NSString).appendingPathComponent("telegram-data"))
            let fakeGroup = (docs as NSString).appendingPathComponent("FakeGroupContainers")
            if let subs = try? fm.contentsOfDirectory(atPath: fakeGroup) {
                for sub in subs {
                    roots.append(((fakeGroup as NSString).appendingPathComponent(sub) as NSString).appendingPathComponent("telegram-data"))
                }
            }
        }

        if let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty {
            if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.\(bundleId)") {
                roots.append((groupURL.path as NSString).appendingPathComponent("telegram-data"))
            }
        }

        if let caches = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first {
            roots.append((caches as NSString).appendingPathComponent("telegram-data"))
        }
        if let appSupport = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first {
            roots.append((appSupport as NSString).appendingPathComponent("telegram-data"))
        }

        for root in roots {
            guard fm.fileExists(atPath: root) else { continue }

            let tempMain = (root as NSString).appendingPathComponent("temp/main")
            if fm.fileExists(atPath: tempMain), let tds = try? fm.contentsOfDirectory(atPath: tempMain) {
                for td in tds {
                    let fullTd = (tempMain as NSString).appendingPathComponent(td)
                    folders.append(fullTd)
                    if let subs = try? fm.contentsOfDirectory(atPath: fullTd) {
                        for sub in subs {
                            folders.append((fullTd as NSString).appendingPathComponent(sub))
                        }
                    }
                }
            }

            if let accounts = try? fm.contentsOfDirectory(atPath: root) {
                for acc in accounts where acc.hasPrefix("account-") {
                    let media = (((root as NSString).appendingPathComponent(acc) as NSString).appendingPathComponent("postbox") as NSString).appendingPathComponent("media")
                    if fm.fileExists(atPath: media) {
                        folders.append(media)
                        folders.append((media as NSString).appendingPathComponent("cache"))
                        folders.append((media as NSString).appendingPathComponent("short-cache"))
                        folders.append((media as NSString).appendingPathComponent("animation-cache"))
                    }
                }
            }
        }
        return folders
    }
}
