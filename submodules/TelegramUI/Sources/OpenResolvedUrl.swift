import Foundation
import UIKit
import AsyncDisplayKit
import TelegramCore
import Postbox
import Display
import SwiftSignalKit
import TelegramUIPreferences
import TelegramPresentationData
import AccountContext
import OverlayStatusController
import AlertUI
import PresentationDataUtils
import PassportUI
import InstantPageUI
import StickerPackPreviewUI
import JoinLinkPreviewUI
import LanguageLinkPreviewUI
import SettingsUI
import UrlHandling
import ShareController
import ChatInterfaceState
import TelegramCallsUI
import UndoUI
import ImportStickerPackUI

private func defaultNavigationForPeerId(_ peerId: PeerId?, navigation: ChatControllerInteractionNavigateToPeer) -> ChatControllerInteractionNavigateToPeer {
    if case .default = navigation {
        if let peerId = peerId {
            if peerId.namespace == Namespaces.Peer.CloudUser {
                return .chat(textInputState: nil, subject: nil, peekData: nil)
            } else {
                return .chat(textInputState: nil, subject: nil, peekData: nil)
            }
        } else {
            return .info
        }
    } else {
        return navigation
    }
}

func openResolvedUrlImpl(_ resolvedUrl: ResolvedUrl, context: AccountContext, urlContext: OpenURLContext, navigationController: NavigationController?, openPeer: @escaping (PeerId, ChatControllerInteractionNavigateToPeer) -> Void, sendFile: ((FileMediaReference) -> Void)?, sendSticker: ((FileMediaReference, ASDisplayNode, CGRect) -> Bool)?, requestMessageActionUrlAuth: ((MessageActionUrlSubject) -> Void)? = nil, joinVoiceChat: ((PeerId, String?, CachedChannelData.ActiveCall) -> Void)?, present: @escaping (ViewController, Any?) -> Void, dismissInput: @escaping () -> Void, contentContext: Any?) {
    let updatedPresentationData: (initial: PresentationData, signal: Signal<PresentationData, NoError>)?
    if case let .chat(maybeUpdatedPresentationData) = urlContext {
        updatedPresentationData = maybeUpdatedPresentationData
    } else {
        updatedPresentationData = nil
    }
    let presentationData = updatedPresentationData?.initial ?? context.sharedContext.currentPresentationData.with { $0 }
    switch resolvedUrl {
        case let .externalUrl(url):
            context.sharedContext.openExternalUrl(context: context, urlContext: urlContext, url: url, forceExternal: false, presentationData: context.sharedContext.currentPresentationData.with { $0 }, navigationController: navigationController, dismissInput: dismissInput)
        case let .urlAuth(url):
            requestMessageActionUrlAuth?(.url(url))
            dismissInput()
            break
        case let .peer(peerId, navigation):
            if let peerId = peerId {
                openPeer(peerId, defaultNavigationForPeerId(peerId, navigation: navigation))
            } else {
                present(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: presentationData.strings.Resolve_ErrorNotFound, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
            }
        case .inaccessiblePeer:
            present(standardTextAlertController(theme: AlertControllerTheme(presentationData: presentationData), title: nil, text: presentationData.strings.Conversation_ErrorInaccessibleMessage, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
        case let .botStart(peerId, payload):
            openPeer(peerId, .withBotStartPayload(ChatControllerInitialBotStart(payload: payload, behavior: .interactive)))
        case let .groupBotStart(botPeerId, payload):
            let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyWriteable, .onlyGroups, .onlyManageable], title: presentationData.strings.UserInfo_InviteBotToGroup))
            controller.peerSelected = { [weak controller] peer in
                let peerId = peer.id
                
                if payload.isEmpty {
                    if peerId.namespace == Namespaces.Peer.CloudGroup {
                        let _ = (context.engine.peers.addGroupMember(peerId: peerId, memberId: botPeerId)
                        |> deliverOnMainQueue).start(completed: {
                            controller?.dismiss()
                        })
                    } else {
                        let _ = (context.engine.peers.addChannelMember(peerId: peerId, memberId: botPeerId)
                        |> deliverOnMainQueue).start(completed: {
                            controller?.dismiss()
                        })
                    }
                } else {
                    let _ = (context.engine.messages.requestStartBotInGroup(botPeerId: botPeerId, groupPeerId: peerId, payload: payload)
                    |> deliverOnMainQueue).start(next: { result in
                        if let navigationController = navigationController {
                            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peerId)))
                        }
                        switch result {
                            case let .channelParticipant(participant):
                                context.peerChannelMemberCategoriesContextsManager.externallyAdded(peerId: peerId, participant: participant)
                            case .none:
                                break
                        }
                        controller?.dismiss()
                    }, error: { _ in
                        
                    })
                }
            }
            dismissInput()
            navigationController?.pushViewController(controller)
        case let .channelMessage(peerId, messageId, timecode):
            openPeer(peerId, .chat(textInputState: nil, subject: .message(id: messageId, highlight: true, timecode: timecode), peekData: nil))
        case let .replyThreadMessage(replyThreadMessage, messageId):
            if let navigationController = navigationController {
                let _ = ChatControllerImpl.openMessageReplies(context: context, navigationController: navigationController, present: { c, a in
                    present(c, a)
                }, messageId: replyThreadMessage.messageId, isChannelPost: replyThreadMessage.isChannelPost, atMessage: messageId, displayModalProgress: true).start()
            }
        case let .stickerPack(name):
            dismissInput()
            if false {
                var mainStickerPack: StickerPackReference?
                var stickerPacks: [StickerPackReference] = []
                if let message = contentContext as? Message {
                    let dataDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType([.link]).rawValue)
                    if let matches = dataDetector?.matches(in: message.text, options: [], range: NSRange(message.text.startIndex ..< message.text.endIndex, in: message.text)) {
                        for match in matches {
                            guard let stringRange = Range(match.range, in: message.text) else {
                                continue
                            }
                            let urlText = String(message.text[stringRange])
                            if let resultName = parseStickerPackUrl(urlText) {
                                stickerPacks.append(.name(resultName))
                                if resultName == name {
                                    mainStickerPack = .name(resultName)
                                }
                            }
                        }
                        if mainStickerPack == nil {
                            mainStickerPack = .name(name)
                            stickerPacks.insert(.name(name), at: 0)
                        }
                    } else {
                        mainStickerPack = .name(name)
                        stickerPacks = [.name(name)]
                    }
                } else {
                    mainStickerPack = .name(name)
                    stickerPacks = [.name(name)]
                }
                if let mainStickerPack = mainStickerPack, !stickerPacks.isEmpty {
                    let controller = StickerPackScreen(context: context, updatedPresentationData: updatedPresentationData, mainStickerPack: mainStickerPack, stickerPacks: stickerPacks, parentNavigationController: navigationController, sendSticker: sendSticker)
                    present(controller, nil)
                }
            } else {
                let controller = StickerPackScreen(context: context, updatedPresentationData: updatedPresentationData, mainStickerPack: .name(name), stickerPacks: [.name(name)], parentNavigationController: navigationController, sendSticker: sendSticker)
                present(controller, nil)
            }
        case let .instantView(webpage, anchor):
            navigationController?.pushViewController(InstantPageController(context: context, webPage: webpage, sourcePeerType: .channel, anchor: anchor))
        case let .join(link):
            dismissInput()
            present(JoinLinkPreviewController(context: context, link: link, navigateToPeer: { peerId, peekData in
                openPeer(peerId, .chat(textInputState: nil, subject: nil, peekData: peekData))
            }, parentNavigationController: navigationController), nil)
        case let .localization(identifier):
            dismissInput()
            present(LanguageLinkPreviewController(context: context, identifier: identifier), nil)
        case let .proxy(host, port, username, password, secret):
            let server: ProxyServerSettings
            if let secret = secret {
                server = ProxyServerSettings(host: host, port: abs(port), connection: .mtp(secret: secret))
            } else {
                server = ProxyServerSettings(host: host, port: abs(port), connection: .socks5(username: username, password: password))
            }

            dismissInput()
            present(ProxyServerActionSheetController(context: context, server: server), nil)
        case let .confirmationCode(code):
            if let topController = navigationController?.topViewController as? ChangePhoneNumberCodeController {
                topController.applyCode(code)
            } else {
                var found = false
                navigationController?.currentWindow?.forEachController({ controller in
                    if let controller = controller as? SecureIdPlaintextFormController {
                        controller.applyPhoneCode(code)
                        found = true
                    }
                })
                if !found {
                    present(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: presentationData.strings.AuthCode_Alert(formattedConfirmationCode(code)).string, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                }
            }
        case let .cancelAccountReset(phone, hash):
            let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
            present(controller, nil)
            let _ = (context.engine.auth.requestCancelAccountResetData(hash: hash)
            |> deliverOnMainQueue).start(next: { [weak controller] data in
                controller?.dismiss()
                present(confirmPhoneNumberCodeController(context: context, phoneNumber: phone, codeData: data), ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            }, error: { [weak controller] error in
                controller?.dismiss()
                
                let text: String
                switch error {
                    case .limitExceeded:
                        text = presentationData.strings.Login_CodeFloodError
                    case .generic:
                        text = presentationData.strings.Login_UnknownError
                }
                present(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
            })
            dismissInput()
        case let .share(url, text, to):
            let continueWithPeer: (PeerId) -> Void = { peerId in
                let textInputState: ChatTextInputState?
                if let text = text, !text.isEmpty {
                    if let url = url, !url.isEmpty {
                        let urlString = NSMutableAttributedString(string: "\(url)\n")
                        let textString = NSAttributedString(string: "\(text)")
                        let selectionRange: Range<Int> = urlString.length ..< (urlString.length + textString.length)
                        urlString.append(textString)
                        textInputState = ChatTextInputState(inputText: urlString, selectionRange: selectionRange)
                    } else {
                        textInputState = ChatTextInputState(inputText: NSAttributedString(string: "\(text)"))
                    }
                } else if let url = url, !url.isEmpty {
                    textInputState = ChatTextInputState(inputText: NSAttributedString(string: "\(url)"))
                } else {
                    textInputState = nil
                }
                
                if let textInputState = textInputState {
                    let _ = (ChatInterfaceState.update(engine: context.engine, peerId: peerId, threadId: nil, { currentState in
                        return currentState.withUpdatedComposeInputState(textInputState)
                    })
                    |> deliverOnMainQueue).start(completed: {
                        navigationController?.pushViewController(ChatControllerImpl(context: context, chatLocation: .peer(peerId)))
                    })
                } else {
                    navigationController?.pushViewController(ChatControllerImpl(context: context, chatLocation: .peer(peerId)))
                }
            }
            
            if let to = to {
                if to.hasPrefix("@") {
                    let _ = (context.engine.peers.resolvePeerByName(name: String(to[to.index(to.startIndex, offsetBy: 1)...]))
                    |> deliverOnMainQueue).start(next: { peer in
                        if let peer = peer {
                            context.sharedContext.applicationBindings.dismissNativeController()
                            continueWithPeer(peer.id)
                        }
                    })
                } else {
                    let query = to.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789").inverted)
                    let _ = (context.account.postbox.searchContacts(query: query)
                    |> deliverOnMainQueue).start(next: { (peers, _) in
                        for case let peer as TelegramUser in peers {
                            if peer.phone == query {
                                context.sharedContext.applicationBindings.dismissNativeController()
                                continueWithPeer(peer.id)
                                break
                            }
                        }
                    })
                }
            } else {
                if let url = url, !url.isEmpty {
                    let shareController = ShareController(context: context, subject: .url(url), presetText: text, externalShare: false, immediateExternalShare: false)
                    shareController.actionCompleted = {
                        present(UndoOverlayController(presentationData: presentationData, content: .linkCopied(text: presentationData.strings.Conversation_LinkCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), nil)
                    }
                    present(shareController, nil)
                    context.sharedContext.applicationBindings.dismissNativeController()
                } else {
                    let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyWriteable, .excludeDisabled]))
                    controller.peerSelected = { [weak controller] peer in
                        let peerId = peer.id
                        
                        if let strongController = controller {
                            strongController.dismiss()
                            continueWithPeer(peerId)
                        }
                    }
                    context.sharedContext.applicationBindings.dismissNativeController()
                    navigationController?.pushViewController(controller)
                }
            }
        case let .wallpaper(parameter):
            var controller: ViewController?
            
            let signal: Signal<TelegramWallpaper, GetWallpaperError>
            var options: WallpaperPresentationOptions?
            var colors: [UInt32] = []
            var intensity: Int32?
            var rotation: Int32?
            switch parameter {
                case let .slug(slug, wallpaperOptions, colorsValue, intensityValue, rotationValue):
                    signal = getWallpaper(network: context.account.network, slug: slug)
                    options = wallpaperOptions
                    colors = colorsValue
                    intensity = intensityValue
                    rotation = rotationValue
                    controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                    present(controller!, nil)
                case let .color(color):
                    signal = .single(.color(color.argb))
                case let .gradient(colors, rotation):
                    signal = .single(.gradient(TelegramWallpaper.Gradient(id: nil, colors: colors, settings: WallpaperSettings(rotation: rotation))))
            }
            
            let _ = (signal
            |> deliverOnMainQueue).start(next: { [weak controller] wallpaper in
                controller?.dismiss()
                let galleryController = WallpaperGalleryController(context: context, source: .wallpaper(wallpaper, options, colors, intensity, rotation, nil))
                present(galleryController, nil)
            }, error: { [weak controller] error in
                controller?.dismiss()
            })
            dismissInput()
        case let .theme(slug):
            let signal = getTheme(account: context.account, slug: slug)
            |> mapToSignal { themeInfo -> Signal<(Data?, TelegramThemeSettings?, TelegramTheme), GetThemeError> in
                return Signal<(Data?, TelegramThemeSettings?, TelegramTheme), GetThemeError> { subscriber in
                    let disposables = DisposableSet()
                    if let settings = themeInfo.settings {
                        subscriber.putNext((nil, settings, themeInfo))
                        subscriber.putCompletion()
                    } else if let resource = themeInfo.file?.resource {
                        disposables.add(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, reference: .standalone(resource: resource)).start())
                        
                        let maybeFetched = context.sharedContext.accountManager.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false), attemptSynchronously: false)
                        |> mapToSignal { maybeData -> Signal<Data?, NoError> in
                            if maybeData.complete {
                                let loadedData = try? Data(contentsOf: URL(fileURLWithPath: maybeData.path), options: [])
                                return .single(loadedData)
                            } else {
                                return context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false), attemptSynchronously: false)
                                |> map { next -> Data? in
                                    if next.size > 0, let data = try? Data(contentsOf: URL(fileURLWithPath: next.path), options: []) {
                                        context.sharedContext.accountManager.mediaBox.storeResourceData(resource.id, data: data)
                                        return data
                                    } else {
                                        return nil
                                    }
                                }
                            }
                        }
                   
                        disposables.add(maybeFetched.start(next: { data in
                            if let data = data {
                                subscriber.putNext((data, nil, themeInfo))
                                subscriber.putCompletion()
                            }
                        }))
                    } else {
                        subscriber.putError(.unsupported)
                    }
                    
                    return disposables
                }
            }
            
            var cancelImpl: (() -> Void)?
            let progressSignal = Signal<Never, NoError> { subscriber in
                let controller = OverlayStatusController(theme: presentationData.theme,  type: .loading(cancelled: {
                    cancelImpl?()
                }))
                present(controller, nil)
                return ActionDisposable { [weak controller] in
                    Queue.mainQueue().async() {
                        controller?.dismiss()
                    }
                }
            }
            |> runOn(Queue.mainQueue())
            |> delay(0.35, queue: Queue.mainQueue())
            
            let disposable = MetaDisposable()
            let progressDisposable = progressSignal.start()
            cancelImpl = {
                disposable.set(nil)
            }
            disposable.set((signal
            |> afterDisposed {
                Queue.mainQueue().async {
                    progressDisposable.dispose()
                }
            }
            |> deliverOnMainQueue).start(next: { dataAndTheme in
                if let data = dataAndTheme.0 {
                    if let theme = makePresentationTheme(data: data) {
                        let previewController = ThemePreviewController(context: context, previewTheme: theme, source: .theme(dataAndTheme.2))
                        navigationController?.pushViewController(previewController)
                    }
                } else if let settings = dataAndTheme.1 {
                    if let theme = makePresentationTheme(mediaBox: context.sharedContext.accountManager.mediaBox, themeReference: .builtin(PresentationBuiltinThemeReference(baseTheme: settings.baseTheme)), accentColor: UIColor(argb: settings.accentColor), backgroundColors: [], bubbleColors: settings.messageColors, wallpaper: settings.wallpaper) {
                        let previewController = ThemePreviewController(context: context, previewTheme: theme, source: .theme(dataAndTheme.2))
                        navigationController?.pushViewController(previewController)
                    }
                }
            }, error: { error in
                let errorText: String
                switch error {
                    case .generic, .slugInvalid:
                        errorText = presentationData.strings.Theme_ErrorNotFound
                    case .unsupported:
                        errorText = presentationData.strings.Theme_Unsupported
                }
                present(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: errorText, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
            }))
            dismissInput()
        #if ENABLE_WALLET
        case let .wallet(address, amount, comment):
            dismissInput()
            context.sharedContext.openWallet(context: context, walletContext: .send(address: address, amount: amount, comment: comment)) { c in
                navigationController?.pushViewController(c)
            }
        #endif
        case let .settings(section):
            dismissInput()
            switch section {
                case .theme:
                    if let navigationController = navigationController {
                        let controller = themeSettingsController(context: context)
                        controller.navigationPresentation = .modal
                        
                        var controllers = navigationController.viewControllers
                        controllers = controllers.filter { !($0 is ThemeSettingsController) }
                        controllers.append(controller)
                        
                        navigationController.setViewControllers(controllers, animated: true)
                    }
                case .devices:
                    if let navigationController = navigationController {
                        let activeSessions = deferred { () -> Signal<(ActiveSessionsContext, Int, WebSessionsContext), NoError> in
                            let activeSessionsContext = context.engine.privacy.activeSessions()
                            let webSessionsContext = context.engine.privacy.webSessions()
                            let otherSessionCount = activeSessionsContext.state
                            |> map { state -> Int in
                                return state.sessions.filter({ !$0.isCurrent }).count
                            }
                            |> distinctUntilChanged
                            
                            return otherSessionCount
                            |> map { value in
                                return (activeSessionsContext, value, webSessionsContext)
                            }
                        }
                        
                        let _ = (activeSessions
                        |> take(1)
                        |> deliverOnMainQueue).start(next: { activeSessionsContext, count, webSessionsContext in
                            let controller = recentSessionsController(context: context, activeSessionsContext: activeSessionsContext, webSessionsContext: webSessionsContext, websitesOnly: false)
                            controller.navigationPresentation = .modal
                            
                            var controllers = navigationController.viewControllers
                            controllers = controllers.filter { !($0 is RecentSessionsController) }
                            controllers.append(controller)
                            
                            navigationController.setViewControllers(controllers, animated: true)
                        })
                    }
                    break
            }
        case let .joinVoiceChat(peerId, invite):
            dismissInput()
            if let navigationController = navigationController {
                context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peerId), completion: { chatController in
                    guard let chatController = chatController as? ChatControllerImpl else {
                        return
                    }
                    navigationController.currentWindow?.present(VoiceChatJoinScreen(context: context, peerId: peerId, invite: invite, join: { [weak chatController] call in
                        chatController?.joinGroupCall(peerId: peerId, invite: invite, activeCall: EngineGroupCallDescription(call))
                    }), on: .root, blockInteraction: false, completion: {})
                }))
            }
        case .importStickers:
            dismissInput()
            if let navigationController = navigationController, let data = UIPasteboard.general.data(forPasteboardType: "org.telegram.third-party.stickerset"), let stickerPack = ImportStickerPack(data: data), !stickerPack.stickers.isEmpty {
                for controller in navigationController.overlayControllers {
                    if controller is ImportStickerPackController {
                        controller.dismiss()
                    }
                }
                let controller = ImportStickerPackController(context: context, stickerPack: stickerPack, parentNavigationController: navigationController)
                present(controller, nil)
            }
    }
}
