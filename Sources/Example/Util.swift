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
    static func isPortFree(_ port: UInt16) -> Bool {
        let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        if socketFileDescriptor == -1 {
            return false
        }

        var address = sockaddr_in()
        let sizeOfSockkAddr = MemoryLayout<sockaddr_in>.size
        address.sin_len = __uint8_t(sizeOfSockkAddr)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = Int(OSHostByteOrder()) == OSLittleEndian ? _OSSwapInt16(port) : port
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        address.sin_zero = (0, 0, 0, 0, 0, 0, 0, 0)
        var bind_addr = sockaddr()
        memcpy(&bind_addr, &address, Int(sizeOfSockkAddr))

        if Darwin.bind(socketFileDescriptor, &bind_addr, socklen_t(sizeOfSockkAddr)) == -1 {
            release(socket: socketFileDescriptor)
            return false
        }
        if listen(socketFileDescriptor, SOMAXCONN) == -1 {
            release(socket: socketFileDescriptor)
            return false
        }
        release(socket: socketFileDescriptor)
        return true
    }

    private static func release(socket: Int32) {
        Darwin.shutdown(socket, SHUT_RDWR)
        close(socket)
    }

    static func getFreePort() -> UInt16 {
        var portNum: UInt16 = 0
        for i in 50000 ..< 65000 {
            let isFree = isPortFree(UInt16(i))
            if isFree {
                portNum = in_port_t(i)
                return portNum
            }
        }

        return 0
    }

    static func setupLog() {
        LoggingSystem.bootstrap { label in
            FileStreamLogHandler(label: label)
        }
    }
}
