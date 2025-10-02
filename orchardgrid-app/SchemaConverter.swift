import Foundation
import FoundationModels

// MARK: - JSON Schema Models

struct JSONSchemaDefinition: Codable, Sendable {
  let name: String
  let strict: Bool?
  let schema: JSONSchemaProperty
}

struct JSONSchemaProperty: Codable, Sendable {
  let type: String?
  let properties: [String: AnyCodable]?
  let required: [String]?
  let items: AnyCodable?
  let `enum`: [String]?
  let minimum: Double?
  let maximum: Double?
  let minItems: Int?
  let maxItems: Int?
  let additionalProperties: Bool?

  enum CodingKeys: String, CodingKey {
    case type, properties, required, items, `enum`, minimum, maximum
    case minItems
    case maxItems
    case additionalProperties
  }
}

// Helper to handle Any in Codable
struct AnyCodable: Codable, Sendable {
  let value: Any

  init(_ value: Any) {
    self.value = value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if let dict = try? container.decode([String: AnyCodable].self) {
      value = dict.mapValues { $0.value }
    } else if let array = try? container.decode([AnyCodable].self) {
      value = array.map(\.value)
    } else if let string = try? container.decode(String.self) {
      value = string
    } else if let int = try? container.decode(Int.self) {
      value = int
    } else if let double = try? container.decode(Double.self) {
      value = double
    } else if let bool = try? container.decode(Bool.self) {
      value = bool
    } else {
      value = NSNull()
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch value {
    case let dict as [String: Any]:
      try container.encode(dict.mapValues { AnyCodable($0) })
    case let array as [Any]:
      try container.encode(array.map { AnyCodable($0) })
    case let string as String:
      try container.encode(string)
    case let int as Int:
      try container.encode(int)
    case let double as Double:
      try container.encode(double)
    case let bool as Bool:
      try container.encode(bool)
    default:
      try container.encodeNil()
    }
  }

  func toJSONSchemaProperty() -> JSONSchemaProperty? {
    guard let dict = value as? [String: Any] else { return nil }

    let type = dict["type"] as? String
    let properties = (dict["properties"] as? [String: Any])?.mapValues { AnyCodable($0) }
    let required = dict["required"] as? [String]
    let items = (dict["items"] as? [String: Any]).map { AnyCodable($0) }
    let enumValues = dict["enum"] as? [String]
    let minimum = dict["minimum"] as? Double
    let maximum = dict["maximum"] as? Double
    let minItems = dict["minItems"] as? Int
    let maxItems = dict["maxItems"] as? Int
    let additionalProperties = dict["additionalProperties"] as? Bool

    return JSONSchemaProperty(
      type: type,
      properties: properties,
      required: required,
      items: items,
      enum: enumValues,
      minimum: minimum,
      maximum: maximum,
      minItems: minItems,
      maxItems: maxItems,
      additionalProperties: additionalProperties
    )
  }
}

// MARK: - Schema Converter

@MainActor
final class SchemaConverter {
  enum ConversionError: Error, CustomStringConvertible {
    case unsupportedType(String)
    case missingProperties
    case invalidSchema(String)

    var description: String {
      switch self {
      case let .unsupportedType(type):
        "Unsupported type: \(type)"
      case .missingProperties:
        "Missing properties in object schema"
      case let .invalidSchema(reason):
        "Invalid schema: \(reason)"
      }
    }
  }

  private var dependencies: [DynamicGenerationSchema] = []
  private var schemaCounter = 0

  func convert(_ jsonSchema: JSONSchemaDefinition) throws -> GenerationSchema {
    dependencies.removeAll()
    schemaCounter = 0

    guard jsonSchema.schema.type == "object" else {
      throw ConversionError.invalidSchema("Root schema must be object type")
    }

    guard let properties = jsonSchema.schema.properties else {
      throw ConversionError.missingProperties
    }

    let required = Set(jsonSchema.schema.required ?? [])
    var dynamicProperties: [DynamicGenerationSchema.Property] = []

    for (propName, propDef) in properties {
      guard let propProperty = propDef.toJSONSchemaProperty() else {
        throw ConversionError.invalidSchema("Invalid property definition for \(propName)")
      }

      let propSchema = try convertProperty(
        name: "\(jsonSchema.name)_\(propName)",
        property: propProperty
      )

      dynamicProperties.append(
        DynamicGenerationSchema.Property(
          name: propName,
          schema: propSchema,
          isOptional: !required.contains(propName)
        )
      )
    }

    let rootSchema = DynamicGenerationSchema(
      name: jsonSchema.name,
      properties: dynamicProperties
    )

    return try GenerationSchema(root: rootSchema, dependencies: dependencies)
  }

  private func convertProperty(name: String,
                               property: JSONSchemaProperty) throws -> DynamicGenerationSchema
  {
    guard let type = property.type else {
      throw ConversionError.invalidSchema("Property must have type")
    }

    switch type {
    case "string":
      if let enumValues = property.enum {
        let enumSchema = DynamicGenerationSchema(name: name, anyOf: enumValues)
        dependencies.append(enumSchema)
        return DynamicGenerationSchema(referenceTo: name)
      }
      return DynamicGenerationSchema(type: String.self)

    case "integer":
      return DynamicGenerationSchema(type: Int.self)

    case "number":
      return DynamicGenerationSchema(type: Double.self)

    case "boolean":
      return DynamicGenerationSchema(type: Bool.self)

    case "array":
      guard let items = property.items,
            let itemProperty = items.toJSONSchemaProperty()
      else {
        throw ConversionError.invalidSchema("Array must have items")
      }
      let itemSchema = try convertProperty(name: "\(name)_item", property: itemProperty)
      return DynamicGenerationSchema(
        arrayOf: itemSchema,
        minimumElements: property.minItems,
        maximumElements: property.maxItems
      )

    case "object":
      guard let properties = property.properties else {
        throw ConversionError.missingProperties
      }

      let required = Set(property.required ?? [])
      var dynamicProperties: [DynamicGenerationSchema.Property] = []

      for (propName, propDef) in properties {
        guard let propProperty = propDef.toJSONSchemaProperty() else {
          throw ConversionError.invalidSchema("Invalid property definition for \(propName)")
        }

        let propSchema = try convertProperty(
          name: "\(name)_\(propName)",
          property: propProperty
        )

        dynamicProperties.append(
          DynamicGenerationSchema.Property(
            name: propName,
            schema: propSchema,
            isOptional: !required.contains(propName)
          )
        )
      }

      let nestedSchema = DynamicGenerationSchema(
        name: name,
        properties: dynamicProperties
      )
      dependencies.append(nestedSchema)
      return DynamicGenerationSchema(referenceTo: name)

    default:
      throw ConversionError.unsupportedType(type)
    }
  }
}
