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
import Logging

/// for test
public enum Util {
    public static func getFreePort() -> Int {
        let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        if socketFileDescriptor == -1 {
            return 0
        }

        var address = sockaddr_in()
        let sizeOfSockkAddr = MemoryLayout<sockaddr_in>.size
        var len = socklen_t(sizeOfSockkAddr)
        address.sin_len = __uint8_t(sizeOfSockkAddr)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0 // Int(OSHostByteOrder()) == OSLittleEndian ? _OSSwapInt16(port) : port
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        address.sin_zero = (0, 0, 0, 0, 0, 0, 0, 0)
        var bind_addr = sockaddr()
        memcpy(&bind_addr, &address, Int(sizeOfSockkAddr))

        if Darwin.bind(socketFileDescriptor, &bind_addr, len) == -1 {
            release(socket: socketFileDescriptor)
            return 0
        }
        if listen(socketFileDescriptor, SOMAXCONN) == -1 {
            release(socket: socketFileDescriptor)
            return 0
        }
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(socketFileDescriptor, $0, &len)
            }
        }
        var port: uint16 = 0
        if result == 0 {
            port = address.sin_port
        }
        release(socket: socketFileDescriptor)
        return Int(port)
    }

    private static func release(socket: Int32) {
        Darwin.shutdown(socket, SHUT_RDWR)
        close(socket)
    }

    static func setupLog() {
        LoggingSystem.bootstrap { label in
            FileStreamLogHandler(label: label)
        }
    }
}
