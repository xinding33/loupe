import Foundation

/// Any JSON, for keeping what a saved file holds that this build doesn't understand.
public enum JSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  /// Whole numbers, kept exact.
  case integer(Int64)
  case unsigned(UInt64)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  /// Any key, for containers whose keys aren't known ahead.
  struct Key: CodingKey, Hashable {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { nil }
  }

  public init(from decoder: Decoder) throws {
    if let values = try? decoder.container(keyedBy: Key.self) {
      var object: [String: JSONValue] = [:]
      for key in values.allKeys {
        object[key.stringValue] = try values.decode(JSONValue.self, forKey: key)
      }
      self = .object(object)
    } else if var values = try? decoder.unkeyedContainer() {
      var array: [JSONValue] = []
      while !values.isAtEnd { array.append(try values.decode(JSONValue.self)) }
      self = .array(array)
    } else {
      let value = try decoder.singleValueContainer()
      if value.decodeNil() {
        self = .null
      } else if let bool = try? value.decode(Bool.self) {
        self = .bool(bool)
      } else if let integer = try? value.decode(Int64.self) {
        self = .integer(integer)
      } else if let unsigned = try? value.decode(UInt64.self) {
        self = .unsigned(unsigned)
      } else if let number = try? value.decode(Double.self) {
        self = .number(number)
      } else {
        self = .string(try value.decode(String.self))
      }
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .object(let object):
      var values = encoder.container(keyedBy: Key.self)
      for (key, value) in object { try values.encode(value, forKey: Key(key)) }
    case .array(let array):
      var values = encoder.unkeyedContainer()
      for value in array { try values.encode(value) }
    case .null:
      var value = encoder.singleValueContainer()
      try value.encodeNil()
    case .bool(let bool):
      var value = encoder.singleValueContainer()
      try value.encode(bool)
    case .integer(let integer):
      var value = encoder.singleValueContainer()
      try value.encode(integer)
    case .unsigned(let unsigned):
      var value = encoder.singleValueContainer()
      try value.encode(unsigned)
    case .number(let number):
      var value = encoder.singleValueContainer()
      try value.encode(number)
    case .string(let string):
      var value = encoder.singleValueContainer()
      try value.encode(string)
    }
  }
}
