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
}
