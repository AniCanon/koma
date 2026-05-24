import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct KomaEntityMacro: MemberMacro, ExtensionMacro {
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
            public static let komaGeneratedCreateTableSQL: String? = \(raw: createTableLiteral)
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

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return []
        }

        let properties = Self.properties(from: structDecl)
        guard !properties.isEmpty else {
            return []
        }

        var conformances = ["KomaGeneratedSchemaRecord"]
        if properties.allSatisfy(\.supportsSQLiteFastPath) {
            conformances.append("KomaSQLiteFastPathRecord")
        }
        if properties.allSatisfy(\.supportsJSON) {
            conformances.append("KomaJSONFastPathRecord")
        }

        return try [
            ExtensionDeclSyntax("extension \(type.trimmed): \(raw: conformances.joined(separator: ", ")) {}")
        ]
    }

    private static func tableName(from node: AttributeSyntax) -> String? {
        stringLiteral(named: "table", in: node.description)
    }

    private static func remoteType(from node: AttributeSyntax, in structDecl: StructDeclSyntax) -> String? {
        metatypeLiteral(named: "as", in: node.description) ?? declaredRemoteType(in: structDecl)
    }

    private static func declaredRemoteType(in structDecl: StructDeclSyntax) -> String? {
        for member in structDecl.memberBlock.members {
            if let typeAlias = member.decl.as(TypeAliasDeclSyntax.self),
               typeAlias.name.text == "Remote"
            {
                return typeAlias.initializer.value.source
            }
        }
        return nil
    }

    private static func hasDeclaredRemoteType(in structDecl: StructDeclSyntax) -> Bool {
        declaredRemoteType(in: structDecl) != nil
    }

    private static func hasRemoteInitializer(in structDecl: StructDeclSyntax) -> Bool {
        structDecl.memberBlock.members.contains { member in
            guard let initializer = member.decl.as(InitializerDeclSyntax.self),
                  let first = initializer.signature.parameterClause.parameters.first
            else {
                return false
            }
            return first.firstName.text == "remote"
        }
    }

    private static func hasRemoteValue(in structDecl: StructDeclSyntax) -> Bool {
        structDecl.memberBlock.members.contains { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  let binding = variable.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
            else {
                return false
            }
            return pattern.identifier.text == "remoteValue"
        }
    }
}
