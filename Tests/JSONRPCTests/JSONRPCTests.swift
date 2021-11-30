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

import NIO
import XCTest

@testable import Example
@testable import JSONRPC
@testable import class JSONRPC.Notification

final class JSONRPCTests: XCTestCase {
    func testBadHost() throws {
        let port = Util.getFreePort()
        let address: ConnectionAddress = .ip(host: "127.0.0.1", port: Int(port))
        let messageRegistry = MessageRegistry(
            requests: [HelloRequest.self, UnknownRequest.self],
            notifications: [HiNotification.self]
        )
        let config = Config(messageRegistry: messageRegistry)
        let server = JSONRPC.createServer(config: config)
        XCTAssertNoThrow(try server.bind(to: address).wait())
        let server2 = JSONRPC.createServer(config: config)
        XCTAssertThrowsError(try server2.bind(to: address).wait())
        XCTAssertNoThrow(try server.stop())
    }

    func testHello() throws {
        let port = Util.getFreePort()
        let address: ConnectionAddress = .ip(host: "127.0.0.1", port: Int(port))
        let messageRegistry = MessageRegistry(
            requests: [HelloRequest.self],
            notifications: [HiNotification.self]
        )

        let config = Config(messageRegistry: messageRegistry)
        let server = JSONRPC.createServer(config: config)
        XCTAssertNoThrow(try server.bind(to: address).wait())

        server.register { (request: Request<HelloRequest>) in
            XCTAssertEqual(request.params.name, "bob")
            XCTAssertEqual(request.params.data, ["age": 18])
            request.reply(HelloResult(greet: "hello \(request.params.name)"))
        }

        server.register { (note: Notification<HiNotification>) in
            XCTAssertEqual(note.params.message, "hi bob")
            server.send(HiNotification(message: "hi every one"), to: .all)
        }

        let client = JSONRPC.createClient(config: config)
        XCTAssertNoThrow(try client.connect(to: address).wait())
        client.register { (note: Notification<HiNotification>) in
            XCTAssertEqual(note.params.message, "hi every one")
        }
        client.send(HiNotification(message: "hi bob"))
        let request = HelloRequest(name: "bob", data: ["age": 18])
        let response = client.send(request)
        let result = try? response.get().success
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.greet, "hello bob")

        let unknown = try? client.send(UnknownRequest(name: "Tom", data: "")).get()
        XCTAssertNotNil(unknown)
        XCTAssertNotNil(unknown!.failure)
        XCTAssertEqual(unknown!.failure!.code, .methodNotFound)

        XCTAssertNoThrow(try client.stop())
        XCTAssertNoThrow(try server.stop())
    }
}
