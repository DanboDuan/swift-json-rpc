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

    func sendRequest(client: RPCClient) {
        let request = HelloRequest(name: "bob", data: ["age": 18])
        let response = client.send(request)
        response.cancel()
        if let result = try? response.get().success {
            let data = try! encoder.encode(result)
            print("HelloRequest success \(String(decoding: data, as: UTF8.self))")
        }
        if let result = try? response.get().failure {
            let data = try! encoder.encode(result)
            print("HelloRequest failure \(String(decoding: data, as: UTF8.self))")
        }
    }

    func sendUnknownRequest(client: RPCClient) {
        let request = UnknownRequest(name: "bob", data: ["age": 18])
        let result = try! client.send(request).get()
        let data = try! encoder.encode(result)
        print("UnknownRequest response \(String(decoding: data, as: UTF8.self))")
    }

    func sendNotification(client: RPCClient) {
        let notification = HiNotification(message: "hi every one")
        client.send(notification)
    }

    func run() throws {
        encoder.outputFormatting = .prettyPrinted.union(.sortedKeys).union(.withoutEscapingSlashes)
        let address: ConnectionAddress
        if let path = options.path {
            address = .unixDomainSocket(path: path)
        } else {
            address = .ip(host: "127.0.0.1", port: options.port)
        }

        let messageRegistry = MessageRegistry(
            requests: [HelloRequest.self, UnknownRequest.self],
            notifications: [HiNotification.self]
        )

        let config = Config(messageRegistry: messageRegistry)
        let client = JSONRPC.createClient(config: config)
        _ = try! client.connect(to: address).wait()
        sendRequest(client: client)
        sendNotification(client: client)
        sendUnknownRequest(client: client)
        try? client.closeFuture.wait()
        try? client.stop()
    }
}
