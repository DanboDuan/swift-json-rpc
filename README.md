# JSON-RPC

[JSON-RPC 2.0](https://www.jsonrpc.org/specification) client and server for Swift base on Swift NIO. You can use this to implement your LSP, BSP, DAP Server or client in Swift.

# Feauture

- ✅ base on Swift NIO for high-performance
- ✅ support Cancellation
- ✅ user-friendly API
- base on Codable

# TODO

- [ ] use `async` 
- [ ] use DI framework to inject handlers
- [ ] add unit test

## Usage

### define your requests and notifications

```swift
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
public struct HiNotification: NotificationType, Hashable {
    public static let method: String = "hi"

    /// The kind of log message.
    public var message: String

    public init(message: String) {
        self.message = message
    }
}
```

### create server or client

- Server 

```swift
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
/// add your code here
_ = try! server.bind(to: address).wait()
try? server.closeFuture.wait()
```

- client

```swift
let address: ConnectionAddress
if let path = options.path {
    address = .unixDomainSocket(path: path)
} else {
    address = .ip(host: "127.0.0.1", port: options.port)
}

let messageRegistry = MessageRegistry(requests: [HelloRequest.self, UnknownRequest.self],
                                        notifications: [HiNotification.self])

let config = Config(messageRegistry: messageRegistry)
let client = JSONRPC.createClient(config: config)
_ = try! client.connect(to: address).wait()
/// add your code
try? client.closeFuture.wait()
try? client.stop().wait()
```

### register handlers

```swift
/// with block
server.register { (request:Request<HelloRequest>) in
    request.reply(HelloResult(greet: "hello \(request.params.name)"))
}
/// or method
func hi(_ notification: Notification<HiNotification>) {
    if let server = server {
        server.send(HiNotification(message: "hi"), to: .all)
    }
}

server.register(self.hi)
```

### just send and get result

```swift
let request = HelloRequest(name: "bob", data: ["age": 18])
let response = try! client.send(request).get()
if let result = try? response.success {
    let data = try! encoder.encode(result)
    print("HelloRequest success \(String(decoding: data, as: UTF8.self))")
}
if let result = try? response.failure {
    let data = try! encoder.encode(result)
    print("HelloRequest failure \(String(decoding: data, as: UTF8.self))")
}
```

### Cancellation

- on the client side

```swift
let request = HelloRequest(name: "bob", data: ["age": 18])
let result = client.send(request)
/// if you want to cancel it
result.cancel()
```
- on the server side 

```swift
func hello(_ request: Request<HelloRequest>) {
    request.addCancellationHandler {
        /// if request cancelled, cancel the jobs
    }
    /// do some jobs and reply
    request.reply(HelloResult(greet: "hello \(request.params.name)"))
}

```
## Installation

```
dependencies: [
    .package(url: "https://github.com/DanboDuan/swift-json-rpc.git", .upToNextMajor(from: "1.0.0"))
]
```
## Recognition

- [apple/swift-nio-examples](https://github.com/apple/swift-nio-examples) for Swift NIO JSON RPC Example
- [apple/sourcekit-lsp](https://github.com/apple/sourcekit-lsp) for JSON RPC Codable Example

## License

[Apache License Version 2.0](https://github.com/DanboDuan/swift-json-rpc/blob/master/LICENSE)




**Enjoy it**