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

extension Swift.Result: Codable
    where Success: Codable, Failure: Codable
{
    private enum CodingKeys: String, CodingKey {
        case success
        case failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let success = try? container.decode(Success.self, forKey: .success) {
            self = .success(success)
            return
        }

        if let failure = try? container.decode(Failure.self, forKey: .failure) {
            self = .failure(failure)
            return
        }

        let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "error value dump \(dump(container))")
        throw DecodingError.dataCorrupted(context)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .success(value):
            try value.encode(to: container.superEncoder(forKey: .success))
        case let .failure(value):
            try value.encode(to: container.superEncoder(forKey: .failure))
        }
    }

    /// Project out the .success value, or nil.
    public var success: Success? {
        switch self {
        case let .success(value):
            return value
        default:
            return nil
        }
    }

    /// Project out the .failure value, or nil.
    public var failure: Failure? {
        switch self {
        case let .failure(error):
            return error
        default:
            return nil
        }
    }
}
