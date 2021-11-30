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
import NIO

public enum ConnectionAddress {
    case ip(host: String, port: Int)
    case unixDomainSocket(path: String)
}

extension ConnectionAddress: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .ip(host, port):
            return "\(host):\(port)"
        case let .unixDomainSocket(path):
            return path
        }
    }
}

public struct Config {
    public let timeout: Int64
    public let maxPayload: Int
    public let log: Bool
    public let numberOfThreads: Int
    public let messageRegistry: MessageRegistry

    public init(messageRegistry: MessageRegistry,
                timeout: Int64 = 3600,
                maxPayload: Int = 1_000_000,
                log: Bool = true,
                numberOfThreads: Int = System.coreCount)
    {
        self.messageRegistry = messageRegistry
        self.timeout = timeout
        self.maxPayload = maxPayload
        self.log = log
        self.numberOfThreads = numberOfThreads
    }
}
