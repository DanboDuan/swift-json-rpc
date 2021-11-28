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

import ArgumentParser
import Dispatch
import JSONRPC

final class Server: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "server",
        abstract: "JSON RPC server"
    )

    @OptionGroup()
    var options: CommandOptions

    private enum CodingKeys: String, CodingKey {
        case options
    }

    private var server: RPCServer?

    func hello(_ request: Request<HelloRequest>) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(60)) {
            /// fake time cost jobs
            request.reply(HelloResult(greet: "hello \(request.params.name)"))
        }

        request.addCancellationHandler {
            /// if request cancelled
        }
        if let server = server {
            server.send(HiNotification(message: "hi"), to: .all)
        }
    }

    func hi(_ notification: Notification<HiNotification>) {
        if let server = server {
            server.send(HiNotification(message: "hi"), to: .all)
        }
    }

    func run() throws {
        let address: ConnectionAddress
        if let path = options.path {
            address = .unixDomainSocket(path: path)
        } else {
            address = .ip(host: "127.0.0.1", port: self.options.port)
        }
        let messageRegistry = MessageRegistry(requests: [HelloRequest.self, UnknownRequest.self],
                                              notifications: [HiNotification.self])
        let config = Config(messageRegistry: messageRegistry)
        let server = JSONRPC.createServer(config: config)

        server.register(self.hi)
        server.register { (request: Request<HelloRequest>) in
            request.reply(HelloResult(greet: "hello \(request.params.name)"))
        }
        self.server = server
        _ = try! server.bind(to: address).wait()
        try? server.closeFuture.wait()
    }
}
