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

import Foundation
import NIO

struct JSONRPCMessageWrapper {
    let message: JSONRPCMessage
    let promise: EventLoopPromise<JSONRPCMessage>?
}

struct OutstandingRequestType {
    public var requestType: _RequestType.Type
    public var responseType: ResponseType.Type
}

enum ConnectionType: Equatable {
    case Server
    case Client
}

final class JSONRPCMessageHandler: ChannelInboundHandler, ChannelOutboundHandler {
    public typealias InboundIn = JSONRPCMessage
    public typealias OutboundIn = JSONRPCMessageWrapper
    public typealias OutboundOut = JSONRPCMessage

    private unowned let receiveHandler: MessageHandler
    private var channelConnections: [ObjectIdentifier: Channel] = [:]
    private var outstandingRequests: [RequestID: OutstandingRequestType] = [:]

    private var queue = [RequestID: EventLoopPromise<JSONRPCMessage>]()
    private let type: ConnectionType

    public init(_ handler: MessageHandler, type: ConnectionType) {
        self.receiveHandler = handler
        self.type = type
    }

    /// outbound
    /// client send request or notification
    /// server send notification
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let wrapper = self.unwrapOutboundIn(data)
        if case .request(let request, let id) = wrapper.message {
            self.outstandingRequests[id] = OutstandingRequestType(
                requestType: Swift.type(of: request),
                responseType: request.responseType())
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
            let future = request._handle(self.receiveHandler, id: id, from: ObjectIdentifier(context.channel))

            future.whenSuccess { response in
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
            future.whenFailure { error in
                let result: JSONRPCMessage
                if let response = error as? ResponseError {
                    result = JSONRPCMessage.errorResponse(response, id: id)
                } else {
                    let response = ResponseError(code: .unknownErrorCode, error: error)
                    result = JSONRPCMessage.errorResponse(response, id: id)
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
            context.writeAndFlush(self.wrapOutboundOut(response), promise: nil)
        case CodecError.requestTooLarge:
            let responseError = ResponseError(code: .invalidRequest, error: error)
            let response: JSONRPCMessage = .errorResponse(responseError, id: .string("unknown"))
            context.writeAndFlush(self.wrapOutboundOut(response), promise: nil)
        default:
            if let decodingError = error as? MessageDecodingError {
                let responseError = ResponseError(decodingError)
                let response: JSONRPCMessage = .errorResponse(responseError, id: decodingError.id)
                context.writeAndFlush(self.wrapOutboundOut(response), promise: nil)
            } else {
                let responseError = ResponseError(code: .internalError, error: error)
                let response: JSONRPCMessage = .errorResponse(responseError, id: .string("unknown"))
                context.writeAndFlush(self.wrapOutboundOut(response), promise: nil)
            }
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

extension JSONRPCMessageHandler: ServerNotificationSender {
    public func send<Notification>(_ notification: Notification, to client: ClientType) where Notification: NotificationType {
        let message = JSONRPCMessage.notification(notification)
        let wrapper = JSONRPCMessageWrapper(message: message, promise: nil)
        switch client {
        case .some(id: let id):
            guard let channel = self.channelConnections[id] else {
                return
            }
            channel.eventLoop.execute {
                channel.writeAndFlush(NIOAny(wrapper), promise: nil)
            }
        case .all:
            self.channelConnections.forEach { (_: ObjectIdentifier, channel: Channel) in
                channel.eventLoop.execute {
                    channel.writeAndFlush(NIOAny(wrapper), promise: nil)
                }
            }
        }
    }
}

extension JSONRPCMessageHandler: ResponseTypeCallback {
    public func responseType(for id: RequestID) -> ResponseType.Type? {
        guard let outstanding = self.outstandingRequests[id] else {
            return nil
        }

        return outstanding.responseType
    }
}
