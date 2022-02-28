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

final class Main: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "JSONRPC",
        abstract: "JSON RPC Client & Server",
        version: "1.0.0",
        subcommands: [
            Client.self,
            Server.self,
        ]
    )

    @OptionGroup()
    var options: CommandOptions

    func run() throws {}
}

Main.main()
