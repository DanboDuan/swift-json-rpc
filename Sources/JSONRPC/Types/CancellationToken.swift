//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

public final class CancellationToken {
    public var isCancelled = false

    private var cancellationHandlers: [String: () -> Void] = [:]

    public init() {}

    public func addCancellationHandler(_ handler: @escaping () -> Void) -> Disposable {
        if isCancelled {
            return Disposable()
        } else {
            let key = UUID().uuidString
            cancellationHandlers[key] = handler
            return Disposable { [weak self] in
                self?.cancellationHandlers[key] = nil
            }
        }
    }

    public func cancel() {
        if !isCancelled {
            isCancelled = true
            cancellationHandlers.forEach { _, handler in
                handler()
            }
            cancellationHandlers.removeAll()
        }
    }
}
