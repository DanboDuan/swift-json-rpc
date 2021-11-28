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
import NIOPosix

extension JSONRPC: RPCServer {
    public func send<Notification>(_ notification: Notification, to client: ClientType) where Notification: NotificationType {
        guard let handler = handler else {
            return
        }
        handler.send(notification, to: client)
    }

    /// Register the given request handler.
    public func register<R>(_ requestHandler: @escaping (Request<R>) -> Void) {
        self.requestHandlers[ObjectIdentifier(R.self)] = requestHandler
    }

    public func bind(to address: ConnectionAddress) -> EventLoopFuture<Void> {
        assert(self.state == .initializing)
        let handler = JSONRPCMessageHandler(self, type: .Server)
        let codec = CodableCodec<JSONRPCMessage, JSONRPCMessage>(messageRegistry: config.messageRegistry,
                                                                 maxPayload: self.config.maxPayload)
        let timeout = TimeAmount.seconds(config.timeout)
        self.handler = handler
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandlers([IdleStateHandler(readTimeout: timeout), HalfCloseOnTimeout()])
                    .flatMap {
                        let framingHandler = ContentLengthHeaderCodec()
                        return channel.pipeline.addHandlers([ByteToMessageHandler(framingHandler),
                                                             MessageToByteHandler(framingHandler)])
                    }.flatMap {
                        channel.pipeline.addHandlers([codec,
                                                      handler])
                    }
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

        self.state = .starting(address.description)
        let future: EventLoopFuture<Channel>
        switch address {
        case .ip(host: let host, port: let port):
            future = bootstrap.bind(host: host, port: port)
        case .unixDomainSocket(path: let path):
            future = bootstrap.bind(unixDomainSocketPath: path, cleanupExistingSocketFile: true)
        }
        return future.flatMap { channel in
            self.channel = channel
            self.state = .started
            return channel.eventLoop.makeSucceededVoidFuture()
        }
    }
}
