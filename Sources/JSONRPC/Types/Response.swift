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

import NIOCore

public final class Response<R: RequestType> {
    public typealias Response = R.Response
    private var requestID: RequestID
    private var result: EventLoopFuture<JSONRPCResult<Response>>
    private var client: RPCClient
    private var cancelled = false

    public init(requestID: RequestID, result: EventLoopFuture<JSONRPCResult<Response>>, client: RPCClient) {
        self.requestID = requestID
        self.result = result
        self.client = client
    }

    public func get() throws -> JSONRPCResult<Response> {
        return try result.wait()
    }

    public func cancel() {
        cancelled = true
        client.send(CancelRequestNotification(id: requestID))
    }
}
