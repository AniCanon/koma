import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct KomaRelationsMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self),
              let ownerRecord = KomaMacroParsing.firstMetatypeLiteral(in: node.description)
        else {
            return []
        }

        let relations = Self.relations(from: enumDecl, ownerRecord: ownerRecord)
        let members = relations.map { relation in
            """
            public static let include\(relation.capitalizedName) = \(relation.kind.typeName)<\(ownerRecord), \(relation
                .relatedRecord), \(relation
                .relatedModel)>(
                name: "\(relation.name)",
                localColumn: "\(relation.localColumn)",
                foreignColumn: "\(relation.foreignColumn)"
            )
            """
        }

        return members.map { DeclSyntax(stringLiteral: $0) }
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        try [
            ExtensionDeclSyntax("extension \(type.trimmed): KomaRelationNamespace {}")
        ]
    }

    private static func relations(from enumDecl: EnumDeclSyntax, ownerRecord: String) -> [Relation] {
        enumDecl.memberBlock.members.compactMap { member in
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
                ownerRecord: ownerRecord,
                relatedRecord: relatedRecord,
                relatedModel: relatedModel,
                localColumn: localColumn,
                foreignColumn: foreignColumn,
                kind: kind
            )
        }
    }

    private struct Relation {
        let name: String
        let ownerRecord: String
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
    }
}
