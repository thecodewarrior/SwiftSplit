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
    @IBOutlet weak var timerRunningIndicator: NSProgressIndicator!
    
    var timer: Timer? = nil
    var runTimer: Bool = false
    var server: LiveSplitServer? = nil

    override func viewDidLoad() {
        super.viewDidLoad()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.timerRunningIndicator.isHidden = !self.runTimer
            if(self.runTimer) {
                self.updateInfo()
            }
        }

        signatureLabel.stringValue = "No Signature"
        updateInfoView(with: AutoSplitterInfo())
        server = try? LiveSplitServer(host: "localhost", port: 8777)
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    func updateInfo() {
        
        guard let eventGenerator = self.eventGenerator else {
            print("Memory is nil")
            return
        }
        do {
            let events = try eventGenerator.updateInfo()
            updateInfoView(with: eventGenerator.autoSplitterInfo)
            processEvents(events)
        } catch {
            updateInfoView(with: AutoSplitterInfo())
            runTimer = false
            print("Error getting info: \(error)")
        }
    }
    
    func tapKey(_ keyCode: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false)?.post(tap: .cghidEventTap)
    }
    
    func nextSplitKey() {
        print("Tapping next split")
        tapKey(kVK_F12)
    }
    func resetKey() {
        print("Tapping reset")
        tapKey(kVK_F10)
    }
    
    func send(_ command: String) {
        server?.send(message: command)
    }
    
    let run = [
        ("s3",   "0x-a"),
        ("08-a", "09-b"),
        ("10-x", "11-x"),
        ("09-b", "10-c"),
        ("09-b", "11-b"),
        ("12-x", "11-a"),
        ("02-d", "00-d")
    ]
    var runIndex = 0

    func processEvents(_ events: [CelesteEvent]) {
        for event in events {
            switch event {
            case .resetChapter(chapter: _):
                send("reset")
            case .startChapter(chapter: _):
                runIndex = 0
                send("start")
            case .completeChapter(chapter: _):
                send("split")
            case let .levelSwitch(old, new):
                if runIndex < run.count && old == run[runIndex].0 && new == run[runIndex].1 {
                    runIndex += 1
                    send("split")
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

    @IBAction func findHeader(_ sender: Any) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.celeste")
        
        if apps.isEmpty {
            print("No celeste app running")
            return
        }
        
        do {
            self.eventGenerator = try CelesteEventGenerator(pid: apps[0].processIdentifier)
        } catch {
            print("Error creating event generator for header: \(error)")
        }
        if let signature = eventGenerator?.scanner.headerSignature {
            signatureLabel.stringValue = "Signature: " + signature.debugString()
        } else {
            signatureLabel.stringValue = "No Signature"
        }
    }
    
    @IBAction func getInfo(_ sender: Any) {
        updateInfo()
    }
    
    @IBAction func toggleAutoUpdate(_ sender: Any) {
        runTimer = !runTimer
    }
    
    @IBAction func runDebugScan(_ sender: Any) {
        guard let memory = self.eventGenerator?.scanner else {
            print("Memory is nil")
            return
        }
        
        do {
            try memory.debugScan()
        } catch {
            print("Error running debug scan: \(error)")
        }
    }
    
    @IBAction func runPointerDebug(_ sender: Any) {
        guard let memory = self.eventGenerator?.scanner else {
            print("Memory is nil")
            return
        }
        
        do {
            try memory.debugPointers()
        } catch {
            print("Error running debug scan: \(error)")
        }
    }
}

