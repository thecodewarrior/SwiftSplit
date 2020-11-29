//
//  RouteBox.swift
//  SwiftSplit
//
//  Created by Pierce Corcoran on 11/28/20.
//  Copyright © 2020 Pierce Corcoran. All rights reserved.
//

import Foundation
import Cocoa

protocol RouteBoxDelegate: class {
    func openRouteFile(url: URL)
}

class RouteBox: NSBox {
    weak var delegate: RouteBoxDelegate?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.registerMyTypes()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.registerMyTypes()
    }
    
    final private func registerMyTypes() {
        registerForDraggedTypes(
            [NSPasteboard.PasteboardType.URL,
             NSPasteboard.PasteboardType.fileURL,
             NSPasteboard.PasteboardType.fileNameType(forPathExtension: "json")
        ])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return NSDragOperation.copy
    }
    
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        print("performDragOperation")
        
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            if !urls.isEmpty {
                delegate?.openRouteFile(url: urls[0])
            }
            return true
        }
        return false
    }
}
