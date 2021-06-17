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
    case normal(specificity: Int)
    case legacy
}

extension VariantType {
    var sortOrder: Int {
        get {
            switch self {
            case .normal(specificity: let spec):
                return spec
            case .legacy:
                return Int.max
            }
        }
    }
}

struct EventVariant {
    var event: String
    var type: VariantType
    
    static func legacy(_ event: String) -> EventVariant {
        return EventVariant(event: event, type: .legacy)
    }
    
    static func normal(_ event: String, specificity: Int) -> EventVariant {
        return EventVariant(event: event, type: .normal(specificity: specificity))
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
            var event = Event(
                .normal("enter chapter", specificity: 0),
                .normal("enter chapter \(new.chapter)", specificity: 0)
            )
            switch new.mode {
            case .Normal: event.add(variant: .normal("enter a-side \(new.chapter)", specificity: 0))
            case .BSide: event.add(variant: .normal("enter b-side \(new.chapter)", specificity: 0))
            case .CSide: event.add(variant: .normal("enter c-side \(new.chapter)", specificity: 0))
            default: break
            }
            
            event.add(variants:
                .legacy("start chapter"),
                      .legacy("start chapter \(new.chapter)")
            )
            switch new.mode {
            case .Normal: event.add(variant: .legacy("start a-side \(new.chapter)"))
            case .BSide: event.add(variant: .legacy("start b-side \(new.chapter)"))
            case .CSide: event.add(variant: .legacy("start c-side \(new.chapter)"))
            default: break
            }
            events.append(event)
        }
        if !new.chapterStarted && old.chapterStarted && !old.chapterComplete {
            var event: Event = Event(
                .normal("leave chapter", specificity: 0),
                .normal("leave chapter \(old.chapter)", specificity: 0)
            )
            switch new.mode {
            case .Normal: event.add(variant: .normal("leave a-side \(old.chapter)", specificity: 0))
            case .BSide: event.add(variant: .normal("leave b-side \(old.chapter)", specificity: 0))
            case .CSide: event.add(variant: .normal("leave c-side \(old.chapter)", specificity: 0))
            default: break
            }
            
            event.add(variants: .legacy("reset chapter"), .legacy("reset chapter \(old.chapter)"))
            switch new.mode {
            case .Normal: event.add(variant: .legacy("reset a-side \(old.chapter)"))
            case .BSide: event.add(variant: .legacy("reset b-side \(old.chapter)"))
            case .CSide: event.add(variant: .legacy("reset c-side \(old.chapter)"))
            default: break
            }
            events.append(event)
        }
        if new.chapterComplete && !old.chapterComplete {
            var event: Event = Event(
                .normal("complete chapter", specificity: 0),
                .normal("complete chapter \(old.chapter)", specificity: 0)
            )
            switch new.mode {
            case .Normal: event.add(variant: .normal("complete a-side \(old.chapter)", specificity: 0))
            case .BSide: event.add(variant: .normal("complete b-side \(old.chapter)", specificity: 0))
            case .CSide: event.add(variant: .normal("complete c-side \(old.chapter)", specificity: 0))
            default: break
            }
            events.append(event)
        }
        
        if new.level != old.level && old.level != "" && new.level != "" {
            events.append(Event(.normal("\(old.level) > \(new.level)", specificity: 0)))
        }
        if new.chapterCassette && !old.chapterCassette {
            events.append(Event(
                .normal("collect cassette", specificity: 0),
                .normal("collect chapter \(new.chapter) cassette", specificity: 0),
                .normal("collect \(new.fileCassettes) total cassettes", specificity: 0),
                // compat:
                .legacy("cassette"),
                .legacy("chapter \(new.chapter) cassette"),
                .legacy("\(new.fileCassettes) total cassettes")
            ))
        }
        if new.chapterHeart && !old.chapterHeart {
            events.append(Event(
                .normal("collect heart", specificity: 0),
                .normal("collect chapter \(new.chapter) heart", specificity: 0),
                .normal("collect \(new.fileHearts) total hearts", specificity: 0),
                // compat:
                .legacy("heart"),
                .legacy("chapter \(new.chapter) heart"),
                .legacy("\(new.fileHearts) total hearts")
            ))
        }
        if new.chapterStrawberries > old.chapterStrawberries {
            events.append(Event(
                .normal("collect strawberry", specificity: 0),
                .normal("collect \(new.chapterStrawberries) chapter strawberries", specificity: 0),
                .normal("collect \(new.fileStrawberries) file strawberries", specificity: 0),
                // compat:
                .legacy("strawberry"),
                .legacy("\(new.chapterStrawberries) chapter strawberries"),
                .legacy("\(new.fileStrawberries) file strawberries")
            ))
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
        return event.variants.contains(where: { self.matches(variant: $0) })
    }
    
    func matches(variant: EventVariant) -> Bool {
        return self.event == variant.event
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
