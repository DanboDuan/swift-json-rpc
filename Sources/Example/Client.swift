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
import Foundation
import JSONRPC
import NIO

final class Client: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "client",
        abstract: "JSON RPC Client"
    )

    @OptionGroup()
    var options: CommandOptions

    private enum CodingKeys: String, CodingKey {
        case options
    }

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    func sendRequest(client: JSONRPC) {
        let request = HelloRequest(name: "bob", data: ["age": 18])
        let result = try! client.send(request).wait()
        let data = try! encoder.encode(result)
        print("HelloRequest response \(String(decoding: data, as: UTF8.self))")
    }

    func sendNotification(client: JSONRPC) {
//        let notification = HiNotification(message: "hi every one")
//        client.send(notification)
    }

    func run() throws {
        encoder.outputFormatting = .prettyPrinted.union(.sortedKeys).union(.withoutEscapingSlashes)
        if options.port > 0 {
            let messageRegistry = MessageRegistry(requests: [HelloRequest.self],
                                                  notifications: [HiNotification.self])
            let address = ("127.0.0.1", options.port)
            let client = JSONRPC(messageRegistry: messageRegistry)
            _ = try! client.startClient(host: address.0, port: address.1).wait()
            sendRequest(client: client)
            sendNotification(client: client)
//            let group = DispatchGroup()
//            group.enter()
//            group.wait()
            client.stop()
        }
    }
}
