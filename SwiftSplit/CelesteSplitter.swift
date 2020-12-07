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
/**
 Handles sending split commands based on state changes
 */
class CelesteSplitter {
    let scanner: CelesteScanner
    let server: LiveSplitServer
    var autoSplitterInfo: AutoSplitterInfo = AutoSplitterInfo()
    var routeConfig = RouteConfig(
        useFileTime: false,
        reset: "",
        route: []
    )
    
    init(pid: pid_t, server: LiveSplitServer) throws {
        self.scanner = try CelesteScanner(pid: pid)
        self.server = server
        self.server.pauseGameTime() // make sure gameTimeRunning is accurate
        try scanner.findHeader()
        if scanner.headerSignature == nil {
            throw SplitterError.noHeader
        }
    }
    
    private var gameTimeRunning = false
    private(set) var routeIndex = 0
    
    func reset() {
        server.reset()
        routeIndex = 0
    }
    
    func update() throws -> [String] {
        guard let info = try scanner.getInfo() else {
            autoSplitterInfo = AutoSplitterInfo()
            return []
        }
        let events = getEvents(from: autoSplitterInfo, to: info)
        autoSplitterInfo = info
        
        let time = routeConfig.useFileTime ? autoSplitterInfo.fileTime : autoSplitterInfo.chapterTime
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
    
    func getEvents(from old: AutoSplitterInfo, to new: AutoSplitterInfo) -> [String] {
        var events: [String] = []
        
        // if we don't check `new.chapterComplete`, the summit credits trigger the autosplitter
        if new.chapterStarted && !old.chapterStarted && !new.chapterComplete {
            events.append("start chapter \(new.chapter)")
            switch new.mode {
            case .Normal: events.append("start a-side \(new.chapter)")
            case .BSide: events.append("start b-side \(new.chapter)")
            case .CSide: events.append("start c-side \(new.chapter)")
            default: break
            }
        }
        if !new.chapterStarted && old.chapterStarted && !old.chapterComplete {
            events.append("reset chapter")
            events.append("reset chapter \(old.chapter)")
            switch new.mode {
            case .Normal: events.append("reset a-side \(old.chapter)")
            case .BSide: events.append("reset b-side \(old.chapter)")
            case .CSide: events.append("reset c-side \(old.chapter)")
            default: break
            }
        }
        if new.chapterComplete && !old.chapterComplete {
            events.append("complete chapter \(old.chapter)")
            switch new.mode {
            case .Normal: events.append("complete a-side \(old.chapter)")
            case .BSide: events.append("complete b-side \(old.chapter)")
            case .CSide: events.append("complete c-side \(old.chapter)")
            default: break
            }
        }
        
        if new.level != old.level && old.level != "" && new.level != "" {
            events.append("\(old.level) > \(new.level)")
        }
        if new.chapterCassette && !old.chapterCassette {
            events.append("cassette")
            events.append("chapter \(new.chapter) cassette")
            events.append("\(new.fileCassettes) total cassettes")
        }
        if new.chapterHeart && !old.chapterHeart {
            events.append("heart")
            events.append("chapter \(new.chapter) heart")
            events.append("\(new.fileHearts) total hearts")
        }
        if new.chapterStrawberries > old.chapterStrawberries {
            events.append("strawberry")
            events.append("\(new.chapterStrawberries) chapter strawberries")
            events.append("\(new.fileStrawberries) file strawberries")
        }
        return events
    }
    
    func processEvents(_ events: [String]) {
        for event in events {
            print("Event: `\(event)`")
            if event == routeConfig.reset {
                server.reset()
                routeIndex = 0
            } else if routeIndex < routeConfig.route.count {
                let nextEvent = routeConfig.route[routeIndex]
                if event == nextEvent || "!\(event)" == nextEvent {
                    if routeIndex == 0 {
                        server.reset()
                        server.start()
                        gameTimeRunning = true
                    } else if !nextEvent.starts(with: "!") {
                        server.split()
                    }
                    routeIndex += 1
                    if routeIndex == routeConfig.route.count {
                        routeIndex = 0
                    }
                }
            }
        }
    }
}

struct RouteConfig {
    let useFileTime: Bool
    let reset: String
    let route: [String]
}

extension RouteConfig {
    init?(json: [String: Any]) {
        guard let useFileTime = json["useFileTime"] as? Bool,
            let reset = json["reset"] as? String,
            let route = json["route"] as? [String]
            else {
                return nil
        }
        self.useFileTime = useFileTime
        self.reset = reset.components(separatedBy: " ##")[0]
        self.route = route.map { $0.components(separatedBy: " ##")[0] }
    }
    
    init() {
        self.init(useFileTime: false, reset: "", route: [])
    }
}
