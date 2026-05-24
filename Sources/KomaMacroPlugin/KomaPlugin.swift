import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct KomaPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        KomaEntityMacro.self,
        KomaModelMacro.self,
        KomaNoopMacro.self,
        KomaRelationsMacro.self,
        KomaResourceMacro.self
    ]
}
