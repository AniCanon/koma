import Foundation

extension KomaResourceMacro {
    static func routeFromKomaRoute(_ text: String) -> (method: String, path: String, output: String)? {
        guard let methodCall = routeMethodCall(in: text) else {
            return nil
        }
        return (
            methodCall.method,
            methodCall.path,
            Self.routeOutputType(in: methodCall.arguments) ?? "Void"
        )
    }

    private static func routeMethodCall(in text: String) -> (method: String, path: String, arguments: String)? {
        for method in ["get", "post", "patch", "put", "delete"] {
            guard let range = text.range(of: ".\(method)(") else {
                continue
            }
            let open = text.index(before: range.upperBound)
            guard let close = KomaMacroParsing.matchingCloseParen(in: text, open: open) else {
                continue
            }

            let arguments = String(text[text.index(after: open) ..< close])
            return (
                method,
                Self.routePath(in: arguments) ?? "",
                arguments
            )
        }
        return nil
    }

    private static func routePath(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "\"" else {
            return nil
        }
        return Self.firstStringLiteral(in: trimmed)
    }

    private static func routeOutputType(in text: String) -> String? {
        for label in ["as", "output", "response"] {
            guard let expression = KomaMacroParsing.argumentExpressionInCall(named: label, in: text),
                  let selfRange = expression.range(of: ".self")
            else {
                continue
            }
            return String(expression[..<selfRange.lowerBound])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t(),"))
        }
        return nil
    }
}
