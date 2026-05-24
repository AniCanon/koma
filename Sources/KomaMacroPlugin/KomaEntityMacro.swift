import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct KomaEntityMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return []
        }

        let tableName = Self.tableName(from: node) ?? Self.defaultTableName(from: structDecl.name.text)
        let properties = Self.properties(from: structDecl)
        guard !properties.isEmpty else {
            return []
        }

        let primaryKey = properties.first(where: \.isPrimaryKey)?.name ?? "id"
        let columnMembers = properties
            .map { "public let \($0.name) = KomaColumn<\($0.type)>(\"\($0.name)\")" }
            .joined(separator: "\n        ")
        let metadata = properties
            .map {
                "KomaColumnMetadata(name: \"\($0.name)\", storage: .\($0.storage), isPrimaryKey: \($0.name == primaryKey ? "true" : "false"))"
            }
            .joined(separator: ",\n        ")
        let createTableSQL = Self.createTableSQL(tableName: tableName, properties: properties, primaryKey: primaryKey)
        let createTableLiteral = String(reflecting: createTableSQL)

        var declarations: [DeclSyntax] = [
            """
            public struct Columns: Sendable {
                public init() {}
                \(raw: columnMembers)
            }
            """,
            """
            public static let columns = Columns()
            """,
            """
            public static let komaTableName = "\(raw: tableName)"
            """,
            """
            public static let komaPrimaryKey = "\(raw: primaryKey)"
            """,
            """
            public static let komaColumns: [KomaColumnMetadata] = [
                \(raw: metadata)
            ]
            """,
            """
            public static let _komaSQLiteCreateTableSQL: String? = \(raw: createTableLiteral)
            """
        ]

        if properties.allSatisfy(\.supportsSQLiteFastPath) {
            declarations.append(contentsOf: Self.sqliteFastPathMembers(for: properties))
        }

        if properties.allSatisfy(\.supportsJSON) {
            declarations.append(contentsOf: Self.jsonFastPathMembers(for: properties))
        }

        if let remoteType = Self.remoteType(from: node, in: structDecl) {
            declarations.append(
                contentsOf: Self.remoteMappingMembers(
                    remoteType: remoteType,
                    properties: properties,
                    hasDeclaredRemoteType: Self.hasDeclaredRemoteType(in: structDecl),
                    hasRemoteInitializer: Self.hasRemoteInitializer(in: structDecl),
                    hasRemoteValue: Self.hasRemoteValue(in: structDecl)
                )
            )
        }

        return declarations
    }

    private static func tableName(from node: AttributeSyntax) -> String? {
        stringLiteral(named: "table", in: node.description)
    }

    private static func remoteType(from node: AttributeSyntax, in structDecl: StructDeclSyntax) -> String? {
        metatypeLiteral(named: "as", in: node.description) ?? declaredRemoteType(in: structDecl)
    }

    private static func declaredRemoteType(in structDecl: StructDeclSyntax) -> String? {
        for member in structDecl.memberBlock.members {
            let source = member.decl.source
            guard let range = source.range(of: "typealias Remote"),
                  let equals = source[range.upperBound...].firstIndex(of: "=")
            else {
                continue
            }
            return String(source[source.index(after: equals)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t;"))
        }
        return nil
    }

    private static func hasDeclaredRemoteType(in structDecl: StructDeclSyntax) -> Bool {
        declaredRemoteType(in: structDecl) != nil
    }

    private static func hasRemoteInitializer(in structDecl: StructDeclSyntax) -> Bool {
        structDecl.memberBlock.members.contains { member in
            member.decl.source
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .contains("init(remote:")
        }
    }

    private static func hasRemoteValue(in structDecl: StructDeclSyntax) -> Bool {
        structDecl.memberBlock.members.contains { member in
            member.decl.source
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .contains("varremoteValue:")
        }
    }

    private static func defaultTableName(from typeName: String) -> String {
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

    private static func createTableSQL(tableName: String, properties: [EntityProperty], primaryKey: String) -> String {
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

    private static func properties(from structDecl: StructDeclSyntax) -> [EntityProperty] {
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

    private static func unwrappedType(_ type: String) -> String {
        let normalized = type.replacingOccurrences(of: " ", with: "")
        if normalized.hasSuffix("?") {
            return String(normalized.dropLast())
        }
        if normalized.hasPrefix("Optional<"), normalized.hasSuffix(">") {
            return String(normalized.dropFirst("Optional<".count).dropLast())
        }
        return normalized
    }

    private static func remoteMappingMembers(
        remoteType: String,
        properties: [EntityProperty],
        hasDeclaredRemoteType: Bool,
        hasRemoteInitializer: Bool,
        hasRemoteValue: Bool
    ) -> [DeclSyntax] {
        var declarations: [DeclSyntax] = []

        if !hasDeclaredRemoteType {
            declarations.append(
                """
                public typealias Remote = \(raw: remoteType)
                """
            )
        }

        if !hasRemoteInitializer {
            let assignments = properties
                .map { "self.\($0.name) = remote.\($0.name)" }
                .joined(separator: "\n        ")
            declarations.append(
                """
                public init(remote: Remote) {
                    \(raw: assignments)
                }
                """
            )
        }

        if !hasRemoteValue {
            let arguments = properties
                .map { "\($0.name): self.\($0.name)" }
                .joined(separator: ",\n            ")
            declarations.append(
                """
                public var remoteValue: Remote {
                    Remote(
                        \(raw: arguments)
                    )
                }
                """
            )
        }

        return declarations
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
