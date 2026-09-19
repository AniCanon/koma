import Foundation
import Koma
import Testing

private struct PageParams: Codable {
    var page: Int
    var active: Bool
    var ratio: Double
}

struct KomaQueryEncoderTests {
    @Test(arguments: [0, 1, 42, -1])
    func `an integer stays an integer rather than encoding as a boolean`(page: Int) {
        let items = KomaQueryEncoder.queryItems(
            from: PageParams(page: page, active: true, ratio: 1.5)
        )

        #expect(Self.value(named: "page", in: items) == String(page))
    }

    @Test(arguments: [true, false])
    func `a boolean encodes as true or false`(active: Bool) {
        let items = KomaQueryEncoder.queryItems(
            from: PageParams(page: 1, active: active, ratio: 1.5)
        )

        #expect(Self.value(named: "active", in: items) == (active ? "true" : "false"))
    }

    @Test
    func `a double keeps its fractional part`() {
        let items = KomaQueryEncoder.queryItems(
            from: PageParams(page: 0, active: false, ratio: 1.5)
        )

        #expect(Self.value(named: "ratio", in: items) == "1.5")
    }

    @Test
    func `integers and booleans coexist in one parameter struct`() {
        let items = KomaQueryEncoder.queryItems(
            from: PageParams(page: 1, active: false, ratio: 1.5)
        )

        #expect(Self.value(named: "page", in: items) == "1")
        #expect(Self.value(named: "active", in: items) == "false")
    }

    @Test
    func `a standalone integer query item stays an integer`() {
        #expect(KomaQueryEncoder.queryItem(name: "page", value: 0)?.value == "0")
        #expect(KomaQueryEncoder.queryItem(name: "page", value: 1)?.value == "1")
        #expect(KomaQueryEncoder.queryItem(name: "page", value: 42)?.value == "42")
        #expect(KomaQueryEncoder.queryItem(name: "page", value: -1)?.value == "-1")
    }

    @Test
    func `a standalone boolean query item encodes as true or false`() {
        #expect(KomaQueryEncoder.queryItem(name: "active", value: true)?.value == "true")
        #expect(KomaQueryEncoder.queryItem(name: "active", value: false)?.value == "false")
    }

    @Test
    func `a standalone double query item keeps its fractional part`() {
        #expect(KomaQueryEncoder.queryItem(name: "ratio", value: 1.5)?.value == "1.5")
    }

    private static func value(named name: String, in items: [URLQueryItem]) -> String? {
        items.first { $0.name == name }?.value
    }
}
