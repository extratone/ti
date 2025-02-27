import Foundation
import UIKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import TextFormat
import LocalizedPeerData
import Display
import Markdown

private let titleFont = Font.regular(13.0)
private let titleBoldFont = Font.bold(13.0)

private func peerMentionAttributes(primaryTextColor: UIColor, peerId: PeerId) -> MarkdownAttributeSet {
    return MarkdownAttributeSet(font: titleBoldFont, textColor: primaryTextColor, additionalAttributes: [TelegramTextAttributes.PeerMention: TelegramPeerMention(peerId: peerId, mention: "")])
}

private func peerMentionsAttributes(primaryTextColor: UIColor, peerIds: [(Int, PeerId?)]) -> [Int: MarkdownAttributeSet] {
    var result: [Int: MarkdownAttributeSet] = [:]
    for (index, peerId) in peerIds {
        if let peerId = peerId {
            result[index] = peerMentionAttributes(primaryTextColor: primaryTextColor, peerId: peerId)
        }
    }
    return result
}

public func plainServiceMessageString(strings: PresentationStrings, nameDisplayOrder: PresentationPersonNameOrder, dateTimeFormat: PresentationDateTimeFormat, message: Message, accountPeerId: PeerId, forChatList: Bool) -> String? {
    return universalServiceMessageString(presentationData: nil, strings: strings, nameDisplayOrder: nameDisplayOrder, dateTimeFormat: dateTimeFormat, message: message, accountPeerId: accountPeerId, forChatList: forChatList)?.string
}

public func universalServiceMessageString(presentationData: (PresentationTheme, TelegramWallpaper)?, strings: PresentationStrings, nameDisplayOrder: PresentationPersonNameOrder, dateTimeFormat: PresentationDateTimeFormat, message: Message, accountPeerId: PeerId, forChatList: Bool) -> NSAttributedString? {
    var attributedString: NSAttributedString?
    
    let primaryTextColor: UIColor
    if let (theme, wallpaper) = presentationData {
        primaryTextColor = serviceMessageColorComponents(theme: theme, wallpaper: wallpaper).primaryText
    } else {
        primaryTextColor = .black
    }
    
    let bodyAttributes = MarkdownAttributeSet(font: titleFont, textColor: primaryTextColor, additionalAttributes: [:])
    let boldAttributes = MarkdownAttributeSet(font: titleBoldFont, textColor: primaryTextColor, additionalAttributes: [:])
    
    for media in message.media {
        if let action = media as? TelegramMediaAction {
            let authorName = message.author?.displayTitle(strings: strings, displayOrder: nameDisplayOrder) ?? ""
            
            var isChannel = false
            if message.id.peerId.namespace == Namespaces.Peer.CloudChannel, let peer = message.peers[message.id.peerId] as? TelegramChannel, case .broadcast = peer.info {
                isChannel = true
            }
            
            switch action.action {
            case let .groupCreated(title):
                if isChannel {
                    attributedString = NSAttributedString(string: strings.Notification_CreatedChannel, font: titleFont, textColor: primaryTextColor)
                } else {
                    if forChatList {
                        attributedString = NSAttributedString(string: strings.Notification_CreatedGroup, font: titleFont, textColor: primaryTextColor)
                    } else {
                        attributedString = addAttributesToStringWithRanges(strings.Notification_CreatedChatWithTitle(authorName, title)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                    }
                }
            case let .addedMembers(peerIds):
                if let peerId = peerIds.first, peerId == message.author?.id {
                    if let peer = message.peers[message.id.peerId] as? TelegramChannel, case .broadcast = peer.info {
                        attributedString = addAttributesToStringWithRanges(strings.Notification_JoinedChannel(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, peerId)]))
                    } else {
                        attributedString = addAttributesToStringWithRanges(strings.Notification_JoinedChat(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, peerId)]))
                    }
                } else {
                    var attributePeerIds: [(Int, PeerId?)] = [(0, message.author?.id)]
                    let resultTitleString: PresentationStrings.FormattedString
                    if peerIds.count == 1 {
                        attributePeerIds.append((1, peerIds.first))
                        resultTitleString = strings.Notification_Invited(authorName, peerDebugDisplayTitles(peerIds, message.peers))
                    } else {
                        resultTitleString = strings.Notification_InvitedMultiple(authorName, peerDebugDisplayTitles(peerIds, message.peers))
                    }
                    
                    attributedString = addAttributesToStringWithRanges(resultTitleString._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: attributePeerIds))
                }
            case let .removedMembers(peerIds):
                if peerIds.first == message.author?.id {
                    if let peer = message.peers[message.id.peerId] as? TelegramChannel, case .broadcast = peer.info {
                        attributedString = addAttributesToStringWithRanges(strings.Notification_LeftChannel(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                    } else {
                        attributedString = addAttributesToStringWithRanges(strings.Notification_LeftChat(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                    }
                } else {
                    var attributePeerIds: [(Int, PeerId?)] = [(0, message.author?.id)]
                    if peerIds.count == 1 {
                        attributePeerIds.append((1, peerIds.first))
                    }
                    attributedString = addAttributesToStringWithRanges(strings.Notification_Kicked(authorName, peerDebugDisplayTitles(peerIds, message.peers))._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: attributePeerIds))
                }
            case let .photoUpdated(image):
                if authorName.isEmpty || isChannel {
                    if isChannel {
                        if let image = image {
                            if !image.videoRepresentations.isEmpty {
                                attributedString = NSAttributedString(string: strings.Channel_MessageVideoUpdated, font: titleFont, textColor: primaryTextColor)
                            } else {
                                attributedString = NSAttributedString(string: strings.Channel_MessagePhotoUpdated, font: titleFont, textColor: primaryTextColor)
                            }
                        } else {
                            attributedString = NSAttributedString(string: strings.Channel_MessagePhotoRemoved, font: titleFont, textColor: primaryTextColor)
                        }
                    } else {
                        if let image = image {
                            if !image.videoRepresentations.isEmpty {
                                attributedString = NSAttributedString(string: strings.Group_MessageVideoUpdated, font: titleFont, textColor: primaryTextColor)
                            } else {
                                attributedString = NSAttributedString(string: strings.Group_MessagePhotoUpdated, font: titleFont, textColor: primaryTextColor)
                            }
                        } else {
                            attributedString = NSAttributedString(string: strings.Group_MessagePhotoRemoved, font: titleFont, textColor: primaryTextColor)
                        }
                    }
                } else {
                    if let image = image {
                        if !image.videoRepresentations.isEmpty {
                            attributedString = addAttributesToStringWithRanges(strings.Notification_ChangedGroupVideo(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                        } else {
                            attributedString = addAttributesToStringWithRanges(strings.Notification_ChangedGroupPhoto(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                        }
                    } else {
                        attributedString = addAttributesToStringWithRanges(strings.Notification_RemovedGroupPhoto(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                    }
                }
            case let .titleUpdated(title):
                if authorName.isEmpty || isChannel {
                    attributedString = NSAttributedString(string: strings.Channel_MessageTitleUpdated(title).string, font: titleFont, textColor: primaryTextColor)
                } else {
                    attributedString = addAttributesToStringWithRanges(strings.Notification_ChangedGroupName(authorName, title)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                }
            case .pinnedMessageUpdated:
                enum PinnnedMediaType {
                    case text(String)
                    case game
                    case photo
                    case video
                    case round
                    case audio
                    case file
                    case gif
                    case sticker
                    case location
                    case contact
                    case poll(TelegramMediaPollKind)
                    case deleted
                }
                
                var pinnedMessage: Message?
                for attribute in message.attributes {
                    if let attribute = attribute as? ReplyMessageAttribute, let message = message.associatedMessages[attribute.messageId] {
                        pinnedMessage = message
                    }
                }
                
                var type: PinnnedMediaType
                if let pinnedMessage = pinnedMessage {
                    type = .text(pinnedMessage.text)
                    inner: for media in pinnedMessage.media {
                        if media is TelegramMediaGame {
                            type = .game
                            break inner
                        }
                        if let _ = media as? TelegramMediaImage {
                            type = .photo
                        } else if let file = media as? TelegramMediaFile {
                            type = .file
                            if file.isAnimated {
                                type = .gif
                            } else {
                                for attribute in file.attributes {
                                    switch attribute {
                                    case let .Video(_, _, flags):
                                        if flags.contains(.instantRoundVideo) {
                                            type = .round
                                        } else {
                                            type = .video
                                        }
                                        break inner
                                    case let .Audio(isVoice, _, _, _, _):
                                        if isVoice {
                                            type = .audio
                                        } else {
                                            type = .file
                                        }
                                        break inner
                                    case .Sticker:
                                        type = .sticker
                                        break inner
                                    case .Animated:
                                        break
                                    default:
                                        break
                                    }
                                }
                            }
                        } else if let _ = media as? TelegramMediaMap {
                            type = .location
                        } else if let _ = media as? TelegramMediaContact {
                            type = .contact
                        } else if let poll = media as? TelegramMediaPoll {
                            type = .poll(poll.kind)
                        }
                    }
                } else {
                    type = .deleted
                }
                
                switch type {
                case let .text(text):
                    var clippedText = text.replacingOccurrences(of: "\n", with: " ")
                    if clippedText.count > 14 {
                        clippedText = "\(clippedText[...clippedText.index(clippedText.startIndex, offsetBy: 14)])..."
                    }
                    let textWithRanges: PresentationStrings.FormattedString
                    if clippedText.isEmpty {
                        textWithRanges = strings.Message_PinnedGenericMessage(authorName)
                    } else {
                        textWithRanges = strings.Notification_PinnedTextMessage(authorName, clippedText)
                    }
                    attributedString = addAttributesToStringWithRanges(textWithRanges._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                case .game:
                    attributedString = addAttributesToStringWithRanges(strings.Message_AuthorPinnedGame(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                case .photo:
                    attributedString = addAttributesToStringWithRanges(strings.Notification_PinnedPhotoMessage(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                case .video:
                    attributedString = addAttributesToStringWithRanges(strings.Notification_PinnedVideoMessage(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                case .round:
                    attributedString = addAttributesToStringWithRanges(strings.Notification_PinnedRoundMessage(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                case .audio:
                    attributedString = addAttributesToStringWithRanges(strings.Notification_PinnedAudioMessage(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                case .file:
                    attributedString = addAttributesToStringWithRanges(strings.Notification_PinnedDocumentMessage(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                case .gif:
                    attributedString = addAttributesToStringWithRanges(strings.Notification_PinnedAnimationMessage(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                case .sticker:
                    attributedString = addAttributesToStringWithRanges(strings.Notification_PinnedStickerMessage(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                case .location:
                    attributedString = addAttributesToStringWithRanges(strings.Notification_PinnedLocationMessage(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                case .contact:
                    attributedString = addAttributesToStringWithRanges(strings.Notification_PinnedContactMessage(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                case let .poll(kind):
                    switch kind {
                    case .poll:
                        attributedString = addAttributesToStringWithRanges(strings.Notification_PinnedPollMessage(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                    case .quiz:
                        attributedString = addAttributesToStringWithRanges(strings.Notification_PinnedQuizMessage(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                    }
                case .deleted:
                    attributedString = addAttributesToStringWithRanges(strings.Message_PinnedGenericMessage(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
                }
            case .joinedByLink:
                attributedString = addAttributesToStringWithRanges(strings.Notification_JoinedGroupByLink(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
            case .channelMigratedFromGroup, .groupMigratedToChannel:
                attributedString = NSAttributedString(string: "", font: titleFont, textColor: primaryTextColor)
            case let .messageAutoremoveTimeoutUpdated(timeout):
                let authorString: String
                if let author = messageMainPeer(message) {
                    authorString = author.compactDisplayTitle
                } else {
                    authorString = ""
                }
                
                let messagePeer = message.peers[message.id.peerId]
                
                if timeout > 0 {
                    let timeValue = timeIntervalString(strings: strings, value: timeout, preferLowerValue: true)
                    
                    let string: String
                    if let _ = messagePeer as? TelegramUser {
                        if message.author?.id == accountPeerId {
                            string = strings.Conversation_AutoremoveTimerSetUserYou(timeValue).string
                        } else {
                            string = strings.Conversation_AutoremoveTimerSetUser(authorString, timeValue).string
                        }
                    } else if let _ = messagePeer as? TelegramGroup {
                        string = strings.Conversation_AutoremoveTimerSetGroup(timeValue).string
                    } else if let channel = messagePeer as? TelegramChannel {
                        if case .group = channel.info {
                            string = strings.Conversation_AutoremoveTimerSetGroup(timeValue).string
                        } else {
                            string = strings.Conversation_AutoremoveTimerSetChannel(timeValue).string
                        }
                    } else {
                        if message.author?.id == accountPeerId {
                            string = strings.Notification_MessageLifetimeChangedOutgoing(timeValue).string
                        } else {
                            string = strings.Notification_MessageLifetimeChanged(authorString, timeValue).string
                        }
                    }
                    attributedString = NSAttributedString(string: string, font: titleFont, textColor: primaryTextColor)
                } else {
                    let string: String
                    if let _ = messagePeer as? TelegramUser {
                        if message.author?.id == accountPeerId {
                            string = strings.Conversation_AutoremoveTimerRemovedUserYou
                        } else {
                            string = strings.Conversation_AutoremoveTimerRemovedUser(authorString).string
                        }
                    } else if let _ = messagePeer as? TelegramGroup {
                        string = strings.Conversation_AutoremoveTimerRemovedGroup
                    } else if let channel = messagePeer as? TelegramChannel {
                        if case .group = channel.info {
                            string = strings.Conversation_AutoremoveTimerRemovedGroup
                        } else {
                            string = strings.Conversation_AutoremoveTimerRemovedChannel
                        }
                    } else {
                        if message.author?.id == accountPeerId {
                            string = strings.Notification_MessageLifetimeRemovedOutgoing
                        } else {
                            string = strings.Notification_MessageLifetimeRemoved(authorString).string
                        }
                    }
                    attributedString = NSAttributedString(string: string, font: titleFont, textColor: primaryTextColor)
                }
            case .historyCleared:
                break
            case .historyScreenshot:
                let text: String
                if message.effectivelyIncoming(accountPeerId) {
                    text = strings.Notification_SecretChatMessageScreenshot(message.author?.compactDisplayTitle ?? "").string
                } else {
                    text = strings.Notification_SecretChatMessageScreenshotSelf
                }
                attributedString = NSAttributedString(string: text, font: titleFont, textColor: primaryTextColor)
            case let .gameScore(gameId: _, score):
                var gameTitle: String?
                inner: for attribute in message.attributes {
                    if let attribute = attribute as? ReplyMessageAttribute, let message = message.associatedMessages[attribute.messageId] {
                        for media in message.media {
                            if let game = media as? TelegramMediaGame {
                                gameTitle = game.title
                                break inner
                            }
                        }
                    }
                }
                
                var baseString: String
                if message.author?.id == accountPeerId {
                    if let _ = gameTitle {
                        baseString = strings.ServiceMessage_GameScoreSelfExtended(score)
                    } else {
                        baseString = strings.ServiceMessage_GameScoreSelfSimple(score)
                    }
                } else {
                    if let _ = gameTitle {
                        baseString = strings.ServiceMessage_GameScoreExtended(score)
                    } else {
                        baseString = strings.ServiceMessage_GameScoreSimple(score)
                    }
                }
                let baseStringValue = baseString as NSString
                var ranges: [(Int, NSRange)] = []
                if baseStringValue.range(of: "{name}").location != NSNotFound {
                    ranges.append((0, baseStringValue.range(of: "{name}")))
                }
                if baseStringValue.range(of: "{game}").location != NSNotFound {
                    ranges.append((1, baseStringValue.range(of: "{game}")))
                }
                ranges.sort(by: { $0.1.location < $1.1.location })
                
                var argumentAttributes = peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)])
                argumentAttributes[1] = MarkdownAttributeSet(font: titleBoldFont, textColor: primaryTextColor, additionalAttributes: [:])
                attributedString = addAttributesToStringWithRanges(formatWithArgumentRanges(baseString, ranges, [authorName, gameTitle ?? ""]), body: bodyAttributes, argumentAttributes: argumentAttributes)
            case let .paymentSent(currency, totalAmount):
                var invoiceMessage: Message?
                for attribute in message.attributes {
                    if let attribute = attribute as? ReplyMessageAttribute, let message = message.associatedMessages[attribute.messageId] {
                        invoiceMessage = message
                    }
                }
                
                var invoiceTitle: String?
                if let invoiceMessage = invoiceMessage {
                    for media in invoiceMessage.media {
                        if let invoice = media as? TelegramMediaInvoice {
                            invoiceTitle = invoice.title
                        }
                    }
                }
                
                if let invoiceTitle = invoiceTitle {
                    let botString: String
                    if let peer = messageMainPeer(message) {
                        botString = peer.compactDisplayTitle
                    } else {
                        botString = ""
                    }
                    let mutableString = NSMutableAttributedString()
                    mutableString.append(NSAttributedString(string: strings.Notification_PaymentSent, font: titleFont, textColor: primaryTextColor))
                    
                    var range = NSRange(location: NSNotFound, length: 0)
                    
                    range = (mutableString.string as NSString).range(of: "{amount}")
                    if range.location != NSNotFound {
                        mutableString.replaceCharacters(in: range, with: NSAttributedString(string: formatCurrencyAmount(totalAmount, currency: currency), font: titleBoldFont, textColor: primaryTextColor))
                    }
                    range = (mutableString.string as NSString).range(of: "{name}")
                    if range.location != NSNotFound {
                        mutableString.replaceCharacters(in: range, with: NSAttributedString(string: botString, font: titleBoldFont, textColor: primaryTextColor))
                    }
                    range = (mutableString.string as NSString).range(of: "{title}")
                    if range.location != NSNotFound {
                        mutableString.replaceCharacters(in: range, with: NSAttributedString(string: invoiceTitle, font: titleFont, textColor: primaryTextColor))
                    }
                    attributedString = mutableString
                } else {
                    attributedString = NSAttributedString(string: strings.Message_PaymentSent(formatCurrencyAmount(totalAmount, currency: currency)).string, font: titleFont, textColor: primaryTextColor)
                }
            case let .phoneCall(_, discardReason, _, _):
                var titleString: String
                let incoming: Bool
                if message.flags.contains(.Incoming) {
                    titleString = strings.Notification_CallIncoming
                    incoming = true
                } else {
                    titleString = strings.Notification_CallOutgoing
                    incoming = false
                }
                if let discardReason = discardReason {
                    switch discardReason {
                    case .disconnect:
                        titleString = strings.Notification_CallCanceled
                    case .missed, .busy:
                        titleString = incoming ? strings.Notification_CallMissed : strings.Notification_CallCanceled
                    case .hangup:
                        break
                    }
                }
                attributedString = NSAttributedString(string: titleString, font: titleFont, textColor: primaryTextColor)
            case let .groupPhoneCall(_, _, scheduleDate, duration):
                if let scheduleDate = scheduleDate {
                    if message.author?.id.namespace == Namespaces.Peer.CloudChannel {
                        let titleString: PresentationStrings.FormattedString
                        if let channel = message.author as? TelegramChannel, case .broadcast = channel.info {
                            titleString = humanReadableStringForTimestamp(strings: strings, dateTimeFormat: dateTimeFormat, timestamp: scheduleDate, alwaysShowTime: true, allowYesterday: false, format: HumanReadableStringFormat(dateFormatString: { strings.Notification_LiveStreamScheduled($0) }, tomorrowFormatString: { strings.Notification_LiveStreamScheduledTomorrow($0) }, todayFormatString: { strings.Notification_LiveStreamScheduledToday($0) }))
                        } else {
                            titleString = humanReadableStringForTimestamp(strings: strings, dateTimeFormat: dateTimeFormat, timestamp: scheduleDate, alwaysShowTime: true, allowYesterday: false, format: HumanReadableStringFormat(dateFormatString: { strings.Notification_VoiceChatScheduledChannel($0) }, tomorrowFormatString: { strings.Notification_VoiceChatScheduledTomorrowChannel($0) }, todayFormatString: { strings.Notification_VoiceChatScheduledTodayChannel($0) }))
                        }
                        attributedString = NSAttributedString(string: titleString.string, font: titleFont, textColor: primaryTextColor)
                    } else {
                        let titleString = humanReadableStringForTimestamp(strings: strings, dateTimeFormat: dateTimeFormat, timestamp: scheduleDate, alwaysShowTime: true, allowYesterday: false, format: HumanReadableStringFormat(dateFormatString: { strings.Notification_VoiceChatScheduled(authorName, $0) }, tomorrowFormatString: { strings.Notification_VoiceChatScheduledTomorrow(authorName, $0) }, todayFormatString: { strings.Notification_VoiceChatScheduledToday(authorName, $0) }))
                        let attributePeerIds: [(Int, PeerId?)] = [(0, message.author?.id)]
                        attributedString = addAttributesToStringWithRanges(titleString._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: attributePeerIds))
                    }
                } else if let duration = duration {
                    if message.author?.id.namespace == Namespaces.Peer.CloudChannel {
                        let titleString: String
                        if let channel = message.author as? TelegramChannel, case .broadcast = channel.info {
                            titleString = strings.Notification_LiveStreamEnded(callDurationString(strings: strings, value: duration)).string
                        } else {
                            titleString = strings.Notification_VoiceChatEnded(callDurationString(strings: strings, value: duration)).string
                        }
                        attributedString = NSAttributedString(string: titleString, font: titleFont, textColor: primaryTextColor)
                    } else {
                        let attributePeerIds: [(Int, PeerId?)] = [(0, message.author?.id)]
                        let titleString = strings.Notification_VoiceChatEndedGroup(authorName, callDurationString(strings: strings, value: duration))
                        attributedString = addAttributesToStringWithRanges(titleString._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: attributePeerIds))
                    }
                } else {
                    if message.author?.id.namespace == Namespaces.Peer.CloudChannel {
                        let titleString: String
                        if let channel = message.author as? TelegramChannel, case .broadcast = channel.info {
                            titleString = strings.Notification_LiveStreamStarted
                        } else {
                            titleString = strings.Notification_VoiceChatStartedChannel
                        }
                        attributedString = NSAttributedString(string: titleString, font: titleFont, textColor: primaryTextColor)
                    } else {
                        let attributePeerIds: [(Int, PeerId?)] = [(0, message.author?.id)]
                        let titleString = strings.Notification_VoiceChatStarted(authorName)
                        attributedString = addAttributesToStringWithRanges(titleString._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: attributePeerIds))
                    }
                }
            case let .customText(text, entities):
                attributedString = stringWithAppliedEntities(text, entities: entities, baseColor: primaryTextColor, linkColor: primaryTextColor, baseFont: titleFont, linkFont: titleBoldFont, boldFont: titleBoldFont, italicFont: titleFont, boldItalicFont: titleBoldFont, fixedFont: titleFont, blockQuoteFont: titleFont, underlineLinks: false)
            case let .botDomainAccessGranted(domain):
                attributedString = NSAttributedString(string: strings.AuthSessions_Message(domain).string, font: titleFont, textColor: primaryTextColor)
            case let .botSentSecureValues(types):
                var typesString = ""
                var hasIdentity = false
                var hasAddress = false
                for type in types {
                    if !typesString.isEmpty {
                        typesString.append(", ")
                    }
                    switch type {
                    case .personalDetails:
                        typesString.append(strings.Notification_PassportValuePersonalDetails)
                    case .passport, .internalPassport, .driversLicense, .idCard:
                        if !hasIdentity {
                            typesString.append(strings.Notification_PassportValueProofOfIdentity)
                            hasIdentity = true
                        }
                    case .address:
                        typesString.append(strings.Notification_PassportValueAddress)
                    case .bankStatement, .utilityBill, .rentalAgreement, .passportRegistration, .temporaryRegistration:
                        if !hasAddress {
                            typesString.append(strings.Notification_PassportValueProofOfAddress)
                            hasAddress = true
                        }
                    case .phone:
                        typesString.append(strings.Notification_PassportValuePhone)
                    case .email:
                        typesString.append(strings.Notification_PassportValueEmail)
                    }
                }
                attributedString = NSAttributedString(string: strings.Notification_PassportValuesSentMessage(message.peers[message.id.peerId]?.compactDisplayTitle ?? "", typesString).string, font: titleFont, textColor: primaryTextColor)
            case .peerJoined:
                attributedString = addAttributesToStringWithRanges(strings.Notification_Joined(authorName)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, message.author?.id)]))
            case .phoneNumberRequest:
                attributedString = nil
            case let .geoProximityReached(fromId, toId, distance):
                let distanceString = stringForDistance(strings: strings, distance: Double(distance))
                if fromId == accountPeerId {
                    attributedString = addAttributesToStringWithRanges(strings.Notification_ProximityYouReached(distanceString, message.peers[toId]?.displayTitle(strings: strings, displayOrder: nameDisplayOrder) ?? "")._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(1, toId)]))
                } else if toId == accountPeerId {
                    attributedString = addAttributesToStringWithRanges(strings.Notification_ProximityReachedYou(message.peers[fromId]?.displayTitle(strings: strings, displayOrder: nameDisplayOrder) ?? "", distanceString)._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, fromId)]))
                } else {
                    attributedString = addAttributesToStringWithRanges(strings.Notification_ProximityReached(message.peers[fromId]?.displayTitle(strings: strings, displayOrder: nameDisplayOrder) ?? "", distanceString, message.peers[toId]?.displayTitle(strings: strings, displayOrder: nameDisplayOrder) ?? "")._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: [(0, fromId), (2, toId)]))
                }
            case let .inviteToGroupPhoneCall(_, _, peerIds):
                var attributePeerIds: [(Int, PeerId?)] = [(0, message.author?.id)]
                let resultTitleString: PresentationStrings.FormattedString
                if peerIds.count == 1 {
                    if peerIds[0] == accountPeerId {
                        attributePeerIds.append((1, peerIds.first))
                        resultTitleString = strings.Notification_VoiceChatInvitationForYou(authorName)
                    } else {
                        attributePeerIds.append((1, peerIds.first))
                        resultTitleString = strings.Notification_VoiceChatInvitation(authorName, peerDebugDisplayTitles(peerIds, message.peers))
                    }
                } else {
                    resultTitleString = strings.Notification_VoiceChatInvitation(authorName, peerDebugDisplayTitles(peerIds, message.peers))
                }
                
                attributedString = addAttributesToStringWithRanges(resultTitleString._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: attributePeerIds))
            case let .setChatTheme(emoji):
                if emoji.isEmpty {
                    if message.author?.id.namespace == Namespaces.Peer.CloudChannel {
                        attributedString = NSAttributedString(string: strings.Notification_ChannelDisabledTheme, font: titleFont, textColor: primaryTextColor)
                    } else if message.author?.id == accountPeerId {
                        attributedString = NSAttributedString(string: strings.Notification_YouDisabledTheme, font: titleFont, textColor: primaryTextColor)
                    } else {
                        let attributePeerIds: [(Int, PeerId?)] = [(0, message.author?.id)]
                        let resultTitleString = strings.Notification_DisabledTheme(authorName)
                        attributedString = addAttributesToStringWithRanges(resultTitleString._tuple, body: bodyAttributes, argumentAttributes: peerMentionsAttributes(primaryTextColor: primaryTextColor, peerIds: attributePeerIds))
                    }
                } else {
                    if message.author?.id.namespace == Namespaces.Peer.CloudChannel {
                        attributedString = NSAttributedString(string: strings.Notification_ChannelChangedTheme(emoji).string, font: titleFont, textColor: primaryTextColor)
                    } else if message.author?.id == accountPeerId {
                        attributedString = NSAttributedString(string: strings.Notification_YouChangedTheme(emoji).string, font: titleFont, textColor: primaryTextColor)
                    } else {
                        let resultTitleString = strings.Notification_ChangedTheme(authorName, emoji)
                        attributedString = addAttributesToStringWithRanges(resultTitleString._tuple, body: bodyAttributes, argumentAttributes: [0: boldAttributes])
                    }
                }
            case .unknown:
                attributedString = nil
            }
            
            break
        } else if let expiredMedia = media as? TelegramMediaExpiredContent {
            switch expiredMedia.data {
            case .image:
                attributedString = NSAttributedString(string: strings.Message_ImageExpired, font: titleFont, textColor: primaryTextColor)
            case .file:
                attributedString = NSAttributedString(string: strings.Message_VideoExpired, font: titleFont, textColor: primaryTextColor)
            }
        }
    }
    
    return attributedString
}
