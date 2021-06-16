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

struct Event {
    var variants: Set<String>
    
    init() {
        self.variants = Set()
    }
    
    mutating func add(variant: String) {
        self.variants.insert(variant)
    }
    mutating func add(variants: String...) {
        for variant in variants {
            self.variants.insert(variant)
        }
    }
}

extension Event : ExpressibleByArrayLiteral {
    init(arrayLiteral elements: String...) {
        self.init()
        for element in elements {
            self.add(variant: element)
        }
    }
    
    typealias ArrayLiteralElement = String
}

/**
 Handles sending split commands based on state changes
 */
class CelesteSplitter {
    let scanner: CelesteScanner
    let server: LiveSplitServer
    var autoSplitterInfo: AutoSplitterInfo = AutoSplitterInfo()
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
    
    func reset() {
        server.reset()
        nextEventIndex = 0
    }
    
    func update() throws -> [Event] {
        guard let info = try scanner.getInfo() else {
            autoSplitterInfo = AutoSplitterInfo()
            return []
        }
        let events = getEvents(from: autoSplitterInfo, to: info)
        logStateChange(from: autoSplitterInfo, to: info)
        autoSplitterInfo = info
        
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

    func logStateChange(from old: AutoSplitterInfo, to new: AutoSplitterInfo) {
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
    
    func getEvents(from old: AutoSplitterInfo, to new: AutoSplitterInfo) -> [Event] {
        var events: [Event] = []
        
        // if we don't check `new.chapterComplete`, the summit credits trigger the autosplitter
        if new.chapterStarted && !old.chapterStarted && !new.chapterComplete {
            var event: Event = ["start chapter", "start chapter \(new.chapter)"]
            switch new.mode {
            case .Normal: event.add(variant: "start a-side \(new.chapter)")
            case .BSide: event.add(variant: "start b-side \(new.chapter)")
            case .CSide: event.add(variant: "start c-side \(new.chapter)")
            default: break
            }
            events.append(event)
        }
        if !new.chapterStarted && old.chapterStarted && !old.chapterComplete {
            var event: Event = ["leave chapter", "leave chapter \(old.chapter)"]
            switch new.mode {
            case .Normal: event.add(variant: "leave a-side \(old.chapter)")
            case .BSide: event.add(variant: "leave b-side \(old.chapter)")
            case .CSide: event.add(variant: "leave c-side \(old.chapter)")
            default: break
            }
            event.add(variants: "reset chapter", "reset chapter \(old.chapter)")
            switch new.mode {
            case .Normal: event.add(variant: "reset a-side \(old.chapter)")
            case .BSide: event.add(variant: "reset b-side \(old.chapter)")
            case .CSide: event.add(variant: "reset c-side \(old.chapter)")
            default: break
            }
            events.append(event)
        }
        if new.chapterComplete && !old.chapterComplete {
            var event: Event = ["complete chapter", "complete chapter \(old.chapter)"]
            switch new.mode {
            case .Normal: event.add(variant: "complete a-side \(old.chapter)")
            case .BSide: event.add(variant: "complete b-side \(old.chapter)")
            case .CSide: event.add(variant: "complete c-side \(old.chapter)")
            default: break
            }
            events.append(event)
        }
        
        if new.level != old.level && old.level != "" && new.level != "" {
            events.append(["\(old.level) > \(new.level)"])
        }
        if new.chapterCassette && !old.chapterCassette {
            events.append([
                "collect cassette",
                "collect chapter \(new.chapter) cassette",
                "collect \(new.fileCassettes) total cassettes",
                // compat:
                "cassette",
                "chapter \(new.chapter) cassette",
                "\(new.fileCassettes) total cassettes"
            ])
        }
        if new.chapterHeart && !old.chapterHeart {
            events.append([
                "collect heart",
                "collect chapter \(new.chapter) heart",
                "collect \(new.fileHearts) total hearts",
                // compat:
                "heart",
                "chapter \(new.chapter) heart",
                "\(new.fileHearts) total hearts"
            ])
        }
        if new.chapterStrawberries > old.chapterStrawberries {
            events.append([
                "collect strawberry",
                "collect \(new.chapterStrawberries) chapter strawberries",
                "collect \(new.fileStrawberries) file strawberries",
                // compat:
                "strawberry",
                "\(new.chapterStrawberries) chapter strawberries",
                "\(new.fileStrawberries) file strawberries"
            ])
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
        if jsonString.prefix(1) == "#" {
            return nil
        }
        guard let match = RouteEvent.pattern.firstMatch(in: jsonString, options: [], range: NSRange(jsonString.startIndex..<jsonString.endIndex, in: jsonString)) else {
            return nil
        }
        silent = match.range(at: 1).location != NSNotFound
        if let eventRange = Range(match.range(at: 2), in: jsonString) {
            event = String(jsonString[eventRange]).lowercased(with: nil)
        } else {
            return nil
        }
    }
    
    init(silent: Bool, event: String) {
        self.silent = silent
        self.event = event
    }

    func matches(event: Event) -> Bool {
        return event.variants.contains(self.event)
    }
    
    private static let pattern = try! NSRegularExpression(
        pattern: #"^(!)?\s*(.*?)\s*(##.*)?$"#
    )
}

extension RouteEvent : CustomStringConvertible {
    var description: String {
        (silent ? "!" : "") + event
    }
    
    
}
