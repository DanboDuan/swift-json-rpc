// Copyright 2021 Bob
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import NIO

final class JSONRPCMessageHandler: ChannelInboundHandler, ChannelOutboundHandler {
    public typealias InboundIn = JSONRPCMessage
    public typealias OutboundIn = JSONRPCMessageWrapper
    public typealias OutboundOut = JSONRPCMessage

    private let receiveHandler: MessageHandler
    private var channelConnections: [ObjectIdentifier: Channel] = [:]

    private var queue = [RequestID: EventLoopPromise<JSONRPCMessage>]()
    private let type: ConnectionType

    public init(_ handler: MessageHandler, type: ConnectionType = .Server) {
        self.receiveHandler = handler
        self.type = type
    }

    /// outbound
    /// client send request or notification
    /// server send notification
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let wrapper = self.unwrapOutboundIn(data)
        if case .request(_, let id) = wrapper.message {
            self.queue[id] = wrapper.promise
        }
        context.write(wrapOutboundOut(wrapper.message), promise: promise)
    }

    /// inbound
    /// server get request and notification
    /// client get response and notification
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        switch message {
        case .notification(let notification):
            notification._handle(self.receiveHandler, from: ObjectIdentifier(context.channel))
        case .request(let request, id: let id):
            request._handle(self.receiveHandler, id: id, from: ObjectIdentifier(context.channel)) { response, id in
                let result: JSONRPCMessage
                switch response {
                case .success(let value):
                    result = JSONRPCMessage.response(value, id: id)
                case .failure(let error):
                    result = JSONRPCMessage.errorResponse(error, id: id)
                }
                context.eventLoop.execute {
                    context.writeAndFlush(self.wrapOutboundOut(result), promise: nil)
                }
            }
        case .response(let response, id: let id):
            if let promise = self.queue.removeValue(forKey: id) {
                promise.succeed(message)
            } else {
                log("server receive response \(String(describing: id)) \(String(describing: response)) ", level: .error)
            }
        case .errorResponse(let error, id: let id):
            if let requestID = id, let promise = self.queue.removeValue(forKey: requestID) {
                promise.succeed(message)
            } else {
                log("server receive errorResponse \(String(describing: id)) \(String(describing: error))", level: .error)
            }
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        if let remoteAddress = context.remoteAddress {
            log("errorCaught client \(remoteAddress) \(String(describing: error))", level: .error)
        }
        switch error {
        case CodecError.badJSON:
            let responseError = ResponseError(code: .parseError, error: error)
            let response: JSONRPCMessage = .errorResponse(responseError, id: .string("unknown"))
            context.channel.writeAndFlush(self.wrapOutboundOut(response), promise: nil)
        case CodecError.requestTooLarge:
            let responseError = ResponseError(code: .invalidRequest, error: error)
            let response: JSONRPCMessage = .errorResponse(responseError, id: .string("unknown"))
            context.channel.writeAndFlush(self.wrapOutboundOut(response), promise: nil)
        default:
            let responseError = ResponseError(code: .internalError, error: error)
            let response: JSONRPCMessage = .errorResponse(responseError, id: .string("unknown"))
            context.channel.writeAndFlush(self.wrapOutboundOut(response), promise: nil)
        }
    }

    public func channelActive(context: ChannelHandlerContext) {
        if let remoteAddress = context.remoteAddress {
            if self.type == .Server {
                log("client \(remoteAddress) connected")
            } else {
                log("connected server \(remoteAddress) ")
            }
            let channel = context.channel
            self.channelConnections[ObjectIdentifier(channel)] = channel
        }
    }

    public func channelInactive(context: ChannelHandlerContext) {
        if let remoteAddress = context.remoteAddress {
            log("client \(remoteAddress) disconnect")
            if self.type == .Server {
                log("client \(remoteAddress) connected")
            } else {
                log("disconnect server \(remoteAddress) ")
            }
            self.channelConnections.removeValue(forKey: ObjectIdentifier(context.channel))
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if (event as? IdleStateHandler.IdleStateEvent) == .read {
            self.errorCaught(context: context, error: ConnectionError.timeout)
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }
}

extension JSONRPCMessageHandler: ServerConnection {
    func send<Notification>(_ notification: Notification, clients: [ObjectIdentifier]?) where Notification: NotificationType {
        guard let clients = clients else {
            self.channelConnections.forEach { (_: ObjectIdentifier, channel: Channel) in
                try? channel.eventLoop.submit {
                    channel.writeAndFlush(self.wrapOutboundOut(JSONRPCMessage.notification(notification)), promise: nil)
                }.wait()
            }

            return
        }

        clients.compactMap { self.channelConnections[$0] }.forEach { channel in
            try? channel.eventLoop.submit {
                channel.writeAndFlush(self.wrapOutboundOut(JSONRPCMessage.notification(notification)), promise: nil)
            }.wait()
        }
    }
}
