//
//  CelesteSplitter.swift
//  SwiftSplit
//
//  Created by Pierce Corcoran on 11/27/20.
//  Copyright © 2020 Pierce Corcoran. All rights reserved.
//

import Foundation

enum SplitterError: Error {
    case noHeader
}

enum VariantType: Equatable {
    case normal
    case legacy
}

struct EventVariant {
    var event: String
    var type: VariantType
    
    static func legacy(_ event: String) -> EventVariant {
        return EventVariant(event: event, type: .legacy)
    }
    
    static func normal(_ event: String) -> EventVariant {
        return EventVariant(event: event, type: .normal)
    }
}

struct Event {
    var variants: [EventVariant] = []
    
    init(_ variants: EventVariant...) {
        self.variants = variants
    }
    
    mutating func add(variant: EventVariant) {
        self.variants.append(variant)
    }
    mutating func add(variants: EventVariant...) {
        for variant in variants {
            self.variants.append(variant)
        }
    }
    
    mutating func add(_ event: String) {
        self.variants.append(.normal(event))
    }
}

/**
 Handles sending split commands based on state changes
 */
class CelesteSplitter {
    let scanner: CelesteScanner
    let server: LiveSplitServer
    var autoSplitterInfo: AutoSplitterInfo = AutoSplitterInfo()
    var extendedInfo: ExtendedAutoSplitterInfo? = nil
    var routeConfig = RouteConfig()
    
    init(pid: pid_t, server: LiveSplitServer) throws {
        self.scanner = try CelesteScanner(pid: pid)
        self.server = server
        self.server.pauseGameTime() // make sure gameTimeRunning is accurate
        try scanner.findHeader()
        if scanner.headerInfo == nil {
            throw SplitterError.noHeader
        }
    }
    
    private var time: Double = 0.0
    private var gameTimeRunning = false
    private(set) var nextEventIndex = 0
    private var feedIndex = 0
    
    func reset() {
        server.reset()
        nextEventIndex = 0
    }
    
    func update() throws -> [Event] {
        guard let info = try scanner.getInfo() else {
            autoSplitterInfo = AutoSplitterInfo()
            return []
        }
        let extended = try scanner.getExtendedInfo()
        
        var externalFeed: [String] = try readExternalFeed(from: extended)
        
        let events = getEvents(from: autoSplitterInfo, extended: extendedInfo, to: info, extended: extended, feed: externalFeed)
        logStateChange(from: autoSplitterInfo, extended: extendedInfo, to: info, extended: extendedInfo)
        autoSplitterInfo = info
        extendedInfo = extended
        
        if autoSplitterInfo.mode != .Menu { // save and quit resets the chapter timer to zero, but we don't want to reset it for QTM strats
            time = routeConfig.useFileTime ? autoSplitterInfo.fileTime : autoSplitterInfo.chapterTime
        }
        server.setGameTime(seconds: time)
        processEvents(events)
        
        // when using the chapter time, `timerActive` will be true before the chapter time starts ticking.
        // This is because the *file* timer is active even before the *chapter* timer is active
        let timerActive = autoSplitterInfo.timerActive && time != 0
        if timerActive != gameTimeRunning {
            server.setGameTime(running: timerActive)
            gameTimeRunning = timerActive
        }
        return events
    }
    
    var lastStateTime = DispatchTime.now()
    
    func logStateChange(from old: AutoSplitterInfo, extended oldExtended: ExtendedAutoSplitterInfo?, to new: AutoSplitterInfo, extended newExtended: ExtendedAutoSplitterInfo?) {
        let comparisons = [
            (name: "chapter", old: "\(old.chapter)", new: "\(new.chapter)"),
            (name: "mode", old: "\(old.mode)", new: "\(new.mode)"),
            (name: "level", old: "\(old.level)", new: "\(new.level)"),
            (name: "timerActive", old: "\(old.timerActive)", new: "\(new.timerActive)"),
            (name: "chapterStarted", old: "\(old.chapterStarted)", new: "\(new.chapterStarted)"),
            (name: "chapterComplete", old: "\(old.chapterComplete)", new: "\(new.chapterComplete)"),
            // (name: "chapterTime", old: "\(old.chapterTime)", new: "\(new.chapterTime)"),
            (name: "chapterStrawberries", old: "\(old.chapterStrawberries)", new: "\(new.chapterStrawberries)"),
            (name: "chapterCassette", old: "\(old.chapterCassette)", new: "\(new.chapterCassette)"),
            (name: "chapterHeart", old: "\(old.chapterHeart)", new: "\(new.chapterHeart)"),
            // (name: "fileTime", old: "\(old.fileTime)", new: "\(new.fileTime)"),
            (name: "fileStrawberries", old: "\(old.fileStrawberries)", new: "\(new.fileStrawberries)"),
            (name: "fileCassettes", old: "\(old.fileCassettes)", new: "\(new.fileCassettes)"),
            (name: "fileHearts", old: "\(old.fileHearts)", new: "\(new.fileHearts)"),
            
            (name: "chapterDeaths", old: "\(oldExtended?.chapterDeaths ?? -1)", new: "\(newExtended?.chapterDeaths ?? -1)"),
            (name: "levelDeaths", old: "\(oldExtended?.levelDeaths ?? -1)", new: "\(newExtended?.levelDeaths ?? -1)"),
            (name: "areaName", old: "\(oldExtended?.areaName ?? "<none>")", new: "\(newExtended?.areaName ?? "<none>")"),
            (name: "areaSID", old: "\(oldExtended?.areaSID ?? "<none>")", new: "\(newExtended?.areaSID ?? "<none>")"),
            (name: "levelSet", old: "\(oldExtended?.levelSet ?? "<none>")", new: "\(newExtended?.levelSet ?? "<none>")"),
        ]
        let changes = comparisons.filter { $0.old != $0.new }
        
        if !changes.isEmpty {
            let currentTime = DispatchTime.now()
            let delta = Double(currentTime.uptimeNanoseconds - lastStateTime.uptimeNanoseconds) / 1_000_000_000
            print(
                "[real delta: \(delta), chapter: \(new.chapterTime), file: \(new.fileTime)] " + changes.map { "\($0.name): \($0.old) -> \($0.new)" }.joined(separator: ", ")
            )
            lastStateTime = currentTime
        }
    }
    
    func readExternalFeed(from extended: ExtendedAutoSplitterInfo?) throws -> [String] {
        guard let info = extended else { return [] }
        
        let remoteIndex = Int(info.feedIndex)
        if self.extendedInfo == nil {
            self.feedIndex = remoteIndex
        }
        let remoteFeed = info.feed
        
        var items: [String] = []
        
        self.feedIndex = max(remoteIndex - remoteFeed.count, self.feedIndex)
        while self.feedIndex < remoteIndex {
            if let feedItem = try Mono.readString(at: remoteFeed[self.feedIndex % remoteFeed.count]) {
                items.append(feedItem)
            }
            self.feedIndex += 1
        }
        
        return items
    }
    
    func getEvents(from old: AutoSplitterInfo, extended oldExtended: ExtendedAutoSplitterInfo?, to new: AutoSplitterInfo, extended newExtended: ExtendedAutoSplitterInfo?, feed externalFeed: [String]) -> [Event] {
        var events: [Event] = []
        
        // if we don't check `new.chapterComplete`, the summit credits trigger the autosplitter
        if new.chapterStarted && !old.chapterStarted && !new.chapterComplete {
            var event = Event()
            
            do { // no chapter
                event.add("enter chapter")
                switch new.mode {
                case .Normal: event.add("enter a-side")
                case .BSide: event.add("enter b-side")
                case .CSide: event.add("enter c-side")
                default: break
                }
            }
            
            do { // chapter index
                event.add("enter chapter \(new.chapter)")
                switch new.mode {
                case .Normal: event.add("enter a-side \(new.chapter)")
                case .BSide: event.add("enter b-side \(new.chapter)")
                case .CSide: event.add("enter c-side \(new.chapter)")
                default: break
                }
            }
            
            do { // area SID
                if let newSID = newExtended?.areaSID {
                    event.add("enter chapter '\(newSID)'")
                    switch new.mode {
                    case .Normal: event.add("enter a-side '\(newSID)'")
                    case .BSide: event.add("enter b-side '\(newSID)'")
                    case .CSide: event.add("enter c-side '\(newSID)'")
                    default: break
                    }
                }
            }
            
            do { // legacy
                event.add(variants: .legacy("start chapter"), .legacy("start chapter \(new.chapter)"))
                switch new.mode {
                case .Normal: event.add(variant: .legacy("start a-side \(new.chapter)"))
                case .BSide: event.add(variant: .legacy("start b-side \(new.chapter)"))
                case .CSide: event.add(variant: .legacy("start c-side \(new.chapter)"))
                default: break
                }
            }
            events.append(event)
        }
        
        if !new.chapterStarted && old.chapterStarted && !old.chapterComplete {
            var event: Event = Event()
            
            do { // no chapter
                event.add("leave chapter")
                switch old.mode {
                case .Normal: event.add("leave a-side")
                case .BSide: event.add("leave b-side")
                case .CSide: event.add("leave c-side")
                default: break
                }
            }
            
            do { // chapter index
                event.add("leave chapter \(old.chapter)")
                switch old.mode {
                case .Normal: event.add("leave a-side \(old.chapter)")
                case .BSide: event.add("leave b-side \(old.chapter)")
                case .CSide: event.add("leave c-side \(old.chapter)")
                default: break
                }
            }
            
            do { // area SID
                if let oldSID = oldExtended?.areaSID {
                    event.add("leave chapter '\(oldSID)'")
                    switch old.mode {
                    case .Normal: event.add("leave a-side '\(oldSID)'")
                    case .BSide: event.add("leave b-side '\(oldSID)'")
                    case .CSide: event.add("leave c-side '\(oldSID)'")
                    default: break
                    }
                }
            }
            
            do { // legacy
                event.add(variants: .legacy("reset chapter"), .legacy("reset chapter \(old.chapter)"))
                switch old.mode {
                case .Normal: event.add(variant: .legacy("reset a-side \(old.chapter)"))
                case .BSide: event.add(variant: .legacy("reset b-side \(old.chapter)"))
                case .CSide: event.add(variant: .legacy("reset c-side \(old.chapter)"))
                default: break
                }
            }
            events.append(event)
        }
        
        if new.chapterComplete && !old.chapterComplete {
            var event: Event = Event()
            
            do { // no chapter
                event.add("complete chapter")
                switch new.mode {
                case .Normal: event.add("complete a-side")
                case .BSide: event.add("complete b-side")
                case .CSide: event.add("complete c-side")
                default: break
                }
            }
            
            do { // chapter index
                event.add("complete chapter \(old.chapter)")
                switch new.mode {
                case .Normal: event.add("complete a-side \(old.chapter)")
                case .BSide: event.add("complete b-side \(old.chapter)")
                case .CSide: event.add("complete c-side \(old.chapter)")
                default: break
                }
            }
            
            do { // area SID
                if let oldSID = oldExtended?.areaSID {
                    event.add("complete chapter '\(oldSID)'")
                    switch new.mode {
                    case .Normal: event.add("complete a-side '\(oldSID)'")
                    case .BSide: event.add("complete b-side '\(oldSID)'")
                    case .CSide: event.add("complete c-side '\(oldSID)'")
                    default: break
                    }
                }
            }
            
            events.append(event)
        }
        
        if new.level != old.level && old.level != "" && new.level != "" {
            events.append(Event(.normal("\(old.level) > \(new.level)")))
        }
        
        if new.chapterCassette && !old.chapterCassette {
            var event = Event()
            
            event.add("collect cassette") // no chapter
            event.add("collect chapter \(new.chapter) cassette") // chapter index
            if let newSID = newExtended?.areaSID { // area SID
                event.add("collect chapter '\(newSID)' cassette")
            }
            event.add("\(new.fileCassettes) total cassettes")
            // legacy
            event.add(variants: .legacy("cassette"), .legacy("chapter \(new.chapter) cassette"))
            
            events.append(event)
        }
        
        if new.chapterHeart && !old.chapterHeart {
            var event = Event()
            
            event.add("collect heart") // no chapter
            event.add("collect chapter \(new.chapter) heart") // chapter index
            if let newSID = newExtended?.areaSID { // area SID
                event.add("collect chapter '\(newSID)' heart")
            }
            event.add("\(new.fileHearts) total hearts")
            // legacy
            event.add(variants: .legacy("heart"), .legacy("chapter \(new.chapter) heart"))
            
            events.append(event)
        }
        
        if new.chapterStrawberries > old.chapterStrawberries {
            var event = Event()
            
            event.add("collect strawberry")
            event.add("\(new.chapterStrawberries) chapter strawberries")
            event.add("\(new.fileStrawberries) file strawberries")
            event.add(variant: .legacy("strawberry"))

            events.append(event)
        }
        
        if !externalFeed.isEmpty {
            var event = Event()
            for item in externalFeed {
                event.add(item)
            }
            events.append(event)
        }
        return events
    }
    
    func processEvents(_ events: [Event]) {
        if events.count == 0 {
            return
        }
        var events = events
        // go through the route, gobbling up events as they match
        route: for routeEvent in routeConfig.route[nextEventIndex...] {
            for i in events.indices {
                if routeEvent.matches(event: events[i]) {
                    print("Matched against: `\(routeEvent.event)`")
                    events.remove(at: i)
                    
                    if nextEventIndex == 0 {
                        server.reset()
                        server.start()
                        gameTimeRunning = true
                    } else if !routeEvent.silent {
                        server.split()
                    }
                    
                    nextEventIndex += 1
                    continue route
                }
            }
            break
        }
        
        if events.contains(where: { routeConfig.reset.matches(event: $0) }) {
            server.reset()
            nextEventIndex = 0
        }
    }
}

struct RouteConfig {
    let useFileTime: Bool
    let reset: RouteEvent
    let route: [RouteEvent]
}

extension RouteConfig {
    init?(json: [String: Any]) {
        guard let useFileTime = json["useFileTime"] as? Bool,
            let reset = json["reset"] as? String,
            let resetEvent = RouteEvent(from: reset),
            let route = json["route"] as? [String]
            else {
                return nil
        }
        let routeEvents = route.compactMap({ RouteEvent(from: $0) })
        if(routeEvents.count != route.count) {
            return nil
        }
        self.useFileTime = useFileTime
        self.reset = resetEvent
        self.route = routeEvents
    }
    
    init() {
        self.init(useFileTime: false, reset: RouteEvent(silent: false, event: ""), route: [])
    }
}

class RouteEvent {
    var silent: Bool
    var event: String
    
    init?(from jsonString: String) {
        guard let match = RouteEvent.pattern.firstMatch(in: jsonString, options: [], range: NSRange(jsonString.startIndex..<jsonString.endIndex, in: jsonString)) else {
            return nil
        }
        silent = match.range(at: 1).location != NSNotFound
        guard let eventRange = Range(match.range(at: 2), in: jsonString) else {
            return nil
        }
        let event = String(jsonString[eventRange])
        if event.isEmpty {
            return nil
        }
        self.event = event
    }
    
    init(silent: Bool, event: String) {
        self.silent = silent
        self.event = event
    }
    
    func matches(event: Event) -> Bool {
        return event.variants.contains(where: { self.matches(variant: $0) })
    }
    
    func matches(variant: EventVariant) -> Bool {
        return self.event == variant.event
    }
    
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(!)?\s*(.*?)\s*(#.*)?$"#
    )
}

extension RouteEvent : CustomStringConvertible {
    var description: String {
        (silent ? "!" : "") + event
    }
}
