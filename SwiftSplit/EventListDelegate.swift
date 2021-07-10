//
//  EventListDelegate.swift
//  SwiftSplit
//
//  Created by Pierce Corcoran on 6/16/21.
//  Copyright © 2021 Pierce Corcoran. All rights reserved.
//

import Foundation
import Cocoa

class EventListDelegate: NSObject, NSCollectionViewDelegate, NSCollectionViewDataSource {
    static let itemIdentifier = NSUserInterfaceItemIdentifier(rawValue: "eventStreamItem")
    
    let maxEntries = 100
    var eventEntries: [String] = []
    weak var collectionView: NSCollectionView!
    var scrollView: NSScrollView {
        get {
            return self.collectionView.enclosingScrollView!
        }
    }
    
    func add(events: [Event]) {
        if events.isEmpty {
            return
        }
        
        let variants = events.flatMap { $0.variants }.filter { $0.type != VariantType.legacy }
        let entries = variants.map { $0.event }
        
        let removeCount = eventEntries.count + entries.count - maxEntries
        
        if removeCount > 0 {
            eventEntries.removeFirst(removeCount)
            let range = (0 ..< removeCount).map { IndexPath(item: $0, section: 0) }
            self.collectionView.deleteItems(at: Set(range))
        }
        
        let rangeStart = self.eventEntries.count
        self.eventEntries.append(contentsOf: entries)
        let rangeEnd = self.eventEntries.count
        
        let items = (rangeStart ..< rangeEnd).map { IndexPath(item: $0, section: 0) }
        let wasAtBottom = isAtBottom()
        self.collectionView.insertItems(at: Set(items))
        if wasAtBottom && !isAtBottom() {
            scrollToBottom()
        }
    }
    
    private func scrollToBottom() {
        guard let documentView = scrollView.documentView else {
            return
        }
        collectionView.scroll(NSPoint(x: 0, y: documentView.bounds.height))
    }
    
    private func isAtBottom() -> Bool {
        guard let documentView = scrollView.documentView else {
            return false
        }
        return scrollView.contentView.bounds.maxY >= documentView.bounds.height
    }
    
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return eventEntries.count
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        guard let item = collectionView.makeItem(withIdentifier: EventListDelegate.itemIdentifier, for: indexPath) as? EventStreamItem else {
            return NSCollectionViewItem()
        }
        item.event = eventEntries[indexPath.item]
        return item
    }
}
