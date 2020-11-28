//
//  ViewController.swift
//  MacSplit
//
//  Created by Pierce Corcoran on 11/3/20.
//  Copyright © 2020 Pierce Corcoran. All rights reserved.
//

import Cocoa
import Carbon

class ViewController: NSViewController {
    var splitter: CelesteSplitter? = nil

    @IBOutlet weak var gameTimeLabel: NSTextField!
    @IBOutlet weak var nextEventLabel: NSTextField!
    @IBOutlet weak var livesplitClientsLabel: NSTextField!
    @IBOutlet weak var eventStreamLabel: NSTextField!
    
    @IBOutlet weak var loadedRouteLabel: NSTextField!
    @IBOutlet weak var routeDataLabel: NSTextField!
    
    @IBOutlet weak var connectionStatusLabel: NSTextField!
    @IBOutlet weak var celesteDataLabel: NSTextField!
    
    var showRouteData = false
    var showCelesteData = false
    let eventStreamLength = 6
    var eventStream: [String] = []

    // we will ignore the celeste instance that was open when we first launched (if any). We don't know if they're in a clean state.
    // we also ignore the pid once it has been connected to. this prevents attempting to reconnect immediately after the game closes and we disconnect
    var ignorePid: pid_t?
    
    var hasRouteConfig = false
    var routeConfig = RouteConfig() {
        didSet {
            splitter?.routeConfig = routeConfig
        }
    }

    var timer: Timer? = nil
    var connectTimer: Timer? = nil
    var server: LiveSplitServer? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        self.eventStream = Array(repeating: "", count: eventStreamLength)
        self.ignorePid = findCelestePid()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.update()
            self.updateInfoViews()
        }

        eventStreamLabel.stringValue = eventStream.joined(separator: "\n")
        server = try? LiveSplitServer(host: "localhost", port: 8777)
    }

    func update() {
        livesplitClientsLabel.stringValue = "\(server?.connectedClients ?? 0)"
        if self.splitter == nil {
            tryConnecting()
        }
        guard let splitter = self.splitter else {
            return
        }
        
        do {
            let events = try splitter.update()
            eventStream = (eventStream + events.map { "\"\($0)\"" }).suffix(eventStreamLength)
        } catch {
            self.splitter = nil
            eventStream = Array(repeating: "", count: eventStreamLength)
            connectionStatusLabel.stringValue = "Disconnected"
            print("Error getting info: \(error)")
        }
        eventStreamLabel.stringValue = eventStream.joined(separator: "\n")
    }
    
    func tryConnecting() {
        if self.connectTimer != nil {
            return
        }
        guard let pid = findCelestePid() else {
            return
        }

        var connectionAttempts = 0
        self.connectionStatusLabel.stringValue = "Connecting…"
        connectTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            if NSRunningApplication(processIdentifier: pid) == nil {
                self.connectTimer?.invalidate()
                self.connectTimer = nil
                self.connectionStatusLabel.stringValue = "Not connected"
            }
            
            self.connect(pid: pid)
            
            connectionAttempts += 1
            if self.splitter != nil {
                self.connectTimer?.invalidate()
                self.connectTimer = nil
            } else if connectionAttempts > 5 {
                self.connectTimer?.invalidate()
                self.connectTimer = nil
                self.connectionStatusLabel.stringValue = "Connection failed"
            }
        }
    }
    
    func findCelestePid() -> pid_t? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.celeste")
        
        if apps.isEmpty {
            return nil
        }
        let pid = apps[0].processIdentifier
        
        if pid == ignorePid {
            return nil // this celeste process was open when we launched, so we don't know that it's in a clean state.
        }
        
        return pid
    }
    
    func connect(pid: pid_t) {
        guard let server = self.server else {
            return
        }
        
        do {
            self.ignorePid = pid
            self.splitter = try CelesteSplitter(pid: pid, server: server)
            self.splitter?.routeConfig = routeConfig
            connectionStatusLabel.stringValue = "Connected"
        } catch {
            print("Error creating splitter: \(error)")
        }
    }

    func updateInfoViews() {
        if !hasRouteConfig {
            routeDataLabel.stringValue = "<none>"
        } else if showRouteData {
            routeDataLabel.stringValue = """
            Use file time: \(routeConfig.useFileTime)
            Reset event: '\(routeConfig.reset)'
            Route:
            \(routeConfig.route.map { "    '\($0)'" }.joined(separator: "\n"))
            """
        } else {
            routeDataLabel.stringValue = "…"
        }
        
        guard let splitter = splitter else {
            gameTimeLabel.stringValue = "<none>"
            nextEventLabel.stringValue = routeConfig.route.isEmpty ? "<none>" : "\"\(routeConfig.route[0])\""
            celesteDataLabel.stringValue = "<none>"
            return
        }
        
        let info = splitter.autoSplitterInfo
        if showCelesteData {
            celesteDataLabel.stringValue = """
            Object Header: \(String(format: "%08llx", info.data.header))
            Object Location: \(String(format: "%08llx", info.data.location))
            
            Chapter: \(info.chapter)
            Mode: \(info.mode)
            Level:
                Name Pointer: \(String(format: "%llx", info.data.levelPointer))
                Name: \(info.level)
                Timer Active: \(info.timerActive)
            Chapter:
                Started: \(info.chapterStarted)
                Complete: \(info.chapterComplete)
                Time: \(info.chapterTime)
                Strawberries: \(info.chapterStrawberries)
                Cassette: \(info.chapterCassette)
                Heart: \(info.chapterHeart)
            File:
                Time: \(info.fileTime)
                Strawberries: \(info.fileStrawberries)
                Cassettes: \(info.fileCassettes)
                Hearts: \(info.fileHearts)
            """
        } else {
            celesteDataLabel.stringValue = "…"
        }
        
        let time = routeConfig.useFileTime ? info.fileTime : info.chapterTime
        let seconds = time.truncatingRemainder(dividingBy: 60)
        let minutes = Int(time / 60) % 60
        let hours = Int(time / 3600) % 60
        
        var timeString = ""
        if hours > 0 { timeString +=  "\(hours):" }
        if minutes > 0 {
            if timeString != "" {
                timeString +=  String(format: "%02d:", minutes)
            } else {
                timeString +=  String(format: "%d:", minutes)
            }
        }
        if timeString != "" {
            timeString += String(format: "%02.3f", seconds)
        } else {
            timeString += String(format: "%.3f", seconds)
        }
            
        gameTimeLabel.stringValue = timeString
        
        nextEventLabel.stringValue = splitter.routeIndex < routeConfig.route.count ? "\"\(routeConfig.route[splitter.routeIndex])\"" : "<none>"
    }

    @IBAction func loadRoute(_ sender: Any) {
        let dialog = NSOpenPanel();
        
        dialog.title = "Choose a route .json file";
        dialog.allowedFileTypes = ["json"];
        
        if (dialog.runModal() == .OK) {
            guard let fileUrl = dialog.url,
                let data = try? Data(contentsOf: fileUrl),
                let dataValues = try? JSONSerialization.jsonObject(with: data, options: .init()) as? [String: Any],
                let config = RouteConfig(json: dataValues)
            else {
                return
            }
            hasRouteConfig = true
            routeConfig = config

            loadedRouteLabel.stringValue = "\(fileUrl.lastPathComponent)"
            
            updateInfoViews()
            
        } else {
            // User clicked on "Cancel"
            return
        }
    }
    
    @IBAction func discloseRouteData(_ sender: Any) {
        showRouteData = !showRouteData
        updateInfoViews()
    }
    
    @IBAction func discloseCelesteData(_ sender: Any) {
        showCelesteData = !showCelesteData
        updateInfoViews()
    }
}

