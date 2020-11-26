//
//  CelesteSplitter.swift
//  MacSplit
//
//  Created by Pierce Corcoran on 11/19/20.
//  Copyright © 2020 Pierce Corcoran. All rights reserved.
//

import Foundation

enum CelesteEvent {
    case levelSwitch(old: String, new: String)
    case startChapter(chapter: Int)
    case resetChapter(chapter: Int)
    case completeChapter(chapter: Int)
}

class CelesteEventGenerator {
    var scanner: CelesteScanner
    var autoSplitterInfo: AutoSplitterInfo = AutoSplitterInfo()
    
    init(pid: pid_t) throws {
        scanner = try CelesteScanner(pid: pid)
        try scanner.findHeader()
    }
    
    func updateInfo() throws -> [CelesteEvent] {
        if let info = try scanner.getInfo() {
            let events = getEvents(from: autoSplitterInfo, to: info)
            autoSplitterInfo = info
            return events
        } else {
            autoSplitterInfo = AutoSplitterInfo()
            return []
        }
    }
    
    func getEvents(from old: AutoSplitterInfo, to new: AutoSplitterInfo) -> [CelesteEvent] {
        var events: [CelesteEvent] = []
        if new.level != old.level {
            events.append(.levelSwitch(old: old.level, new: new.level))
        }
        if new.chapterStarted && !old.chapterStarted {
            events.append(.startChapter(chapter: new.chapter))
        }
        if !new.chapterStarted && old.chapterStarted && !old.chapterComplete {
            events.append(.resetChapter(chapter: old.chapter))
        }
        if new.chapterComplete && !old.chapterComplete {
            events.append(.completeChapter(chapter: new.chapter))
        }
        return events
    }
}
