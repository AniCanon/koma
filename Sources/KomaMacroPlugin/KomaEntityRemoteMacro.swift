import SwiftSyntax

extension KomaEntityMacro {
    static func remoteMappingMembers(
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
}
