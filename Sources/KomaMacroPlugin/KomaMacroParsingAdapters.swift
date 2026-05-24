import Foundation
import SwiftSyntax

extension VariableDeclSyntax {
    func hasAttribute(_ name: String) -> Bool {
        attributes.contains { element in
            guard case let .attribute(attribute) = element else {
                return false
            }
            return attribute.attributeName.source == name
        }
    }
}

extension EnumCaseDeclSyntax {
    func hasAttribute(_ name: String) -> Bool {
        attributes.contains { element in
            guard case let .attribute(attribute) = element else {
                return false
            }
            return attribute.attributeName.source == name
        }
    }
}

extension SyntaxProtocol {
    var source: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension KomaEntityMacro {
    static func stringLiteral(named name: String, in text: String) -> String? {
        KomaMacroParsing.stringLiteral(named: name, in: text)
    }

    static func metatypeLiteral(named name: String, in text: String) -> String? {
        KomaMacroParsing.metatypeLiteral(named: name, in: text)
    }
}

extension KomaResourceMacro {
    static func stringLiteral(named name: String, in text: String) -> String? {
        KomaMacroParsing.stringLiteral(named: name, in: text)
    }

    static func firstStringLiteral(in text: String) -> String? {
        KomaMacroParsing.firstStringLiteral(in: text)
    }

    static func metatypeLiteral(named name: String, in text: String) -> String? {
        KomaMacroParsing.metatypeLiteral(named: name, in: text)
    }

    static func firstMetatypeLiteral(in text: String) -> String? {
        KomaMacroParsing.firstMetatypeLiteral(in: text)
    }

    static func outputType(in text: String) -> String? {
        guard let expression = KomaMacroParsing.argumentExpression(named: "output", in: text) else {
            return nil
        }
        return expression.replacingOccurrences(of: ".self", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func argumentExpression(named name: String, in text: String) -> String? {
        KomaMacroParsing.argumentExpression(named: name, in: text)
    }

    static func routeArgument(named name: String, in text: String) -> String? {
        KomaMacroParsing.argumentExpressionInCall(named: name, in: text)
    }

    static func splitTopLevel(_ text: String) -> [String] {
        KomaMacroParsing.splitTopLevel(text)
    }
}
