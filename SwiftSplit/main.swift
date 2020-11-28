//
//  main.swift
//  SwiftSplit
//
//  Created by Pierce Corcoran on 11/28/20.
//  Copyright © 2020 Pierce Corcoran. All rights reserved.
//

import Foundation
import Cocoa

if(getuid() != 0) {
    print("Current user id is \(getuid()), which isn't root. Relaunching as root.")
    
    let swiftsplitExecutable = CommandLine.arguments[0]
    let logFile = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Logs/SwiftSplit.log"
    let bootstrapScript = "do shell script \"'\(swiftsplitExecutable)' &> '\(logFile)' &\" with prompt \"SwiftSplit wants to read process memory.\" with administrator privileges"
    print("Bootstrap script: `\(bootstrapScript)`")

    var error: NSDictionary?
    if let scriptObject = NSAppleScript(source: bootstrapScript) {
        scriptObject.executeAndReturnError(&error)
        if let error = error {
            print("Error bootstrapping to root: ", error)
        }
    }
    
    exit(0)
} else {
    print("Current user id is \(getuid()), which is root. Launching application.")
}

exit(NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv))
