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

/// A request object, wrapping the parameters of a `NotificationType`.
public final class Notification<N: NotificationType> {
    public typealias Params = N

    /// The client of the request.
    public let clientID: ObjectIdentifier

    /// The request parameters.
    public let params: Params

    public init(_ notification: Params, clientID: ObjectIdentifier) {
        self.clientID = clientID
        self.params = notification
    }
}

extension Notification: CustomStringConvertible {
    public var description: String {
        return """
        Notification<\(N.method)>(
          clientID: \(String(describing: clientID)),
          params: \(params)
        )
        """
    }
}
