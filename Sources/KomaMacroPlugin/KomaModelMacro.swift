import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct KomaModelMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self),
              let recordType = KomaMacroParsing.metatypeLiteral(named: "record", in: node.description)
        else {
            return []
        }

        let assignments = Self.properties(from: structDecl)
            .map { "self.\($0) = record.\($0)" }
            .joined(separator: "\n        ")
        let relations = Self.relations(from: structDecl)
        let relationMembers = relations.flatMap { relation in
            [
                """
                public static let komaRelation\(relation.capitalizedName) = \(relation.kind.typeName)<\(recordType), \(relation
                    .relatedRecord), \(relation.relatedModel)>(
                    name: "\(relation.name)",
                    localColumn: "\(relation.localColumn)",
                    foreignColumn: "\(relation.foreignColumn)"
                )
                """,
                """
                public var \(relation.name): \(relation.kind.queryTypeName)<\(recordType), \(relation.relatedRecord), \(relation
                    .relatedModel)> {
                    self.relation(Self.komaRelation\(relation.capitalizedName))
                }
                """
            ]
        }

        var declarations: [DeclSyntax] = [
            """
            public typealias Record = \(raw: recordType)
            """,
            """
            public let komaRecord: \(raw: recordType)
            """,
            """
            public let komaGraphContext: KomaGraphContext
            """,
            """
            public init(record: \(raw: recordType), graphContext: KomaGraphContext) {
                self.komaRecord = record
                self.komaGraphContext = graphContext
                \(raw: assignments)
            }
            """
        ]
        declarations.append(contentsOf: relationMembers.map { DeclSyntax(stringLiteral: $0) })
        return declarations
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        try [
            ExtensionDeclSyntax("extension \(type.trimmed): KomaModel {}")
        ]
    }

    private static func properties(from structDecl: StructDeclSyntax) -> [String] {
        structDecl.memberBlock.members.compactMap { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.hasAttribute("KomaIgnore"),
                  let binding = variable.bindings.first,
                  binding.accessorBlock == nil,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
            else {
                return nil
            }
            let name = pattern.identifier.text
            return name.hasPrefix("_koma") ? nil : name
        }
    }

    private static func relations(from structDecl: StructDeclSyntax) -> [Relation] {
        structDecl.memberBlock.members.flatMap { member -> [Relation] in
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self) else {
                return []
            }
            return enumDecl.memberBlock.members.compactMap { member in
                guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self),
                      let element = caseDecl.elements.first,
                      let attribute = caseDecl.attributes.compactMap({ attribute -> AttributeSyntax? in
                          guard case let .attribute(attribute) = attribute,
                                RelationKind(attributeName: attribute.attributeName.source) != nil
                          else {
                              return nil
                          }
                          return attribute
                      }).first,
                      let relatedRecord = KomaMacroParsing.firstMetatypeLiteral(in: attribute.description),
                      let kind = RelationKind(attributeName: attribute.attributeName.source),
                      let relatedModel = KomaMacroParsing.metatypeLiteral(named: "model", in: attribute.description),
                      let localColumn = KomaMacroParsing.keyPathLeaf(named: "local", in: attribute.description),
                      let foreignColumn = KomaMacroParsing.keyPathLeaf(named: "foreign", in: attribute.description)
                else {
                    return nil
                }

                return Relation(
                    name: element.name.text,
                    relatedRecord: relatedRecord,
                    relatedModel: relatedModel,
                    localColumn: localColumn,
                    foreignColumn: foreignColumn,
                    kind: kind
                )
            }
        }
    }

    private struct Relation {
        let name: String
        let relatedRecord: String
        let relatedModel: String
        let localColumn: String
        let foreignColumn: String
        let kind: RelationKind

        var capitalizedName: String {
            name.prefix(1).uppercased() + name.dropFirst()
        }
    }

    private enum RelationKind {
        case toMany
        case toOne

        init?(attributeName: String) {
            switch attributeName {
            case "KomaHasMany":
                self = .toMany
            case "KomaHasOne", "KomaBelongsTo":
                self = .toOne
            default:
                return nil
            }
        }

        var typeName: String {
            switch self {
            case .toMany:
                return "KomaToManyRelation"
            case .toOne:
                return "KomaToOneRelation"
            }
        }

        var queryTypeName: String {
            switch self {
            case .toMany:
                return "KomaRelationQuery"
            case .toOne:
                return "KomaToOneRelationQuery"
            }
        }
    }
}
