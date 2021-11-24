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

/// A request object, wrapping the parameters of a `RequestType` and tracking its state.
public final class Request<R: RequestType> {
    public typealias Params = R

    public typealias Response = R.Response

    /// The request id from the client.
    public let id: RequestID

    /// The client of the request.
    public let clientID: ObjectIdentifier

    /// The request parameters.
    public let params: Params

    private var replyBlock: (JSONRPCResult<Response>) -> Void

    /// Whether a reply has been made. Every request must reply exactly once.
    private var replied: Bool = false {
        willSet {
            precondition(replied == false, "replied to \(id) more than once")
        }
    }

    /// The request's cancellation state.
    public let cancellationToken: CancellationToken

    public init(_ request: Params, id: RequestID, clientID: ObjectIdentifier, cancellation: CancellationToken, reply: @escaping (JSONRPCResult<Response>) -> Void) {
        self.id = id
        self.clientID = clientID
        self.params = request
        self.cancellationToken = cancellation
        self.replyBlock = reply
        _ = cancellation.addCancellationHandler { [weak self] in
            if let cancelled = request._cancelledResponse() {
                self?.reply(cancelled)
            } else {
                self?.reply(.failure(ResponseError.cancelled))
            }
        }
    }

    deinit {
        precondition(replied, "request \(id) never received a reply")
    }

    /// Reply to the request with `result`.
    ///
    /// This must be called exactly once for each request.
    public func reply(_ result: JSONRPCResult<Response>) {
        guard !isCancelled else {
            return
        }
        replied = true
        replyBlock(result)
    }

    /// Reply to the request with `.success(result)`.
    public func reply(_ result: Response) {
        reply(.success(result))
    }

    /// Whether the result has been cancelled.
    public var isCancelled: Bool { return cancellationToken.isCancelled }
}

extension Request: CustomStringConvertible {
    public var description: String {
        return """
        Request<\(R.method)>(
          id: \(id),
          clientID: \(clientID),
          params: \(params)
        )
        """
    }
}
