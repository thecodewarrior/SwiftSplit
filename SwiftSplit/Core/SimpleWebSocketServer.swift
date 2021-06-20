//
//  Server.swift
//  SwiftSplit
//
//  Created by Pierce Corcoran on 11/25/20.
//  Copyright © 2020 Pierce Corcoran. All rights reserved.
//

import Dispatch
import NIO
import NIOHTTP1
import NIOWebSocket


class SimpleWebSocketServer: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    
    // All access to channels is guarded by channelsSyncQueue.
    private let channelsSyncQueue = DispatchQueue(label: "channelsQueue")
    private var channels: [ObjectIdentifier: Channel] = [:]
    private var awaitingClose: Set<ObjectIdentifier> = Set()
    var allowMultipleClients: Bool = true
    var connectedClients: Int {
        get { channels.count }
    }
    
    func handlerAdded(ctx: ChannelHandlerContext) {
        let channel = ctx.channel
        if(!allowMultipleClients) {
            self.channelsSyncQueue.async {
                self.channels.forEach { (_, channel) in
                    let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: channel.allocator.buffer(capacity: 0))
                    channel.writeAndFlush(self.wrapOutboundOut(frame), promise: nil)
                    self.awaitingClose.insert(ObjectIdentifier(channel))
                }
                self.channels[ObjectIdentifier(channel)] = channel
            }
        }
    }
    
    func handlerRemoved(ctx: ChannelHandlerContext) {
        let channel = ctx.channel
        self.channelsSyncQueue.async {
            self.channels.removeValue(forKey: ObjectIdentifier(channel))
        }
    }

    public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        
        switch frame.opcode {
        case .unknownNonControl, .unknownControl:
            self.receive(unknown: frame, ctx: ctx)
        case .connectionClose:
            self.receive(connectionClose: frame, ctx: ctx)
        case .ping:
            self.receive(ping: frame, ctx: ctx)
        case .pong:
            self.receive(pong: frame, ctx: ctx)
        case .continuation:
            self.receive(continuation: frame, ctx: ctx)
        case .text:
            self.receive(text: frame, ctx: ctx)
        case .binary:
            self.receive(binary: frame, ctx: ctx)
        }
    }
    
    public func channelReadComplete(ctx: ChannelHandlerContext) {
        ctx.flush()
    }
    
    // MARK: Handling packets
    
    private func receive(connectionClose frame: WebSocketFrame, ctx: ChannelHandlerContext) {
        // Handle a received close frame. In websockets, we're just going to send the close
        // frame and then close, unless we already sent our own close frame.
        if awaitingClose.contains(ObjectIdentifier(ctx.channel)) {
            let channel = ctx.channel
            // Cool, we started the close and were waiting for the user. We're done.
            ctx.close(promise: nil)
            self.channelsSyncQueue.async { self.awaitingClose.remove(ObjectIdentifier(channel)) }
        } else {
            var data = frame.unmaskedData
            let closeDataCode = data.readSlice(length: 2) ?? ctx.channel.allocator.buffer(capacity: 0)
            let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: closeDataCode)
            _ = ctx.write(self.wrapOutboundOut(closeFrame)).map { () in
                ctx.close(promise: nil)
            }
        }
    }
    
    private func receive(ping frame: WebSocketFrame, ctx: ChannelHandlerContext) {
        var frameData = frame.data
        let maskingKey = frame.maskKey
        
        if let maskingKey = maskingKey {
            frameData.webSocketUnmask(maskingKey)
        }
        
        let responseFrame = WebSocketFrame(fin: true, opcode: .pong, data: frameData)
        ctx.write(self.wrapOutboundOut(responseFrame), promise: nil)
    }
    
    private func receive(unknown frame: WebSocketFrame, ctx: ChannelHandlerContext) {
        // We have hit an error, we want to close. We do that by sending a close frame and then
        // shutting down the write side of the connection.
        var data = ctx.channel.allocator.buffer(capacity: 2)
        data.write(webSocketErrorCode: .protocolError)
        let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: data)
        ctx.write(self.wrapOutboundOut(frame)).whenComplete {
            ctx.close(mode: .output, promise: nil)
        }
        
        let channel = ctx.channel
        self.channelsSyncQueue.async { self.awaitingClose.insert(ObjectIdentifier(channel)) }
    }
    
    open func receive(pong frame: WebSocketFrame, ctx: ChannelHandlerContext) {
        // no-op
    }

    open func receive(continuation frame: WebSocketFrame, ctx: ChannelHandlerContext) {
        // no-op
    }
    
    open func receive(binary frame: WebSocketFrame, ctx: ChannelHandlerContext) {
        // no-op
    }
    
    open func receive(text frame: WebSocketFrame, ctx: ChannelHandlerContext) {
        // no-op
    }
    
    func sendToAll(text: String) {
        let bytes = [UInt8](text.utf8)
        self.channelsSyncQueue.async {
            self.channels.forEach { (_, channel) in
                var buffer = channel.allocator.buffer(capacity: bytes.count)
                buffer.write(bytes: bytes)
                
                let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
                channel.writeAndFlush(self.wrapOutboundOut(frame), promise: nil)
            }
        }
    }
}

final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    private var responseBody: ByteBuffer!
    private var websocketResponse = "<html></html>"
    
    func channelRegistered(ctx: ChannelHandlerContext) {
        var buffer = ctx.channel.allocator.buffer(capacity: websocketResponse.utf8.count)
        buffer.write(string: websocketResponse)
        self.responseBody = buffer
    }
    
    func channelUnregistered(ctx: ChannelHandlerContext) {
        self.responseBody = nil
    }
    
    func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        
        // We're not interested in request bodies here: we're just serving up GET responses
        // to get the client to initiate a websocket request.
        guard case .head(let head) = reqPart else {
            return
        }
        
        // GETs only.
        guard case .GET = head.method else {
            self.respond405(ctx: ctx)
            return
        }
        
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/html")
        headers.add(name: "Content-Length", value: String(self.responseBody.readableBytes))
        headers.add(name: "Connection", value: "close")
        let responseHead = HTTPResponseHead(version: .init(major: 1, minor: 1),
                                            status: .ok,
                                            headers: headers)
        ctx.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        ctx.write(self.wrapOutboundOut(.body(.byteBuffer(self.responseBody))), promise: nil)
        ctx.write(self.wrapOutboundOut(.end(nil))).whenComplete {
            ctx.close(promise: nil)
        }
        ctx.flush()
    }
    
    private func respond405(ctx: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Connection", value: "close")
        headers.add(name: "Content-Length", value: "0")
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1),
                                    status: .methodNotAllowed,
                                    headers: headers)
        ctx.write(self.wrapOutboundOut(.head(head)), promise: nil)
        ctx.write(self.wrapOutboundOut(.end(nil))).whenComplete {
            ctx.close(promise: nil)
        }
        ctx.flush()
    }
}

func startWebSocketServer(host: String, port: Int, group: EventLoopGroup, handler: SimpleWebSocketServer) throws -> Channel {
    let upgrader = WebSocketUpgrader(shouldUpgrade: { (head: HTTPRequestHead) in HTTPHeaders() },
                                     upgradePipelineHandler: { (channel: Channel, _: HTTPRequestHead) in
                                        channel.pipeline.add(handler: handler)
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
    
    return try bootstrap.bind(host: host, port: port).wait()
}
