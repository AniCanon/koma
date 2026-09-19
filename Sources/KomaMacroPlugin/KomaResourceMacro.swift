import Foundation
import SwiftDiagnostics
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
              let basePath = stringLiteral(named: "basePath", in: node.description)
        else {
            return []
        }

        let recordType = metatypeLiteral(named: "record", in: node.description)
        let operations = Self.operations(from: enumDecl)

        if recordType == nil, let stored = operations.first(where: { !$0.isReturning }) {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: KomaResourceDiagnostic.missingRecord(routeName: stored.name)
                )
            )
            return []
        }

        let methods = operations.map { operation in
            operation.isReturning
                ? Self.returningClientMethod(for: operation, basePath: basePath)
                : Self.clientMethod(for: operation, basePath: basePath, recordType: recordType ?? "Never")
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
                isReturning: route.isReturning,
                cache: Self.cache(from: caseDecl),
                adapter: Self.adapter(from: caseDecl),
                isRefreshable: Self.isRefreshable(caseDecl),
                headers: Self.headers(from: caseDecl),
                parameters: Self.parameters(from: element)
            )
        }
    }

    private static func route(
        from caseDecl: EnumCaseDeclSyntax
    ) -> (method: String, path: String, output: String, isReturning: Bool)? {
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
                Self.outputType(in: attribute.description) ?? "Void",
                false
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

    private static func headers(from caseDecl: EnumCaseDeclSyntax) -> String? {
        for attribute in caseDecl.attributes {
            guard case let .attribute(attribute) = attribute,
                  attribute.attributeName.source == "KomaRoute",
                  let headers = routeArgument(named: "headers", in: attribute.description)
            else {
                continue
            }
            return headers
        }
        return nil
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

enum KomaResourceDiagnostic: DiagnosticMessage {
    case missingRecord(routeName: String)

    var message: String {
        switch self {
        case let .missingRecord(routeName):
            return """
            @KomaResource needs `record:` because route `\(routeName)` stores its response. \
            Declare the record type, or give the route a `returning:` response, which is \
            handed back to the caller instead of being stored.
            """
        }
    }

    var diagnosticID: MessageID {
        switch self {
        case .missingRecord:
            return MessageID(domain: "Koma", id: "KomaResource.missingRecord")
        }
    }

    var severity: DiagnosticSeverity {
        .error
    }
}
