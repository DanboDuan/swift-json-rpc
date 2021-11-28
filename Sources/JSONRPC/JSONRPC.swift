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
import NIOCore

struct RequestCancelKey: Hashable {
    public var client: ObjectIdentifier
    public var request: RequestID
    public init(client: ObjectIdentifier, request: RequestID) {
        self.client = client
        self.request = request
    }
}

public final class JSONRPC {
    let group: EventLoopGroup
    let config: Config
    var requestHandlers: [ObjectIdentifier: Any] = [:]
    var notificationHandlers: [ObjectIdentifier: Any] = [:]

    var requestCancellation: [RequestCancelKey: CancellationToken] = [:]
    var handler: JSONRPCMessageHandler?
    var channel: Channel?

    private var _state = State.initializing
    private let lock = NSLock()

    init(config: Config) {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: config.numberOfThreads)
        self.config = config
        self.state = .initializing
        JSONRPCLogger.shared.enable = config.log
        self.register(JSONRPC.onCancelRequestNotification)
    }

    public static func createServer(config: Config) -> RPCServer {
        let server = JSONRPC(config: config)
        return server
    }

    public static func createClient(config: Config) -> RPCClient {
        let client = JSONRPC(config: config)
        return client
    }

    deinit {
        assert(self.state == .stopped)
    }
}

extension JSONRPC: RPCConnection {
    public var state: State {
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

    public func stop() -> EventLoopFuture<Void> {
        let state = self.state
        if state != .started {
            return self.group.next().makeFailedFuture(ConnectionError.notReady)
        }
        guard let channel = self.channel else {
            return self.group.next().makeFailedFuture(ConnectionError.notReady)
        }
        self.state = .stopping
        channel.closeFuture.whenComplete { _ in
            self.state = .stopped
            do {
                try self.group.syncShutdownGracefully()
            } catch {
                exit(0)
            }
        }

        return channel.close()
    }

    public var closeFuture: EventLoopFuture<Void> {
        return self.channel!.closeFuture
    }
}

extension JSONRPC: NotificationHandlerRegistry {
    // MARK: Handler registration.

    /// Register the given request handler, which must be a method on `self`.
    ///
    /// Must be called on `queue`.
    func register<Server, R>(_ requestHandler: @escaping (Server) -> (Request<R>) -> Void) {
        // We can use `unowned` here because the handler is run synchronously on `queue`.
        precondition(self is Server)
        self.requestHandlers[ObjectIdentifier(R.self)] = { [unowned self] request in
            requestHandler(self as! Server)(request)
        }
    }

    /// Register the given notification handler, which must be a method on `self`.
    ///
    /// Must be called on `queue`.
    func register<Server, N>(_ noteHandler: @escaping (Server) -> (Notification<N>) -> Void) {
        // We can use `unowned` here because the handler is run synchronously on `queue`.
        self.notificationHandlers[ObjectIdentifier(N.self)] = { [unowned self] note in
            noteHandler(self as! Server)(note)
        }
    }

    /// Register the given notification handler.
    public func register<N>(_ noteHandler: @escaping (Notification<N>) -> Void) {
        self.notificationHandlers[ObjectIdentifier(N.self)] = noteHandler
    }

    public func onCancelRequestNotification(_ notification: Notification<CancelRequestNotification>) {
        let key = RequestCancelKey(client: notification.clientID, request: notification.params.id)
        self.requestCancellation[key]?.cancel()
    }
}

extension JSONRPC: MessageHandler {
    public func handle<N>(_ params: N, from clientID: ObjectIdentifier) where N: NotificationType {
        let notification = Notification(params, clientID: clientID)
        guard let handler = notificationHandlers[ObjectIdentifier(N.self)] as? ((Notification<N>) -> Void) else {
            return
        }
        handler(notification)
    }

    public func handle<R>(_ params: R, id: RequestID, from clientID: ObjectIdentifier) -> EventLoopFuture<JSONRPCResult<R.Response>> where R: RequestType {
        guard let handler = requestHandlers[ObjectIdentifier(R.self)] as? ((Request<R>) -> Void) else {
            let error = ResponseError.methodNotFound(R.method)
            return self.group.next().makeSucceededFuture(.failure(error))
        }

        let promise: EventLoopPromise<JSONRPCResult<R.Response>> = self.group.next().makePromise()
        let cancellationToken = CancellationToken()
        let key = RequestCancelKey(client: clientID, request: id)

        let request = Request(params, id: id, clientID: clientID, cancellation: cancellationToken, promise: promise)

        self.requestCancellation[key] = cancellationToken

        promise.futureResult.whenComplete { [weak self] _ in
            self?.requestCancellation[key] = nil
        }
        let future = self.group.next().submit {
            handler(request)
        }

        return future.flatMap {
            promise.futureResult
        }
    }
}
