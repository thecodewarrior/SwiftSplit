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

class LiveSplitServerHandler: MultiClientWebSocketHandler {
    // we don't receive anything, just send
}

class LiveSplitServer {
    let handler = LiveSplitServerHandler()
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    init(host: String, port: Int) throws {
        let upgrader = WebSocketUpgrader(shouldUpgrade: { (head: HTTPRequestHead) in HTTPHeaders() },
                                         upgradePipelineHandler: { (channel: Channel, _: HTTPRequestHead) in
                                            channel.pipeline.add(handler: self.handler)
        })
        
        let bootstrap: ServerBootstrap
        bootstrap = ServerBootstrap(group: group)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            
            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
                let httpHandler = HTTPHandler()
                let config: HTTPUpgradeConfiguration = (
                    upgraders: [ upgrader ],
                    completionHandler: { _ in channel.pipeline.remove(handler: httpHandler, promise: nil) }
                )
                return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: config).then { channel.pipeline.add(handler: httpHandler) }
        }
            
            // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

        let channel = try bootstrap.bind(host: host, port: port).wait()

        guard let localAddress = channel.localAddress else {
            fatalError("Address was unable to bind. Please check that the socket was not closed or that the address family was understood.")
        }
        print("Server started and listening on \(localAddress)")
    }

    deinit {
        try! group.syncShutdownGracefully()
    }
    
    public func send(message: String) {
        handler.sendToAll(text: message)
    }
}
