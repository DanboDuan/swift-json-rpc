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

import Foundation

public protocol MessageType: Codable {}

public protocol ResponseType: MessageType {}

public protocol _RequestType: MessageType {
    /// The name of the request.
    static var method: String { get }

    func _handle(
        _ handler: MessageHandler,
        id: RequestID,
        from: ObjectIdentifier,
        reply: @escaping (JSONRPCResult<ResponseType>, RequestID) -> Void
    )
    
}

/// A request, which must have a unique `method` name as well as an associated response type.
public protocol RequestType: _RequestType {
    /// The type of of the response to this request.
    associatedtype Response: ResponseType
    
    func _cancelledResponse() -> JSONRPCResult<Response>?
}

/// A notification, which must have a unique `method` name.
public protocol NotificationType: MessageType {
    /// The name of the request.
    static var method: String { get }
}

public extension RequestType {
    func _handle(
        _ handler: MessageHandler,
        id: RequestID,
        from: ObjectIdentifier,
        reply: @escaping (JSONRPCResult<ResponseType>, RequestID) -> Void
    ) {
        handler.handle(self, id: id, from: from) { response in
            reply(response.map { $0 as ResponseType }, id)
        }
    }
    
    func _cancelledResponse() -> JSONRPCResult<Response>? {
        return nil
    }
}

public extension NotificationType {
    func _handle(_ handler: MessageHandler, from: ObjectIdentifier) {
        handler.handle(self, from: from)
    }
}
