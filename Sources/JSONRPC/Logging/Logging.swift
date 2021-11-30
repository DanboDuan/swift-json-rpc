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

import Logging

func log(
    _ message: @autoclosure () -> Logger.Message,
    level: LogLevel = .default,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
) {
    JSONRPCLogger.shared.log(message(), level: level, file: file, function: function, line: line)
}

final class JSONRPCLogger {
    public internal(set) static var shared: JSONRPCLogger = .init(logger: Logger(label: "com.jsonrpc.log"))

    private var logger: Logger
    public var enable = false

    internal subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            logger[metadataKey: metadataKey]
        }
        set {
            logger[metadataKey: metadataKey] = newValue
        }
    }

    internal init(logger: @autoclosure () -> Logger) {
        self.logger = logger()
    }

    public func log(
        _ message: @autoclosure () -> Logger.Message,
        level: Logger.Level,
        file: String,
        function: String,
        line: UInt
    ) {
        guard enable else { return }
        logger.log(
            level: level,
            message(),
            metadata: nil,
            source: "JSON-RPC",
            file: file,
            function: function,
            line: line
        )
    }
}
