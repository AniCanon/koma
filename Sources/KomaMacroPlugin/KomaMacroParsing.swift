import Foundation

enum KomaMacroParsing {
    static func stringLiteral(named name: String, in text: String) -> String? {
        guard let range = text.range(of: "\(name):") else {
            return nil
        }
        return firstStringLiteral(in: String(text[range.upperBound...]))
    }

    static func firstStringLiteral(in text: String) -> String? {
        guard let open = text.firstIndex(of: "\"") else {
            return nil
        }
        var index = text.index(after: open)
        var value = ""
        var isEscaped = false
        while index < text.endIndex {
            let character = text[index]
            if isEscaped {
                value.append(character)
                isEscaped = false
            } else if character == "\\" {
                value.append(character)
                isEscaped = true
            } else if character == "\"" {
                return value
            } else {
                value.append(character)
            }
            index = text.index(after: index)
        }
        return nil
    }

    static func metatypeLiteral(named name: String, in text: String) -> String? {
        guard let range = text.range(of: "\(name):") else {
            return nil
        }
        let suffix = String(text[range.upperBound...])
        guard let selfRange = suffix.range(of: ".self") else {
            return nil
        }
        return String(suffix[..<selfRange.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t(),"))
    }

    static func firstMetatypeLiteral(in text: String) -> String? {
        guard let selfRange = text.range(of: ".self") else {
            return nil
        }

        var index = selfRange.lowerBound
        while index > text.startIndex {
            let previous = text.index(before: index)
            let character = text[previous]
            if character == "(" || character == "," || character == " " || character == "\n" || character == "\t" {
                break
            }
            index = previous
        }

        return String(text[index ..< selfRange.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t(),"))
    }

    static func argumentExpression(named name: String, in text: String) -> String? {
        guard let range = text.range(of: "\(name):") else {
            return nil
        }
        let suffix = String(text[range.upperBound...])
        var expression = (splitTopLevel(suffix).first ?? suffix)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t,"))
        if expression.hasSuffix(")") {
            expression.removeLast()
        }
        return expression.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func argumentExpressionInCall(named name: String, in text: String) -> String? {
        let arguments = argumentsInOuterCall(text) ?? text
        for argument in splitTopLevel(arguments) {
            let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("\(name):") else {
                continue
            }
            return String(trimmed.dropFirst(name.count + 1))
                .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t,"))
        }
        return nil
    }

    static func argumentsInOuterCall(_ text: String) -> String? {
        guard let open = text.firstIndex(of: "("),
              let close = matchingCloseParen(in: text, open: open)
        else {
            return nil
        }
        return String(text[text.index(after: open) ..< close])
    }

    static func matchingCloseParen(in text: String, open: String.Index) -> String.Index? {
        var depth = 0
        var index = open
        var isInsideString = false
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]
            if isInsideString, isEscaped {
                isEscaped = false
            } else if isInsideString, character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                isInsideString.toggle()
            } else if !isInsideString {
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    static func keyPathLeaf(named name: String, in text: String) -> String? {
        guard let expression = argumentExpression(named: name, in: text) else {
            return nil
        }
        return expression
            .split(separator: ".")
            .last
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " \n\t,)")) }
    }

    static func splitTopLevel(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for character in text {
            if isInsideString {
                current.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            switch character {
            case "\"":
                isInsideString = true
                current.append(character)
            case "(", "[", "<":
                depth += 1
                current.append(character)
            case ")", "]", ">":
                depth -= 1
                current.append(character)
            case "," where depth == 0:
                result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            default:
                current.append(character)
            }
        }

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            result.append(tail)
        }
        return result
    }
}
