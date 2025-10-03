import Foundation
import FoundationModels

// MARK: - JSON Schema Models
//
// All shared types are now defined in SharedTypes.swift
// This ensures proper type resolution by SourceKit and Swift compiler

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
