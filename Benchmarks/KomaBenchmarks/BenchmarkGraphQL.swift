import Apollo
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

struct BenchmarkGraphQLSchema: SchemaMetadata {
    static let configuration: any SchemaConfiguration.Type = BenchmarkGraphQLSchemaConfiguration.self

    static func objectType(forTypename typename: String) -> Object? {
        Object(typename: typename, implementedInterfaces: [])
    }
}

enum BenchmarkGraphQLSchemaConfiguration: SchemaConfiguration {
    static func cacheKeyInfo(for type: Object, object: ObjectData) -> CacheKeyInfo? {
        nil
    }
}

struct BenchmarkProjectsQuery: GraphQLQuery {
    static let operationName = "BenchmarkProjects"
    static let operationDocument = OperationDocument(
        definition: OperationDefinition(
            """
            query BenchmarkProjects {
              projects {
                __typename
                id
                name
                slug
                deletedAt
                score
                updatedAt
                summary
              }
            }
            """
        )
    )

    typealias Data = BenchmarkProjectsData
}

struct BenchmarkProjectsData: RootSelectionSet {
    typealias Schema = BenchmarkGraphQLSchema

    static let __parentType: any ParentType = Object(typename: "Query", implementedInterfaces: [])
    static var __selections: [Selection] {
        [
            .field("projects", [Project].self)
        ]
    }

    static var __fulfilledFragments: [any SelectionSet.Type] {
        []
    }

    let __data: DataDict

    init(_dataDict: DataDict) {
        __data = _dataDict
    }

    var projects: [Project] {
        __data["projects"]
    }

    struct Project: RootSelectionSet {
        typealias Schema = BenchmarkGraphQLSchema

        static let __parentType: any ParentType = Object(typename: "Project", implementedInterfaces: [])
        static var __selections: [Selection] {
            [
                .field("__typename", String.self),
                .field("id", String.self),
                .field("name", String.self),
                .field("slug", String.self),
                .field("deletedAt", Double?.self),
                .field("score", Int.self),
                .field("updatedAt", Double.self),
                .field("summary", String.self)
            ]
        }

        static var __fulfilledFragments: [any SelectionSet.Type] {
            []
        }

        let __data: DataDict

        init(_dataDict: DataDict) {
            __data = _dataDict
        }
    }
}
