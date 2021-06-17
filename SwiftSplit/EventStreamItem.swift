//
//  EventStreamItem.swift
//  SwiftSplit
//
//  Created by Pierce Corcoran on 6/16/21.
//  Copyright © 2021 Pierce Corcoran. All rights reserved.
//

import Cocoa

class EventStreamItem: NSCollectionViewItem {
    @IBOutlet weak var eventLabel: NSTextField!
    
    var event: String = "" {
        didSet {
            eventLabel.stringValue = event
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
}
