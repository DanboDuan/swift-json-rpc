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
import NIOCore

extension JSONRPC: RPCClient {
    @discardableResult
    public func send<Request>(_ request: Request) -> EventLoopFuture<JSONRPCResult<Request.Response>> where Request: RequestType {
        guard let channel = self.channel else {
            return self.group.next().makeFailedFuture(ConnectionError.notReady)
        }

        let id = RequestID.string(UUID().uuidString)
        let promise: EventLoopPromise<JSONRPCMessage> = channel.eventLoop.makePromise()
        let future = channel.eventLoop.submit {
            let wrapper = JSONRPCMessageWrapper(message: .request(request, id: id), promise: promise)
            let wait = channel.writeAndFlush(wrapper)
            wait.cascadeFailure(to: promise)
        }

        return future.flatMap {
            promise.futureResult
        }.map { anyResult in
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

    public func send<Notification>(_ notification: Notification) where Notification: NotificationType {
        guard let channel = self.channel else {
            return
        }

        channel.eventLoop.execute {
            let wrapper = JSONRPCMessageWrapper(message: .notification(notification), promise: nil)
            _ = channel.writeAndFlush(wrapper)
        }
    }
}
