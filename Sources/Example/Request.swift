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

import JSONRPC

public struct HelloRequest: RequestType, Hashable {
    public static let method: String = "hello"
    public typealias Response = HelloResult
    public var name: String
    public var data: JSONAny?

    public init(name: String, data: JSONAny?) {
        self.name = name
        self.data = data
    }
}

public struct HelloResult: ResponseType, Hashable {
    public var greet: String

    public init(greet: String) {
        self.greet = greet
    }
}

public struct UnknownRequest: RequestType, Hashable {
    public static let method: String = "unknown"
    public typealias Response = HelloResult
    public var name: String
    public var data: JSONAny?

    public init(name: String, data: JSONAny?) {
        self.name = name
        self.data = data
    }
}
