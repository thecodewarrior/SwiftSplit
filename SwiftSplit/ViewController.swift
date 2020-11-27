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
    var eventGenerator: CelesteEventGenerator? = nil
    @IBOutlet weak var signatureLabel: NSTextField!
    @IBOutlet weak var infoLabel: NSTextField!
    @IBOutlet weak var routeLabel: NSTextField!
    
    var timer: Timer? = nil
    var runTimer: Bool = false
    var server: LiveSplitServer? = nil

    override func viewDidLoad() {
        super.viewDidLoad()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if self.runTimer {
                self.updateInfo()
            }
        }

        updateInfoView(with: AutoSplitterInfo())
        server = try? LiveSplitServer(host: "localhost", port: 8777)
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    var gameTimeRunning = false
    func updateInfo() {
        guard let eventGenerator = self.eventGenerator else {
            print("Memory is nil")
            return
        }
        do {
            let events = try eventGenerator.updateInfo()
            updateInfoView(with: eventGenerator.autoSplitterInfo)
            if routeConfig.useFileTime {
                server?.setGameTime(seconds: eventGenerator.autoSplitterInfo.fileTime)
            } else {
                server?.setGameTime(seconds: eventGenerator.autoSplitterInfo.chapterTime)
            }
            if eventGenerator.autoSplitterInfo.timerActive {
                if !gameTimeRunning {
                    server?.resumeGameTime()
                    gameTimeRunning = true
                }
            } else if gameTimeRunning {
                server?.pauseGameTime()
                gameTimeRunning = false
            }
            processEvents(events)
        } catch {
            self.eventGenerator = nil
            updateInfoView(with: AutoSplitterInfo())
            runTimer = false
            signatureLabel.stringValue = "Disconnected"
            print("Error getting info: \(error)")
        }
    }

    var routeConfig = RouteConfig(
        useFileTime: false,
        reset: "",
        route: []
    )
    var routeIndex = 0
    
    func processEvents(_ events: [String]) {
        for event in events {
            print("Event: `\(event)`")
            if event == routeConfig.reset {
                server?.reset()
                routeIndex = 0
            } else if routeIndex < routeConfig.route.count {
                let nextEvent = routeConfig.route[routeIndex]
                if event == nextEvent || "!\(event)" == nextEvent {
                    if routeIndex == 0 {
                        server?.reset()
                        server?.start()
                    } else if !nextEvent.starts(with: "!") {
                        server?.split()
                    }
                    routeIndex += 1
                    if routeIndex == routeConfig.route.count {
                        routeIndex = 0
                    }
                }
            }
        }
    }
    
    func updateInfoView(with info: AutoSplitterInfo) {
        infoLabel.stringValue = """
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
    }

    @IBAction func loadSplits(_ sender: Any) {
        let dialog = NSOpenPanel();
        
        dialog.title                   = "Choose a route .json file";
        dialog.showsResizeIndicator    = true;
        dialog.showsHiddenFiles        = false;
        dialog.canChooseDirectories    = false;
        dialog.canCreateDirectories    = false;
        dialog.allowsMultipleSelection = false;
        dialog.allowedFileTypes        = ["json"];
        
        if (dialog.runModal() == .OK) {
            guard let fileUrl = dialog.url,
                let data = try? Data(contentsOf: fileUrl),
                let dataValues = try? JSONSerialization.jsonObject(with: data, options: .init()) as? [String: Any],
                let config = RouteConfig(json: dataValues)
            else {
                return
            }
            routeConfig = config
            routeLabel.stringValue = """
            Route config: \(fileUrl.lastPathComponent)
            Use file time: \(routeConfig.useFileTime)
            Reset event: '\(routeConfig.reset)'
            Route:
            \(routeConfig.route.map { "    '\($0)'" }.joined(separator: "\n"))
            """
        } else {
            // User clicked on "Cancel"
            return
        }
    }
    
    @IBAction func copyServerUrl(_ sender: Any) {
        NSPasteboard.general.setString("ws://localhost:8777", forType: .string)
    }
    
    @IBAction func connect(_ sender: Any) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.celeste")
        
        if apps.isEmpty {
            print("No celeste app running")
            return
        }
        
        do {
            self.eventGenerator = try CelesteEventGenerator(pid: apps[0].processIdentifier)
            runTimer = true
        } catch {
            print("Error creating event generator for header: \(error)")
        }
        if let signature = eventGenerator?.scanner.headerSignature {
            signatureLabel.stringValue = "Connected with signature: " + signature.debugString()
        } else {
            signatureLabel.stringValue = "Not connected"
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
        self.reset = reset
        self.route = route
    }
}
