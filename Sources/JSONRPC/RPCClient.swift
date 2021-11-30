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
import NIOPosix

extension JSONRPC: RPCClient {
    public func send<Request>(_ request: Request) -> Response<Request> where Request: RequestType {
        let id = RequestID.string(UUID().uuidString)

        guard let channel = channel else {
            let error = ResponseError(code: .invalidRequest, message: "client not started")
            let result: EventLoopFuture<JSONRPCResult<Request.Response>> = group.next().makeSucceededFuture(.failure(error))
            return Response<Request>(requestID: id, result: result, client: self)
        }

        let promise: EventLoopPromise<JSONRPCMessage> = channel.eventLoop.makePromise()
        let future = channel.eventLoop.submit {
            let wrapper = JSONRPCMessageWrapper(message: .request(request, id: id), promise: promise)
            let wait = channel.writeAndFlush(wrapper)
            wait.cascadeFailure(to: promise)
        }

        let result: EventLoopFuture<JSONRPCResult<Request.Response>> = future.flatMap {
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

        return Response<Request>(requestID: id, result: result, client: self)
    }

    public func send<Notification>(_ notification: Notification) where Notification: NotificationType {
        guard let channel = channel else {
            return
        }

        channel.eventLoop.execute {
            let wrapper = JSONRPCMessageWrapper(message: .notification(notification), promise: nil)
            _ = channel.writeAndFlush(wrapper)
        }
    }

    public func connect(to address: ConnectionAddress) -> EventLoopFuture<Void> {
        assert(state == .initializing)

        let handler = JSONRPCMessageHandler(self, type: .Client)
        let codec = CodableCodec<JSONRPCMessage, JSONRPCMessage>(messageRegistry: config.messageRegistry,
                                                                 maxPayload: config.maxPayload,
                                                                 callbackRegistry: handler)
        let timeout = TimeAmount.seconds(config.timeout)
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([IdleStateHandler(readTimeout: timeout), HalfCloseOnTimeout()])
                    .flatMap {
                        let framingHandler = ContentLengthHeaderCodec()
                        return channel.pipeline.addHandlers([ByteToMessageHandler(framingHandler),
                                                             MessageToByteHandler(framingHandler)])
                    }.flatMap {
                        channel.pipeline.addHandlers([
                            codec,
                            handler,
                        ])
                    }
            }

        state = .starting(address.description)
        let future: EventLoopFuture<Channel>
        switch address {
        case let .ip(host: host, port: port):
            future = bootstrap.connect(host: host, port: port)
        case let .unixDomainSocket(path: path):
            future = bootstrap.connect(unixDomainSocketPath: path)
        }

        future.whenFailure { _ in
            self.state = .stopped
        }

        return future.flatMap { channel in
            self.channel = channel
            ///
            self.state = .started
            return channel.eventLoop.makeSucceededVoidFuture()
        }
    }
}
