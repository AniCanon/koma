import Foundation
import SwiftSyntax

extension KomaEntityMacro {
    static func defaultTableName(from typeName: String) -> String {
        let trimmed = typeName.hasSuffix("Record") ? String(typeName.dropLast("Record".count)) : typeName
        return trimmed
            .unicodeScalars
            .reduce(into: "") { result, scalar in
                let character = Character(scalar)
                if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty {
                    result.append("_")
                }
                result.append(String(character).lowercased())
            }
    }

    static func createTableSQL(tableName: String, properties: [EntityProperty], primaryKey: String) -> String {
        let columns = properties.map { property in
            var column = "\(Self.quotedIdentifier(property.name)) \(Self.sqliteType(for: property.storage))"
            if property.name == primaryKey {
                column += " PRIMARY KEY NOT NULL"
            }
            return column
        }
        .joined(separator: ", ")
        return "CREATE TABLE IF NOT EXISTS \(Self.quotedIdentifier(tableName)) (\(columns))"
    }

    static func properties(from structDecl: StructDeclSyntax) -> [EntityProperty] {
        structDecl.memberBlock.members.compactMap { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.hasAttribute("KomaIgnore"),
                  let binding = variable.bindings.first,
                  binding.accessorBlock == nil,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let type = binding.typeAnnotation?.type.source
            else {
                return nil
            }

            return EntityProperty(
                name: pattern.identifier.text,
                type: type,
                storage: Self.storageKind(for: type),
                isPrimaryKey: variable.hasAttribute("KomaPrimaryKey")
            )
        }
    }

    static func unwrappedType(_ type: String) -> String {
        let normalized = type.replacingOccurrences(of: " ", with: "")
        if normalized.hasSuffix("?") {
            return String(normalized.dropLast())
        }
        if normalized.hasPrefix("Optional<"), normalized.hasSuffix(">") {
            return String(normalized.dropFirst("Optional<".count).dropLast())
        }
        return normalized
    }

    private static func sqliteType(for storage: String) -> String {
        switch storage {
        case "integer":
            return "INTEGER"
        case "real":
            return "REAL"
        case "blob":
            return "BLOB"
        default:
            return "TEXT"
        }
    }

    private static func quotedIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func storageKind(for type: String) -> String {
        let normalized = Self.unwrappedType(type)
            .replacingOccurrences(of: " ", with: "")
            .split(separator: ".")
            .last
            .map(String.init) ?? type

        if ["Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Bool"].contains(normalized) {
            return "integer"
        }
        if ["Float", "Double", "Date"].contains(normalized) {
            return "real"
        }
        if normalized == "Data" {
            return "blob"
        }
        return "text"
    }

    struct EntityProperty {
        let name: String
        let type: String
        let storage: String
        let isPrimaryKey: Bool

        var isOptional: Bool {
            let normalized = type.replacingOccurrences(of: " ", with: "")
            return normalized.hasSuffix("?") || (normalized.hasPrefix("Optional<") && normalized.hasSuffix(">"))
        }

        var unwrappedType: String {
            KomaEntityMacro.unwrappedType(type)
        }

        var baseType: String {
            unwrappedType
                .split(separator: ".")
                .last
                .map(String.init) ?? unwrappedType
        }

        var supportsSQLiteFastPath: Bool {
            ["String", "Bool", "Int", "Int8", "Int16", "Int32", "Int64", "Float", "Double", "Date", "Data"].contains(baseType)
        }

        var supportsJSON: Bool {
            ["String", "Bool", "Int", "Int8", "Int16", "Int32", "Int64", "Float", "Double", "Date"].contains(baseType)
        }
    }
}
