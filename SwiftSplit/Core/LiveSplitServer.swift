//
//  LiveSplitServer.swift
//  SwiftSplit
//
//  Created by Pierce Corcoran on 11/25/20.
//  Copyright © 2020 Pierce Corcoran. All rights reserved.
//

import Dispatch
import NIO
import NIOHTTP1
import NIOWebSocket

class LiveSplitServerHandler: SimpleWebSocketServer {
    // we don't receive anything, just send
}

class LiveSplitServer {
    private let handler = LiveSplitServerHandler()
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    
    var allowMultipleClients: Bool {
        get { handler.allowMultipleClients }
        set(value) { handler.allowMultipleClients = value}
    }
    var connectedClients: Int {
        get { handler.connectedClients }
    }

    init(host: String, port: Int) throws {
        let channel = try startWebSocketServer(host: host, port: port, group: group, handler: handler)

        guard let localAddress = channel.localAddress else {
            fatalError("Address was unable to bind. Please check that the socket was not closed or that the address family was understood.")
        }
        print("Server started and listening on \(localAddress)")
    }

    deinit {
        try! group.syncShutdownGracefully()
    }
    
    private func send(_ message: String) {
        handler.sendToAll(text: message)
    }
    
    public func start() {
        send("start")
    }
    
    public func split() {
        send("split")
    }
    
    public func splitOrStart() {
        send("splitorstart")
    }
    
    public func reset() {
        send("reset")
    }
    
    public func togglePause() {
        send("togglepause")
    }
    
    public func undo() {
        send("undo")
    }
    
    public func skip() {
        send("skip")
    }
    
    public func initGameTime() {
        send("initgametime")
    }
    
    public func setGameTime(seconds: Double) {
        send("setgametime \(seconds)")
    }
    
    public func setLoadingTimes(seconds: Double) {
        send("setloadingtimes \(seconds)")
    }
    
    public func pauseGameTime() {
        send("pausegametime")
    }
    
    public func resumeGameTime() {
        send("resumegametime")
    }
    
    public func setGameTime(running: Bool) {
        if running {
            resumeGameTime()
        } else {
            pauseGameTime()
        }
    }
}
