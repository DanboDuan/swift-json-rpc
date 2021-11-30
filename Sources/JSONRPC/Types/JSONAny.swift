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

/// Representation of 'any' in the LSP, JSONRPC, DAP and etc, which is equivalent
/// to an arbitrary JSON value.
public enum JSONAny: Hashable {
    case null
    case int(Int)
    case bool(Bool)
    case double(Double)
    case string(String)
    case array([JSONAny])
    case dictionary([String: JSONAny])
}

extension JSONAny: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONAny].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONAny].self) {
            self = .dictionary(value)
        } else {
            let error = "JSONAny cannot be decoded: Unrecognized type."
            throw DecodingError.dataCorruptedError(in: container, debugDescription: error)
        }
    }
}

extension JSONAny: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .int(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .dictionary(value):
            try container.encode(value)
        }
    }
}

extension JSONAny: ResponseType {}

extension JSONAny: ExpressibleByNilLiteral {
    public init(nilLiteral _: ()) {
        self = .null
    }
}

extension JSONAny: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension JSONAny: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONAny: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension JSONAny: ExpressibleByStringLiteral {
    public init(extendedGraphemeClusterLiteral value: String) {
        self = .string(value)
    }

    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONAny: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONAny...) {
        self = .array(elements)
    }
}

extension JSONAny: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONAny)...) {
        let dict = [String: JSONAny](elements, uniquingKeysWith: { first, _ in first })
        self = .dictionary(dict)
    }
}

public protocol JSONAnyCodable {
    init?(fromJSONRPCDictionary dictionary: [String: JSONAny])
    func encodeToJSONAny() -> JSONAny
}

extension Optional: JSONAnyCodable where Wrapped: JSONAnyCodable {
    public init?(fromJSONAny value: JSONAny) {
        if case .null = value {
            self = .none
            return
        }
        guard case let .dictionary(dict) = value else {
            return nil
        }
        guard let wrapped = Wrapped(fromJSONRPCDictionary: dict) else {
            return nil
        }
        self = .some(wrapped)
    }

    public init?(fromJSONRPCDictionary _: [String: JSONAny]) {
        nil
    }

    public func encodeToJSONAny() -> JSONAny {
        guard let wrapped = self else { return .null }
        return wrapped.encodeToJSONAny()
    }
}

extension Array: JSONAnyCodable where Element: JSONAnyCodable {
    public init?(fromJSONRPCArray array: JSONAny) {
        guard case let .array(array) = array else {
            return nil
        }
        var result = [Element]()
        for case let .dictionary(editDict) in array {
            guard let element = Element(fromJSONRPCDictionary: editDict) else {
                return nil
            }
            result.append(element)
        }
        self = result
    }

    public init?(fromJSONRPCDictionary _: [String: JSONAny]) {
        nil
    }

    public func encodeToJSONAny() -> JSONAny {
        .array(map { $0.encodeToJSONAny() })
    }
}
