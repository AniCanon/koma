import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct KomaResourceMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self),
              let basePath = stringLiteral(named: "basePath", in: node.description),
              let recordType = metatypeLiteral(named: "record", in: node.description)
        else {
            return []
        }

        let operations = Self.operations(from: enumDecl)
        let methods = operations.map { operation in
            Self.clientMethod(for: operation, basePath: basePath, recordType: recordType)
        }.joined(separator: "\n\n        ")

        return [
            """
            public struct Client: Sendable {
                private let koma: KomaClient

                public init(koma: KomaClient) {
                    self.koma = koma
                }

                \(raw: methods)
            }
            """,
            """
            public static func client(in koma: KomaClient) -> Client {
                Client(koma: koma)
            }
            """
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        try [
            ExtensionDeclSyntax("extension \(type.trimmed): KomaResourceNamespace {}")
        ]
    }

    private static func operations(from enumDecl: EnumDeclSyntax) -> [ResourceOperation] {
        enumDecl.memberBlock.members.compactMap { member in
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self),
                  let route = Self.route(from: caseDecl),
                  let element = caseDecl.elements.first
            else {
                return nil
            }

            return ResourceOperation(
                name: element.name.text,
                method: route.method,
                path: route.path,
                output: route.output,
                cache: Self.cache(from: caseDecl),
                adapter: Self.adapter(from: caseDecl),
                isRefreshable: Self.isRefreshable(caseDecl),
                parameters: Self.parameters(from: element)
            )
        }
    }

    private static func route(from caseDecl: EnumCaseDeclSyntax) -> (method: String, path: String, output: String)? {
        for attribute in caseDecl.attributes {
            guard case let .attribute(attribute) = attribute else {
                continue
            }
            if attribute.attributeName.source == "KomaRoute",
               let route = Self.routeFromKomaRoute(attribute.description)
            {
                return route
            }
        }

        for attribute in caseDecl.attributes {
            guard case let .attribute(attribute) = attribute else {
                continue
            }
            let name = attribute.attributeName.source
            guard ["KomaGET", "KomaPOST", "KomaPATCH", "KomaDELETE"].contains(name) else {
                continue
            }

            let method = name
                .replacingOccurrences(of: "Koma", with: "")
                .lowercased()
            return (
                method,
                Self.firstStringLiteral(in: attribute.description) ?? "",
                Self.outputType(in: attribute.description) ?? "Void"
            )
        }
        return nil
    }

    private static func cache(from caseDecl: EnumCaseDeclSyntax) -> String {
        for attribute in caseDecl.attributes {
            guard case let .attribute(attribute) = attribute,
                  attribute.attributeName.source == "KomaRoute",
                  let cache = routeArgument(named: "cache", in: attribute.description)
            else {
                continue
            }
            return cache
        }

        for attribute in caseDecl.attributes {
            guard case let .attribute(attribute) = attribute,
                  attribute.attributeName.source == "KomaCache"
            else {
                continue
            }

            let text = attribute.description
            let kindExpression = if text.contains(".collection") {
                "KomaCacheDescriptor.collection(\(Self.firstStringLiteral(in: text).map { "\"\($0)\"" } ?? "\"\""))"
            } else if text.contains(".entity") {
                "KomaCacheDescriptor.entity(\(Self.firstStringLiteral(in: text).map { "\"\($0)\"" } ?? "\"\""))"
            } else {
                "nil"
            }

            guard kindExpression != "nil" else {
                return "nil"
            }

            if let staleAfter = Self.argumentExpression(named: "staleAfter", in: text) {
                return "\(kindExpression).withStaleAfter(\(staleAfter))"
            }
            return kindExpression
        }
        return "nil"
    }

    private static func adapter(from caseDecl: EnumCaseDeclSyntax) -> String {
        for attribute in caseDecl.attributes {
            guard case let .attribute(attribute) = attribute,
                  attribute.attributeName.source == "KomaRoute",
                  let adapter = routeArgument(named: "adapter", in: attribute.description)
            else {
                continue
            }
            return adapter
        }

        for attribute in caseDecl.attributes {
            guard case let .attribute(attribute) = attribute,
                  attribute.attributeName.source == "KomaAdapter"
            else {
                continue
            }
            let adapter = Self.firstMetatypeLiteral(in: attribute.description) ?? "Never"
            return "\(adapter).self"
        }
        return "nil"
    }

    private static func isRefreshable(_ caseDecl: EnumCaseDeclSyntax) -> Bool {
        for attribute in caseDecl.attributes {
            guard case let .attribute(attribute) = attribute,
                  attribute.attributeName.source == "KomaRoute"
            else {
                continue
            }
            let refresh = Self.routeArgument(named: "refresh", in: attribute.description) ?? ".disabled"
            return refresh.contains(".allowed") || refresh.contains(".enabled") || refresh.contains(".refreshable")
        }

        return caseDecl.hasAttribute("KomaRefreshable")
    }
}
