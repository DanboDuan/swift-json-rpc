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

final class HalfCloseOnTimeout: ChannelInboundHandler {
    public typealias InboundIn = Any

    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is IdleStateHandler.IdleStateEvent {
            // this will trigger ByteToMessageDecoder::decodeLast which is required to
            // recognize partial frames
            context.fireUserInboundEventTriggered(ChannelEvent.inputClosed)
        }
        context.fireUserInboundEventTriggered(event)
    }
}
