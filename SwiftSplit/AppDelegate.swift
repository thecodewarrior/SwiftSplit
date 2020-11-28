//
//  AppDelegate.swift
//  SwiftSplit
//
//  Created by Pierce Corcoran on 11/25/20.
//  Copyright © 2020 Pierce Corcoran. All rights reserved.
//

import Cocoa

//@NSApplicationMain // we use a custom main, so we don't want an implicit one generated for us
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

}

