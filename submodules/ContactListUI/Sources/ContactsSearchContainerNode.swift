import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import MergeLists
import AccountContext
import SearchUI
import ChatListSearchItemHeader
import ContactsPeerItem
import ContextUI
import PhoneNumberFormat
import ItemListUI

private enum ContactListSearchGroup {
    case contacts
    case global
    case deviceContacts
}

private enum ContactListSearchEntryId: Hashable {
    case addContact
    case peerId(ContactListPeerId)
    
    static func <(lhs: ContactListSearchEntryId, rhs: ContactListSearchEntryId) -> Bool {
        return lhs.hashValue < rhs.hashValue
    }
    
    static func ==(lhs: ContactListSearchEntryId, rhs: ContactListSearchEntryId) -> Bool {
        switch lhs {
            case .addContact:
                switch rhs {
                    case .addContact:
                        return true
                    default:
                        return false
                }
            case let .peerId(lhsId):
                switch rhs {
                    case let .peerId(rhsId):
                        return lhsId == rhsId
                    default:
                        return false
                }
        }
    }
}

private enum ContactListSearchEntry: Comparable, Identifiable {
    case addContact(PresentationTheme, PresentationStrings, String)
    case peer(Int, PresentationTheme, PresentationStrings, ContactListPeer, PeerPresence?, ContactListSearchGroup, Bool)
    
    var stableId: ContactListSearchEntryId {
        switch self {
            case .addContact:
                return .addContact
            case let .peer(_, _, _, peer, _, _, _):
                return .peerId(peer.id)
        }
    }
    
    static func ==(lhs: ContactListSearchEntry, rhs: ContactListSearchEntry) -> Bool {
        switch lhs {
            case let .addContact(lhsTheme, lhsStrings, lhsPhoneNumber):
                if case let .addContact(rhsTheme, rhsStrings, rhsPhoneNumber) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsPhoneNumber == rhsPhoneNumber {
                    return true
                } else {
                    return false
                }
            case let .peer(lhsIndex, lhsTheme, lhsStrings, lhsPeer, lhsPresence, lhsGroup, lhsEnabled):
                switch rhs {
                    case let .peer(rhsIndex, rhsTheme, rhsStrings, rhsPeer, rhsPresence, rhsGroup, rhsEnabled):
                        if lhsIndex != rhsIndex {
                            return false
                        }
                        if lhsTheme !== rhsTheme {
                            return false
                        }
                        if lhsStrings !== rhsStrings {
                            return false
                        }
                        if lhsPeer != rhsPeer {
                            return false
                        }
                        if let lhsPresence = lhsPresence, let rhsPresence = rhsPresence {
                            if !lhsPresence.isEqual(to: rhsPresence) {
                                return false
                            }
                        } else if (lhsPresence != nil) != (rhsPresence != nil) {
                            return false
                        }
                        if lhsGroup != rhsGroup {
                            return false
                        }
                        if lhsEnabled != rhsEnabled {
                            return false
                        }
                        return true
                    default:
                        return false
                }
        }
    }

    static func <(lhs: ContactListSearchEntry, rhs: ContactListSearchEntry) -> Bool {
        switch lhs {
            case .addContact:
                return true
            case let .peer(lhsIndex, _, _, _, _, _, _):
                switch rhs {
                    case .addContact:
                        return false
                    case let .peer(rhsIndex, _, _, _, _, _, _):
                        return lhsIndex < rhsIndex
                }
        }
    }
    
    func item(context: AccountContext, presentationData: PresentationData, nameSortOrder: PresentationPersonNameOrder, nameDisplayOrder: PresentationPersonNameOrder, timeFormat: PresentationDateTimeFormat, addContact: ((String) -> Void)?, openPeer: @escaping (ContactListPeer) -> Void, contextAction: ((Peer, ASDisplayNode, ContextGesture?) -> Void)?) -> ListViewItem {
        switch self {
            case let .addContact(theme, strings, phoneNumber):
                return ContactsAddItem(theme: theme, strings: strings, phoneNumber: phoneNumber, header: ChatListSearchItemHeader(type: .phoneNumber, theme: theme, strings: strings, actionTitle: nil, action: nil), action: {
                    addContact?(phoneNumber)
                })
            case let .peer(_, theme, strings, peer, presence, group, enabled):
                let header: ListViewItemHeader
                let status: ContactsPeerItemStatus
                switch group {
                    case .contacts:
                        header = ChatListSearchItemHeader(type: .contacts, theme: theme, strings: strings, actionTitle: nil, action: nil)
                        if let presence = presence {
                            status = .presence(presence, timeFormat)
                        } else {
                            status = .none
                        }
                    case .global:
                        header = ChatListSearchItemHeader(type: .globalPeers, theme: theme, strings: strings, actionTitle: nil, action: nil)
                        if case let .peer(peer, _, _) = peer, let _ = peer.addressName {
                            status = .addressName("")
                        } else {
                            status = .none
                        }
                    case .deviceContacts:
                        header = ChatListSearchItemHeader(type: .deviceContacts, theme: theme, strings: strings, actionTitle: nil, action: nil)
                        status = .none
                }
                var nativePeer: Peer?
                let peerItem: ContactsPeerItemPeer
                switch peer {
                    case let .peer(peer, _, _):
                        peerItem = .peer(peer: peer, chatPeer: peer)
                        nativePeer = peer
                    case let .deviceContact(stableId, contact):
                        peerItem = .deviceContact(stableId: stableId, contact: contact)
                }
                return ContactsPeerItem(presentationData: ItemListPresentationData(presentationData), sortOrder: nameSortOrder, displayOrder: nameDisplayOrder, context: context, peerMode: .peer, peer: peerItem, status: status, enabled: enabled, selection: .none, editing: ContactsPeerItemEditing(editable: false, editing: false, revealed: false), index: nil, header: header, action: { _ in
                    openPeer(peer)
                }, contextAction: contextAction.flatMap { contextAction in
                    return nativePeer.flatMap { nativePeer in
                        return { node, gesture in
                            contextAction(nativePeer, node, gesture)
                        }
                    }
                })
        }
    }
}

struct ContactListSearchContainerTransition {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
    let isSearching: Bool
}

private func contactListSearchContainerPreparedRecentTransition(from fromEntries: [ContactListSearchEntry], to toEntries: [ContactListSearchEntry], isSearching: Bool, context: AccountContext, presentationData: PresentationData, nameSortOrder: PresentationPersonNameOrder, nameDisplayOrder: PresentationPersonNameOrder, timeFormat: PresentationDateTimeFormat, addContact: ((String) -> Void)?, openPeer: @escaping (ContactListPeer) -> Void, contextAction: ((Peer, ASDisplayNode, ContextGesture?) -> Void)?) -> ContactListSearchContainerTransition {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries)
    
    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(context: context, presentationData: presentationData, nameSortOrder: nameSortOrder, nameDisplayOrder: nameDisplayOrder, timeFormat: timeFormat, addContact: addContact, openPeer: openPeer, contextAction: contextAction), directionHint: nil) }
    let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(context: context, presentationData: presentationData, nameSortOrder: nameSortOrder, nameDisplayOrder: nameDisplayOrder, timeFormat: timeFormat, addContact: addContact, openPeer: openPeer, contextAction: contextAction), directionHint: nil) }
    
    return ContactListSearchContainerTransition(deletions: deletions, insertions: insertions, updates: updates, isSearching: isSearching)
}

public struct ContactsSearchCategories: OptionSet {
    public var rawValue: Int32
    
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
    
    public static let cloudContacts = ContactsSearchCategories(rawValue: 1 << 0)
    public static let global = ContactsSearchCategories(rawValue: 1 << 1)
    public static let deviceContacts = ContactsSearchCategories(rawValue: 1 << 2)
}

public final class ContactsSearchContainerNode: SearchDisplayControllerContentNode {
    private let context: AccountContext
    private let addContact: ((String) -> Void)?
    private let openPeer: (ContactListPeer) -> Void
    private let contextAction: ((Peer, ASDisplayNode, ContextGesture?) -> Void)?
    
    private let dimNode: ASDisplayNode
    public let listNode: ListView
    
    private let searchQuery = Promise<String?>()
    private let searchDisposable = MetaDisposable()
    
    private var presentationData: PresentationData
    private let themeAndStringsPromise: Promise<(PresentationTheme, PresentationStrings)>
    
    private var containerViewLayout: (ContainerViewLayout, CGFloat)?
    private var enqueuedTransitions: [ContactListSearchContainerTransition] = []
    
    public override var hasDim: Bool {
        return true
    }
    
    public init(context: AccountContext, updatedPresentationData: (initial: PresentationData, signal: Signal<PresentationData, NoError>)? = nil, onlyWriteable: Bool, categories: ContactsSearchCategories, filters: [ContactListFilter] = [.excludeSelf], addContact: ((String) -> Void)?, openPeer: @escaping (ContactListPeer) -> Void, contextAction: ((Peer, ASDisplayNode, ContextGesture?) -> Void)?) {
        self.context = context
        self.addContact = addContact
        self.openPeer = openPeer
        self.contextAction = contextAction
        
        let presentationData = updatedPresentationData?.initial ?? context.sharedContext.currentPresentationData.with { $0 }
        self.presentationData = presentationData
        
        self.themeAndStringsPromise = Promise((self.presentationData.theme, self.presentationData.strings))
        
        self.dimNode = ASDisplayNode()
        self.dimNode.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        self.listNode = ListView()
        self.listNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        self.listNode.isHidden = true
        self.listNode.accessibilityPageScrolledString = { row, count in
            return presentationData.strings.VoiceOver_ScrollStatus(row, count).string
        }
        
        super.init()
        
        self.backgroundColor = nil
        self.isOpaque = false
        
        self.addSubnode(self.dimNode)
        self.addSubnode(self.listNode)
        
        self.listNode.isHidden = true
        
        let themeAndStringsPromise = self.themeAndStringsPromise
        
        let previousFoundRemoteContacts = Atomic<([FoundPeer], [FoundPeer])?>(value: nil)
        
        let searchItems = self.searchQuery.get()
        |> mapToSignal { query -> Signal<[ContactListSearchEntry]?, NoError> in
            if let query = query, !query.isEmpty {
                let foundLocalContacts: Signal<([Peer], [PeerId: PeerPresence]), NoError>
                if categories.contains(.cloudContacts) {
                    foundLocalContacts = context.account.postbox.searchContacts(query: query.lowercased())
                } else {
                    foundLocalContacts = .single(([], [:]))
                }
                let foundRemoteContacts: Signal<([FoundPeer], [FoundPeer])?, NoError>
                if categories.contains(.global) {
                    foundRemoteContacts = .single(previousFoundRemoteContacts.with({ $0 }))
                    |> then(
                        context.engine.peers.searchPeers(query: query)
                        |> map { ($0.0, $0.1) }
                        |> delay(0.2, queue: Queue.concurrentDefaultQueue())
                    )
                } else {
                    foundRemoteContacts = .single(([], []))
                }
                let searchDeviceContacts = categories.contains(.deviceContacts)
                let foundDeviceContacts: Signal<[DeviceContactStableId: (DeviceContactBasicData, PeerId?)]?, NoError>
                if searchDeviceContacts, let contactDataManager = context.sharedContext.contactDataManager {
                    foundDeviceContacts = contactDataManager.search(query: query)
                    |> map(Optional.init)
                } else {
                    foundDeviceContacts = .single([:])
                }
                
                return combineLatest(foundLocalContacts, foundRemoteContacts, foundDeviceContacts, themeAndStringsPromise.get())
                |> delay(0.1, queue: Queue.concurrentDefaultQueue())
                |> map { localPeersAndPresences, remotePeers, deviceContacts, themeAndStrings -> [ContactListSearchEntry] in
                    let _ = previousFoundRemoteContacts.swap(remotePeers)
                    
                    var entries: [ContactListSearchEntry] = []
                    var existingPeerIds = Set<PeerId>()
                    var disabledPeerIds = Set<PeerId>()
                    for filter in filters {
                        switch filter {
                            case .excludeSelf:
                                existingPeerIds.insert(context.account.peerId)
                            case let .exclude(peerIds):
                                existingPeerIds = existingPeerIds.union(peerIds)
                            case let .disable(peerIds):
                                disabledPeerIds = disabledPeerIds.union(peerIds)
                        }
                    }
                    var existingNormalizedPhoneNumbers = Set<DeviceContactNormalizedPhoneNumber>()
                    var index = 0
                    for peer in localPeersAndPresences.0 {
                        if existingPeerIds.contains(peer.id) {
                            continue
                        }
                        existingPeerIds.insert(peer.id)
                        var enabled = true
                        if onlyWriteable {
                            enabled = canSendMessagesToPeer(peer)
                        }
                        entries.append(.peer(index, themeAndStrings.0, themeAndStrings.1, .peer(peer: peer, isGlobal: false, participantCount: nil), localPeersAndPresences.1[peer.id], .contacts, enabled))
                        if searchDeviceContacts, let user = peer as? TelegramUser, let phone = user.phone {
                            existingNormalizedPhoneNumbers.insert(DeviceContactNormalizedPhoneNumber(rawValue: formatPhoneNumber(phone)))
                        }
                        index += 1
                    }
                    if let remotePeers = remotePeers {
                        for peer in remotePeers.0 {
                            if !(peer.peer is TelegramUser) {
                                continue
                            }
                            if !existingPeerIds.contains(peer.peer.id) {
                                existingPeerIds.insert(peer.peer.id)
                                
                                var enabled = true
                                if onlyWriteable {
                                    enabled = canSendMessagesToPeer(peer.peer)
                                }
                                
                                entries.append(.peer(index, themeAndStrings.0, themeAndStrings.1, .peer(peer: peer.peer, isGlobal: true, participantCount: peer.subscribers), nil, .global, enabled))
                                if searchDeviceContacts, let user = peer.peer as? TelegramUser, let phone = user.phone {
                                    existingNormalizedPhoneNumbers.insert(DeviceContactNormalizedPhoneNumber(rawValue: formatPhoneNumber(phone)))
                                }
                                index += 1
                            }
                        }
                        for peer in remotePeers.1 {
                            if !(peer.peer is TelegramUser) {
                                continue
                            }
                            if !existingPeerIds.contains(peer.peer.id) {
                                existingPeerIds.insert(peer.peer.id)
                                
                                var enabled = true
                                if onlyWriteable {
                                    enabled = canSendMessagesToPeer(peer.peer)
                                }
                                
                                entries.append(.peer(index, themeAndStrings.0, themeAndStrings.1, .peer(peer: peer.peer, isGlobal: true, participantCount: peer.subscribers), nil, .global, enabled))
                                if searchDeviceContacts, let user = peer.peer as? TelegramUser, let phone = user.phone {
                                    existingNormalizedPhoneNumbers.insert(DeviceContactNormalizedPhoneNumber(rawValue: formatPhoneNumber(phone)))
                                }
                                index += 1
                            }
                        }
                    }
                    if let _ = remotePeers, let deviceContacts = deviceContacts {
                        outer: for (stableId, contact) in deviceContacts {
                            inner: for phoneNumber in contact.0.phoneNumbers {
                                let normalizedNumber = DeviceContactNormalizedPhoneNumber(rawValue: formatPhoneNumber(phoneNumber.value))
                                if existingNormalizedPhoneNumbers.contains(normalizedNumber) {
                                    continue outer
                                }
                            }
                            if let peerId = contact.1 {
                                if existingPeerIds.contains(peerId) {
                                    continue outer
                                }
                            }
                            entries.append(.peer(index, themeAndStrings.0, themeAndStrings.1, .deviceContact(stableId, contact.0), nil, .deviceContacts, true))
                            index += 1
                        }
                    }
                    
                    if let _ = addContact, isViablePhoneNumber(query) {
                        entries.append(.addContact(themeAndStrings.0, themeAndStrings.1, query))
                    }
                    
                    return entries
                }
            } else {
                let _ = previousFoundRemoteContacts.swap(nil)
                return .single(nil)
            }
        }
        
        let previousSearchItems = Atomic<[ContactListSearchEntry]>(value: [])
        
        self.searchDisposable.set((searchItems
        |> deliverOnMainQueue).start(next: { [weak self] items in
            if let strongSelf = self {
                let previousItems = previousSearchItems.swap(items ?? [])
                
                var addContact: ((String) -> Void)?
                if let originalAddContact = strongSelf.addContact {
                    addContact = { [weak self] phoneNumber in
                        self?.listNode.clearHighlightAnimated(true)
                        originalAddContact(phoneNumber)
                    }
                }
                
                let transition = contactListSearchContainerPreparedRecentTransition(from: previousItems, to: items ?? [], isSearching: items != nil, context: context, presentationData: strongSelf.presentationData, nameSortOrder: strongSelf.presentationData.nameSortOrder, nameDisplayOrder: strongSelf.presentationData.nameDisplayOrder, timeFormat: strongSelf.presentationData.dateTimeFormat, addContact: addContact, openPeer: { peer in
                    self?.listNode.clearHighlightAnimated(true)
                    self?.openPeer(peer)
                }, contextAction: strongSelf.contextAction)
                
                strongSelf.enqueueTransition(transition)
            }
        }))
        
        self.listNode.beganInteractiveDragging = { [weak self] _ in
            self?.dismissInput?()
        }
    }
    
    deinit {
        self.searchDisposable.dispose()
    }
    
    override public func scrollToTop() {
        if !self.listNode.isHidden {
            self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: ListViewScrollToItem(index: 0, position: .top(0.0), animated: true, curve: .Default(duration: nil), directionHint: .Up), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        }
    }
    
    override public func didLoad() {
        super.didLoad()
        
        self.dimNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTapGesture(_:))))
    }
    
    override public func updatePresentationData(_ presentationData: PresentationData) {
        super.updatePresentationData(presentationData)
        
        self.presentationData = presentationData
        self.themeAndStringsPromise.set(.single((presentationData.theme, presentationData.strings)))
        self.listNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
    }
    
    override public func searchTextUpdated(text: String) {
        if text.isEmpty {
            self.searchQuery.set(.single(nil))
        } else {
            self.searchQuery.set(.single(text))
        }
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: transition)
        
        let hadValidLayout = self.containerViewLayout != nil
        self.containerViewLayout = (layout, navigationBarHeight)
        
        let topInset = navigationBarHeight
        transition.updateFrame(node: self.dimNode, frame: CGRect(origin: CGPoint(x: 0.0, y: topInset), size: CGSize(width: layout.size.width, height: layout.size.height - topInset)))
        
        self.listNode.frame = CGRect(origin: CGPoint(), size: layout.size)
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous], scrollToItem: nil, updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: layout.size, insets: UIEdgeInsets(top: topInset, left: layout.safeInsets.left, bottom: layout.intrinsicInsets.bottom, right: layout.safeInsets.right), duration: 0.0, curve: .Default(duration: nil)), stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        if !hadValidLayout {
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
    }
    
    private func enqueueTransition(_ transition: ContactListSearchContainerTransition) {
        self.enqueuedTransitions.append(transition)
        
        if self.containerViewLayout != nil {
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
    }
    
    private func dequeueTransition() {
        if let transition = self.enqueuedTransitions.first {
            self.enqueuedTransitions.remove(at: 0)
            
            var options = ListViewDeleteAndInsertOptions()
            options.insert(.PreferSynchronousDrawing)
            options.insert(.PreferSynchronousResourceLoading)
            
            let isSearching = transition.isSearching
            self.listNode.transaction(deleteIndices: transition.deletions, insertIndicesAndItems: transition.insertions, updateIndicesAndItems: transition.updates, options: options, updateSizeAndInsets: nil, updateOpaqueState: nil, completion: { [weak self] _ in
                self?.listNode.isHidden = !isSearching
                self?.dimNode.isHidden = isSearching
            })
        }
    }
    
    @objc private func dimTapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.cancel?()
        }
    }
}
