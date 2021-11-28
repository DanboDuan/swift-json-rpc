//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import NIOCore

public enum State: Equatable {
    case initializing
    case starting(String)
    case started
    case stopping
    case stopped
}

public enum ClientType {
    case all
    case some(id: ObjectIdentifier)
}

public protocol NotificationHandlerRegistry: AnyObject {
    /// Register the given request handler.
    func register<R>(_ requestHandler: @escaping (Request<R>) -> Void)
}

public protocol ServerNotificationSender: AnyObject {
    /// Send a notification to clients
    /// if nil clients, send it to all clients
    func send<Notification>(_ notification: Notification, to client: ClientType) where Notification: NotificationType
}

public protocol RPCConnection {
    func stop() -> EventLoopFuture<Void>
    var closeFuture: EventLoopFuture<Void> { get }
    var state: State { get }
}

/// An abstract client connection handler, allow server to send messages to a client
public protocol RPCServer: NotificationHandlerRegistry, ServerNotificationSender, RPCConnection {
    /// bind
    func bind(to address: ConnectionAddress) -> EventLoopFuture<Void>
    /// Register the given notification handler.
    func register<N>(_ noteHandler: @escaping (Notification<N>) -> Void)
}

/// An abstract connection, allow messages to be sent to a (potentially remote) `MessageHandler`.
public protocol RPCClient: NotificationHandlerRegistry, RPCConnection {
    /// connect
    func connect(to address: ConnectionAddress) -> EventLoopFuture<Void>
    /// Send a notification without a reply.
    func send<Notification>(_ notification: Notification) where Notification: NotificationType

    /// Send a request and receive a reply.
    func send<Request>(_ request: Request) -> Response<Request> where Request: RequestType
}

/// An abstract message handler, such as a language server or client.
public protocol MessageHandler: AnyObject {
    /// Handle a notification without a reply.
    func handle<Notification>(_: Notification, from: ObjectIdentifier) where Notification: NotificationType

    /// Handle a request and (asynchronously) receive a reply.
    /// EventLoopFuture<JSONRPCResult<Request.Response>>
    func handle<Request>(_: Request, id: RequestID, from clientID: ObjectIdentifier) -> EventLoopFuture<JSONRPCResult<Request.Response>> where Request: RequestType
}
