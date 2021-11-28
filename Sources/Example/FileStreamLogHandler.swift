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

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif os(Windows)
import CRT
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("Unsupported runtime")
#endif
import Foundation
import Logging
import NIO
import NIOCore
import NIOPosix

// TODO: move to jsonrpc module
final class NIOLoggerWriter {
    static let shared = NIOLoggerWriter("/tmp/jsonrpc.log")
    private let futureFileHandle: EventLoopFuture<NIOFileHandle>
    private let eventLoopGroup: EventLoopGroup
    private let allocator = ByteBufferAllocator()
    private let fileIO: NonBlockingFileIO
    private var writeFuture: EventLoopFuture<Void>?

    public init(_ path: String) {
        let threadPool = NIOThreadPool(numberOfThreads: 1)
        self.fileIO = NonBlockingFileIO(threadPool: threadPool)
        threadPool.start()
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.futureFileHandle = self.fileIO.openFile(path: path,
                                                     mode: .write,
                                                     flags: .allowFileCreation(),
                                                     eventLoop: self.eventLoopGroup.next())
    }

    public func log(log: String) {
        #if DEBUG
        print(log, terminator: "")
        #endif
        let data = log.data(using: .utf8)!
        var buffer = self.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let fileIO = self.fileIO
        let eventLoopGroup = self.eventLoopGroup
        self.futureFileHandle.whenSuccess { handle in
            self.writeFuture = fileIO.write(fileHandle: handle,
                                            buffer: buffer,
                                            eventLoop: eventLoopGroup.next())
        }
    }

    private func close() {
        if let fileHandle = try? self.futureFileHandle.wait() {
            try? fileHandle.close()
        }
    }
}

public final class FileStreamLogHandler: LogHandler {
    private let label: String
    public var logLevel: Logger.Level = .info
    private var prettyMetadata: String?

    public var metadata = Logger.Metadata() {
        didSet {
            self.prettyMetadata = self.prettify(self.metadata)
        }
    }

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            return self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }

    public init(label: String) {
        self.label = label
    }

    public func log(level: Logger.Level,
                    message: Logger.Message,
                    metadata: Logger.Metadata?,
                    source: String,
                    file: String,
                    function: String,
                    line: UInt)
    {
        let prettyMetadata = metadata?.isEmpty ?? true
            ? self.prettyMetadata
            : self.prettify(self.metadata.merging(metadata!, uniquingKeysWith: { _, new in new }))

        let data = "\(self.timestamp()) \(level) \(self.label) :\(prettyMetadata.map { " \($0)" } ?? "") \(message)\n"
        NIOLoggerWriter.shared.log(log: data)
    }

    private func prettify(_ metadata: Logger.Metadata) -> String? {
        return !metadata.isEmpty
            ? metadata.lazy.sorted(by: { $0.key < $1.key }).map { "\($0)=\($1)" }.joined(separator: " ")
            : nil
    }

    private func timestamp() -> String {
        var buffer = [Int8](repeating: 0, count: 255)
        var timestamp = time(nil)
        let localTime = localtime(&timestamp)
        strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S%z", localTime)
        return buffer.withUnsafeBufferPointer {
            $0.withMemoryRebound(to: CChar.self) {
                String(cString: $0.baseAddress!)
            }
        }
    }
}
