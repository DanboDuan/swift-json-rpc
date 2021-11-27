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
import NIOFoundationCompat

internal let maxPayload = 1_000_000 // 1MB

// bytes to codable and back
// <Response, Request>
final class CodableCodec<In, Out>: ChannelInboundHandler, ChannelOutboundHandler where In: Decodable, Out: Encodable {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = In
    public typealias OutboundIn = Out
    public typealias OutboundOut = ByteBuffer

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(messageRegistry: MessageRegistry? = nil,
                callbackRegistry: ResponseTypeCallback? = nil)
    {
        self.encoder.outputFormatting = .withoutEscapingSlashes
        self.decoder.userInfo[.messageRegistryKey] = messageRegistry
        self.decoder.userInfo[.responseTypeCallbackKey] = callbackRegistry
    }

    /// inbound
    /// ByteBuffer to JSONRPCMessage
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        guard buffer.readableBytes < maxPayload else {
            context.fireErrorCaught(CodecError.requestTooLarge)
            return
        }
        let data = buffer.readData(length: buffer.readableBytes)!
        do {
            log("--> \(String(decoding: data, as: UTF8.self))")
            let decodable = try self.decoder.decode(In.self, from: data)
            // call next handler
            context.fireChannelRead(wrapInboundOut(decodable))
        } catch let error as DecodingError {
            context.fireErrorCaught(CodecError.badJSON(error))
        } catch {
            context.fireErrorCaught(error)
        }
    }

    /// outbound
    /// JSONRPCMessage to ByteBuffer
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        do {
            let encodable = self.unwrapOutboundIn(data)
            let data = try encoder.encode(encodable)
            guard data.count < maxPayload else {
                promise?.fail(CodecError.requestTooLarge)
                return
            }
            log("<-- \(String(decoding: data, as: UTF8.self))")
            var buffer = context.channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            context.write(wrapOutboundOut(buffer), promise: promise)
        } catch let error as EncodingError {
            promise?.fail(CodecError.badJSON(error))
        } catch {
            promise?.fail(error)
        }
    }
}

public enum CodecError: Error {
    case badJSON(Error)
    case requestTooLarge
}
