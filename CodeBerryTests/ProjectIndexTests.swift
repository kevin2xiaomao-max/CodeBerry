import XCTest
@testable import CodeBerry

/// §三十九: ProjectIndex — SwiftSyntax 符号索引.
final class ProjectIndexTests: XCTestCase {
    private let sample = """
        import SwiftUI

        /// App entry.
        struct MyApp: View {
            @State private var count = 0
            let title = "Hi"

            var body: some View {
                Text(title)
            }

            func increment(by amount: Int) {
                count += amount
            }

            init(title: String) {
                self.title = title
            }
        }

        class Store: ObservableObject {
            func load() {}
        }

        enum Mode: String {
            case on
            case off
        }

        protocol Loadable {
            func load()
        }

        extension MyApp {
            var doubled: Int { count * 2 }
        }

        typealias Handler = () -> Void
        """

    private func makeIndex(source: String? = nil) -> SymbolIndex {
        let index = SymbolIndex()
        index.updateFile(relativePath: "A.swift", content: source ?? sample)
        return index
    }

    func testFindsTypes() {
        let index = makeIndex()
        let names = Set(index.symbols.map(\.name))
        XCTAssertTrue(names.contains("MyApp"))
        XCTAssertTrue(names.contains("Store"))
        XCTAssertTrue(names.contains("Mode"))
        XCTAssertTrue(names.contains("Loadable"))
    }

    func testKinds() {
        let index = makeIndex()
        func kinds(of name: String) -> Set<CodeSymbol.Kind> {
            Set(index.symbols.filter { $0.name == name }.map(\.kind))
        }
        XCTAssertTrue(kinds(of: "MyApp").contains(.struct))
        XCTAssertTrue(kinds(of: "Store").contains(.class))
        XCTAssertTrue(kinds(of: "Mode").contains(.enum))
        XCTAssertTrue(kinds(of: "Loadable").contains(.protocol))
        XCTAssertTrue(kinds(of: "increment").contains(.function))
        XCTAssertTrue(kinds(of: "init").contains(.initializer))
        XCTAssertTrue(kinds(of: "count").contains(.variable))
        XCTAssertTrue(kinds(of: "title").contains(.constant))
        XCTAssertTrue(kinds(of: "Handler").contains(.typealias))
        XCTAssertTrue(kinds(of: "on").contains(.enumCase))
    }

    func testLineNumbers() {
        let index = makeIndex()
        // struct MyApp is on line 4 (1-based).
        let myApp = index.symbols.first { $0.name == "MyApp" && $0.kind == .struct }
        XCTAssertEqual(myApp?.line, 4)
        // class Store on line 21.
        let store = index.symbols.first { $0.name == "Store" }
        XCTAssertEqual(store?.line, 21)
    }

    func testParentNames() {
        let index = makeIndex()
        let increment = index.symbols.first { $0.name == "increment" }
        XCTAssertEqual(increment?.parentName, "MyApp")
        let on = index.symbols.first { $0.name == "on" }
        XCTAssertEqual(on?.parentName, "Mode")
    }

    func testExtensionRecorded() {
        let index = makeIndex()
        let ext = index.symbols.first { $0.kind == .extension }
        XCTAssertNotNil(ext)
        XCTAssertTrue(ext?.name.contains("MyApp") ?? false)
    }

    func testIncrementalUpdate() {
        let index = makeIndex()
        let before = index.symbols.count
        // Same content: no-op.
        index.updateFile(relativePath: "A.swift", content: sample)
        XCTAssertEqual(index.symbols.count, before)
        // Changed content: replaced.
        index.updateFile(relativePath: "A.swift", content: "struct Only {}\n")
        XCTAssertEqual(index.symbols.count, 1)
        XCTAssertEqual(index.symbols.first?.name, "Only")
    }

    func testRemoveFile() {
        let index = makeIndex()
        XCTAssertFalse(index.isEmpty)
        index.removeFile(relativePath: "A.swift")
        XCTAssertTrue(index.isEmpty)
    }

    func testFuzzyMatching() {
        let index = makeIndex()
        let hits = index.symbols(matching: "MyA")
        XCTAssertTrue(hits.contains { $0.name == "MyApp" })
        // Best match first: exact prefix wins.
        XCTAssertEqual(hits.first?.name, "MyApp")
        XCTAssertTrue(index.symbols(matching: "zzz-no-match").isEmpty)
    }

    func testDefinitionPrefersSameFile() {
        let index = SymbolIndex()
        index.updateFile(relativePath: "A.swift", content: "func helper() {}\n")
        index.updateFile(relativePath: "B.swift", content: "func helper() {}\n")
        let def = index.definition(of: "helper", inFile: "B.swift")
        XCTAssertEqual(def?.filePath, "B.swift")
    }

    func testDefinitionPrefersTypes() {
        let index = SymbolIndex()
        index.updateFile(relativePath: "A.swift",
                         content: "let Mode = 1\nstruct Mode {}\n")
        // Ambiguous name: types win over variables.
        let def = index.definition(of: "Mode")
        XCTAssertEqual(def?.kind, .struct)
    }

    func testReferences() {
        let index = SymbolIndex()
        index.updateFile(relativePath: "A.swift",
                         content: "func helper() {}\nlet x = helper()\n")
        index.updateFile(relativePath: "B.swift",
                         content: "let y = helper()\nlet helper2 = 1\n")
        guard let sym = index.definition(of: "helper") else {
            XCTFail("definition not found")
            return
        }
        let refs = index.references(of: sym, fileContents: [
            "A.swift": "func helper() {}\nlet x = helper()\n",
            "B.swift": "let y = helper()\nlet helper2 = 1\n",
        ])
        // A.swift line 2 and B.swift line 1; helper2 must not match; the
        // definition site (A.swift line 1) is excluded.
        XCTAssertEqual(refs.count, 2)
        XCTAssertTrue(refs.contains { $0.filePath == "A.swift" && $0.line == 2 })
        XCTAssertTrue(refs.contains { $0.filePath == "B.swift" && $0.line == 1 })
    }

    func testRebuildFromDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeberry-indextest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "struct Alpha {}\n".write(to: root.appendingPathComponent("One.swift"),
                                      atomically: true, encoding: .utf8)
        try "struct Beta {}\n".write(to: root.appendingPathComponent("Two.swift"),
                                     atomically: true, encoding: .utf8)
        let index = SymbolIndex()
        index.rebuild(projectRoot: root)
        let names = Set(index.symbols.map(\.name))
        XCTAssertEqual(names, ["Alpha", "Beta"])
    }
}
