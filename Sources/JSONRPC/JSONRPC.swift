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

import Dispatch
import Foundation
import NIO
import NIOCore

public enum ConnectionType: Equatable {
    case Server
    case Client
}

public enum ConnectionState: Equatable {
    case initializing
    case starting(String)
    case started
    case stopping
    case stopped
}

public struct State: Equatable {
    public var state: ConnectionState
    public var type: ConnectionType?

    public init(state: ConnectionState, type: ConnectionType? = nil) {
        self.state = state
        self.type = type
    }
}

struct OutstandingRequestType {
    public var requestType: _RequestType.Type
    public var responseType: ResponseType.Type
}

struct RequestCancelKey: Hashable {
    public var client: ObjectIdentifier
    public var request: RequestID
    public init(client: ObjectIdentifier, request: RequestID) {
        self.client = client
        self.request = request
    }
}

public final class JSONRPC {
    public let group: EventLoopGroup
    private let config: Config
    private var channel: Channel?
    private let messageRegistry: MessageRegistry
    private var type: ConnectionType?

    private var requestHandlers: [ObjectIdentifier: Any] = [:]
    private var notificationHandlers: [ObjectIdentifier: Any] = [:]
    private var requestCancellation: [RequestCancelKey: CancellationToken] = [:]
    private var outstandingRequests: [RequestID: OutstandingRequestType] = [:]

    public init(messageRegistry: MessageRegistry,
                config: Config = Config())
    {
        self.messageRegistry = messageRegistry
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: config.numberOfThreads)
        self.config = config
        self.state = State(state: .initializing)
    }

    deinit {
        assert(self.state.state == .stopped)
    }

    public func startClient(host: String, port: Int) -> EventLoopFuture<JSONRPC> {
        assert(self.state.state == .initializing)
        let callbackRegistry = { id in
            guard let outstanding = self.outstandingRequests[id] else {
                return nil
            }
            return outstanding.responseType
        } as JSONRPCMessage.ResponseTypeCallback
        let handler = JSONRPCMessageHandler(self)
        let bootstrap = ClientBootstrap(group: self.group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([IdleStateHandler(readTimeout: self.config.timeout), HalfCloseOnTimeout()])
                    .flatMap {
                        let framingHandler = ContentLengthHeaderCodec()
                        return channel.pipeline.addHandlers([ByteToMessageHandler(framingHandler),
                                                             MessageToByteHandler(framingHandler)])
                    }.flatMap {
                        channel.pipeline.addHandlers([
                            CodableCodec<JSONRPCMessage, JSONRPCMessage>(messageRegistry: self.messageRegistry, callbackRegistry: callbackRegistry),
                            handler,
                        ])
                    }
            }

        self.state = State(state: .starting("\(host):\(port)"), type: .Server)
        return bootstrap.connect(host: host, port: port).flatMap { channel in
            self.channel = channel
            ///
            self.state = State(state: .started, type: .Server)
            return channel.eventLoop.makeSucceededFuture(self)
        }
    }

    public func startServer(host: String, port: Int) -> EventLoopFuture<(ServerConnection, Channel)> {
        self.type = .Server
        assert(self.state.state == .initializing)
        let handler = JSONRPCMessageHandler(self)
        let callbackRegistry = { id in
            guard let outstanding = self.outstandingRequests[id] else {
                return nil
            }
            return outstanding.responseType
        } as JSONRPCMessage.ResponseTypeCallback

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandlers([IdleStateHandler(readTimeout: self.config.timeout), HalfCloseOnTimeout()])
                    .flatMap {
                        let framingHandler = ContentLengthHeaderCodec()
                        return channel.pipeline.addHandlers([ByteToMessageHandler(framingHandler),
                                                             MessageToByteHandler(framingHandler)])
                    }.flatMap {
                        channel.pipeline.addHandlers([CodableCodec<JSONRPCMessage, JSONRPCMessage>(messageRegistry: self.messageRegistry, callbackRegistry: callbackRegistry),
                                                      handler])
                    }
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        self.state = State(state: .starting("\(host):\(port)"), type: .Client)
        return bootstrap.bind(host: host, port: port).flatMap { channel in
            self.channel = channel
            self.state = State(state: .started, type: .Client)
            return channel.eventLoop.makeSucceededFuture((handler, channel))
        }
    }

    func _stop() -> EventLoopFuture<Void> {
        let state = self.state
        if state.state != .started {
            return self.group.next().makeFailedFuture(ConnectionError.notReady)
        }
        guard let channel = self.channel else {
            return self.group.next().makeFailedFuture(ConnectionError.notReady)
        }
        self.state = State(state: .stopping, type: state.type)
        channel.closeFuture.whenComplete { _ in
            self.state = State(state: .stopped, type: state.type)
        }
        return channel.close()
    }

    public func stop(callback: @escaping (Error?) -> Void) {
        self._stop().whenComplete { _ in
            self.group.shutdownGracefully(callback)
        }
    }

    private var _state = State(state: .initializing)
    private let lock = NSLock()
    private var state: State {
        get {
            return self.lock.withLock {
                _state
            }
        }
        set {
            self.lock.withLock {
                _state = newValue
                log("\(self) \(_state)")
            }
        }
    }
}

public extension JSONRPC {
    internal func readyToSend(shouldLog: Bool = true) -> Bool {
//        precondition(self.state == .connected, "tried to send message before start")
//        if self.state != .connected {
//            return false
//        }

        guard self.channel != nil else {
            return false
        }

        return true
    }

    func record<Request>(_ request: Request) -> RequestID where Request: RequestType {
        let id = RequestID.string(UUID().uuidString)
        self.outstandingRequests[id] = OutstandingRequestType(
            requestType: Request.self,
            responseType: Request.Response.self)
        return id
    }

    @discardableResult
    func send(message: JSONRPCMessage) -> EventLoopFuture<JSONRPCMessage> {
        let promise: EventLoopPromise<JSONRPCMessage> = self.channel!.eventLoop.makePromise()
        let future = self.channel!.eventLoop.submit {
            let wrapper = JSONRPCMessageWrapper(message: message, promise: promise)
            let wait = self.channel!.writeAndFlush(wrapper)
            wait.cascadeFailure(to: promise)
        }
        return future.flatMap {
            promise.futureResult
        }
    }

    @discardableResult
    func send<Request>(_ request: Request) -> EventLoopFuture<JSONRPCResult<Request.Response>> where Request: RequestType {
        guard self.readyToSend() else {
            return self.group.next().makeFailedFuture(ConnectionError.notReady)
        }

        let id = self.record(request)
        return self.send(message: JSONRPCMessage.request(request, id: id)).map { anyResult in
            switch anyResult {
            case .response(let response, id: _):
                return .success(response as! Request.Response)
            case .errorResponse(let error, id: _):
                return .failure(error)
            default:
                return .failure(ResponseError.unknown("unknown result"))
            }
        }
    }

    func send<Notification>(_ notification: Notification) where Notification: NotificationType {
        self.send(message: JSONRPCMessage.notification(notification))
    }

    func sendReply(_ response: JSONRPCResult<ResponseType>, id: RequestID) {
        switch response {
        case .success(let result):
            self.send(message: JSONRPCMessage.response(result, id: id))
        case .failure(let error):
            self.send(message: JSONRPCMessage.errorResponse(error, id: id))
        }
    }
}

extension JSONRPC: MessageHandler {
    // MARK: Request registration.

    /// Register the given request handler, which must be a method on `self`.
    ///
    /// Must be called on `queue`.
    public func register<Server, R>(_ requestHandler: @escaping (Server) -> (Request<R>) -> Void) {
        // We can use `unowned` here because the handler is run synchronously on `queue`.
        precondition(self is Server)
        self.requestHandlers[ObjectIdentifier(R.self)] = { [unowned self] request in
            requestHandler(self as! Server)(request)
        }
    }

    /// Register the given notification handler, which must be a method on `self`.
    ///
    /// Must be called on `queue`.
    public func register<Server, N>(_ noteHandler: @escaping (Server) -> (Notification<N>) -> Void) {
        // We can use `unowned` here because the handler is run synchronously on `queue`.
        self.notificationHandlers[ObjectIdentifier(N.self)] = { [unowned self] note in
            noteHandler(self as! Server)(note)
        }
    }

    /// Register the given request handler.
    ///
    /// Must be called on `queue`.
    public func register<R>(_ requestHandler: @escaping (Request<R>) -> Void) {
        self.requestHandlers[ObjectIdentifier(R.self)] = requestHandler
    }

    /// Register the given notification handler.
    ///
    /// Must be called on `queue`.
    public func register<N>(_ noteHandler: @escaping (Notification<N>) -> Void) {
        self.notificationHandlers[ObjectIdentifier(N.self)] = noteHandler
    }

    /// Handle an unknown request.
    ///
    /// By default, replies with `methodNotFound` error.
    func handleUnknown<R>(_ request: Request<R>) {
        request.reply(.failure(ResponseError.methodNotFound(R.method)))
    }

    /// Handle an unknown notification.
    func handleUnknown<N>(_ notification: Notification<N>) {
        // Do nothing.
    }

    public func handle<N>(_ params: N, from clientID: ObjectIdentifier) where N: NotificationType {
        let notification = Notification(params, clientID: clientID)
        guard let handler = notificationHandlers[ObjectIdentifier(N.self)] as? ((Notification<N>) -> Void) else {
            self.handleUnknown(notification)
            return
        }
        handler(notification)
    }

    public func handle<R>(_ params: R, id: RequestID, from clientID: ObjectIdentifier, reply: @escaping (JSONRPCResult<R.Response>) -> Void) where R: RequestType {
        let cancellationToken = CancellationToken()
        let key = RequestCancelKey(client: clientID, request: id)

        self.requestCancellation[key] = cancellationToken

        let request = Request(params, id: id, clientID: clientID, cancellation: cancellationToken, reply: { [weak self] result in
            self?.requestCancellation[key] = nil
            reply(result)
        })

        guard let handler = requestHandlers[ObjectIdentifier(R.self)] as? ((Request<R>) -> Void) else {
            self.handleUnknown(request)
            return
        }

        handler(request)
    }
}

