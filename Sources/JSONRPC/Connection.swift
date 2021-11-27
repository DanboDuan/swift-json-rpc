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

import NIO

public enum ClientType {
    case all
    case some(id: ObjectIdentifier)
}

/// An abstract client connection handler, allow server to send messages to a client
public protocol RPCServer: AnyObject {
    /// Send a notification to clients
    /// if nil clients, send it to all clients
    func send<Notification>(_ notification: Notification, to client: ClientType) where Notification: NotificationType
}

/// An abstract connection, allow messages to be sent to a (potentially remote) `MessageHandler`.
public protocol RPCClient: AnyObject {
    /// Send a notification without a reply.
    func send<Notification>(_ notification: Notification) where Notification: NotificationType
    
    /// Send a request and (asynchronously) receive a reply.
    func send<Request>(_ request: Request) -> EventLoopFuture<JSONRPCResult<Request.Response>> where Request: RequestType
}

/// An abstract message handler, such as a language server or client.
protocol MessageHandler: AnyObject {
    /// Handle a notification without a reply.
    func handle<Notification>(_: Notification, from: ObjectIdentifier) where Notification: NotificationType

    /// Handle a request and (asynchronously) receive a reply.
    /// EventLoopFuture<JSONRPCResult<Request.Response>>
    func handle<Request>(_: Request, id: RequestID, from: ObjectIdentifier, reply: @escaping (JSONRPCResult<Request.Response>) -> Void) where Request: RequestType
}
