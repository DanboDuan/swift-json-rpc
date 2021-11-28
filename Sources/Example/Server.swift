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
import NIO

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

    private var server: JSONRPC?
    
    func hello(_ request: Request<HelloRequest>) {
        request.reply(HelloResult(greet: "hello \(request.params.name)"))
        if let server = server {
            server.send(HiNotification(message: "hi"), to: .all)
        }
    }

    func hi(_ notification: Notification<HiNotification>) {
//        if let server = server {
//            server.send(HiNotification(message: "hi"))
//        }
    }

    func run() throws {
        if self.options.port > 0 {
            let messageRegistry = MessageRegistry(requests: [HelloRequest.self, UnknownRequest.self],
                                                  notifications: [HiNotification.self])
            let address = ("127.0.0.1", options.port)
            let server = JSONRPC(messageRegistry: messageRegistry)

            server.register(self.hello)
            server.register(self.hi)
            self.server = server
            _ = try! server.startServer(host: address.0, port: address.1).wait()
            try? server.closeFuture.wait()
        }
    }
}
