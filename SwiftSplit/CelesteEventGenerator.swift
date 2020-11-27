//
//  CelesteEventGenerator.swift
//  MacSplit
//
//  Created by Pierce Corcoran on 11/19/20.
//  Copyright © 2020 Pierce Corcoran. All rights reserved.
//

import Foundation

class CelesteEventGenerator {
    var scanner: CelesteScanner
    var autoSplitterInfo: AutoSplitterInfo = AutoSplitterInfo()
    
    init(pid: pid_t) throws {
        scanner = try CelesteScanner(pid: pid)
        try scanner.findHeader()
    }
    
    func updateInfo() throws -> [String] {
        if let info = try scanner.getInfo() {
            let events = getEvents(from: autoSplitterInfo, to: info)
            autoSplitterInfo = info
            return events
        } else {
            autoSplitterInfo = AutoSplitterInfo()
            return []
        }
    }
    
    func getEvents(from old: AutoSplitterInfo, to new: AutoSplitterInfo) -> [String] {
        var events: [String] = []
        if new.level != old.level {
            events.append("\(old.level) > \(new.level)")
        }
        if new.chapterStarted && !old.chapterStarted {
            events.append("start chapter \(new.chapter)")
        }
        if !new.chapterStarted && old.chapterStarted && !old.chapterComplete {
            events.append("reset chapter")
        }
        if new.chapterComplete && !old.chapterComplete {
            events.append("complete chapter \(old.chapter)")
        }
        return events
    }
}
