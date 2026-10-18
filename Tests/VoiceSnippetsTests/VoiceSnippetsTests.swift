import Foundation
import XCTest
@testable import VoiceSnippets

final class VoiceSnippetsTests: XCTestCase {
    func testCompletePhrasesAndCase() {
        let config = VoiceSnippetConfiguration(snippets: [.init(trigger: "my signature", text: "Regards,\nSam")])
        XCTAssertEqual(config.expand("MY SIGNATURE, please. my signature"), "Regards,\nSam, please. Regards,\nSam")
        XCTAssertEqual(config.expand("notmy signature or my signatures or émy signature or my signature_"), "notmy signature or my signatures or émy signature or my signature_")
        XCTAssertEqual(config.expand("my \n signature"), "Regards,\nSam")
    }

    func testLongestFirstAndNoRecursiveExpansion() {
        let config = VoiceSnippetConfiguration(snippets: [
            .init(trigger: "insert", text: "short"),
            .init(trigger: "insert signature", text: "insert"),
            .init(trigger: "signature", text: "other")
        ])
        XCTAssertEqual(config.expand("Insert signature. Insert."), "insert. short.")
        let overlap = VoiceSnippetConfiguration(snippets: [
            .init(trigger: "a b", text: "first"),
            .init(trigger: "b c d", text: "second")
        ])
        XCTAssertEqual(overlap.expand("a b c d"), "first c d")
    }

    func testFormattingAndLiteralReplacement() {
        let replacement = "  Hello\n\n\t- $1 \\ path\n"
        let config = VoiceSnippetConfiguration(snippets: [.init(trigger: "insert (note)", text: replacement)])
        XCTAssertEqual(config.expand("insert (note)"), replacement)
        XCTAssertEqual(config.expand("🙂 insert (note)!"), "🙂 \(replacement)!")
    }

    func testDisabledAndNoMatch() {
        var config = VoiceSnippetConfiguration(snippets: [.init(trigger: "hello", text: "bye", enabled: false)])
        XCTAssertEqual(config.expand("Hello"), "Hello")
        config.snippets[0].enabled = true
        config.enabled = false
        XCTAssertEqual(config.expand("Hello"), "Hello")
        XCTAssertEqual(VoiceSnippetConfiguration().expand("Unchanged\ntext"), "Unchanged\ntext")
        XCTAssertEqual(config.expand("No match"), "No match")
    }

    func testValidation() {
        for trigger in ["", "  ", " hello", "hello\nworld"] {
            XCTAssertThrowsError(try VoiceSnippetConfiguration(snippets: [.init(trigger: trigger, text: "")]).validate())
        }
        XCTAssertThrowsError(try VoiceSnippetConfiguration(snippets: [
            .init(trigger: "My signature", text: "one"),
            .init(trigger: "MY  SIGNATURE", text: "two", enabled: false)
        ]).validate())
    }

    func testPersistenceAndExternalEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("voice-snippets.json")
        let writer = VoiceSnippetStore(url: url)
        let reader = VoiceSnippetStore(url: url)
        let empty = try writer.load()
        XCTAssertTrue(empty.configuration.snippets.isEmpty)
        let config = VoiceSnippetConfiguration(snippets: [.init(trigger: "note", text: "line 1\n  line 2\n")])
        let saved = try writer.save(config, replacing: empty)
        XCTAssertEqual(try reader.load().configuration, config)
        XCTAssertEqual(reader.expandUsingLastValidConfiguration("NOTE"), "line 1\n  line 2\n")
        let external = """
        {"enabled":true,"snippets":[{"trigger":"note","text":"external\\nedit","enabled":true}]}
        """
        try external.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try reader.load().configuration.snippets[0].text, "external\nedit")
        XCTAssertThrowsError(try writer.save(config, replacing: saved))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), external)
        for invalid in ["{", #"{"enabled":true,"snippets":[{"trigger":"note","text":5,"enabled":true}]}"#,
                        #"{"enabled":true,"snippets":[{"trigger":"note","text":"one","enabled":true},{"trigger":"NOTE","text":"two","enabled":true}]}"#] {
            try invalid.write(to: url, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try reader.load())
            XCTAssertEqual(reader.expandUsingLastValidConfiguration("note"), "external\nedit")
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), invalid)
        }
        XCTAssertThrowsError(try writer.save(.init(snippets: [.init(trigger: "", text: "")]), replacing: saved))
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(try reader.load().configuration.snippets.isEmpty)
        XCTAssertEqual(reader.expandUsingLastValidConfiguration("note"), "note")
    }

    func testConfigurationLocation() {
        let root = URL(fileURLWithPath: "/project")
        XCTAssertEqual(VoiceSnippetStore.configurationURL(projectRoot: root, environment: [:]).path, "/project/work/fn-scribe-store/voice-snippets.json")
        XCTAssertEqual(VoiceSnippetStore.configurationURL(projectRoot: root, environment: ["FNSCRIBE_HOME": "/custom"]).path, "/custom/voice-snippets.json")
    }

    func testEditDisableDeleteAndInvalidSavePreservesFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = VoiceSnippetStore(url: directory.appendingPathComponent("voice-snippets.json"))
        var config = VoiceSnippetConfiguration(snippets: [.init(trigger: "hello", text: "first")])
        var snapshot = try store.save(config, replacing: store.load())
        config.snippets[0].text = "second\n  line"
        config.snippets[0].enabled = false
        snapshot = try store.save(config, replacing: snapshot)
        XCTAssertEqual(try store.load().configuration, config)
        var duplicate = config
        duplicate.snippets.append(.init(trigger: "HELLO", text: "duplicate"))
        XCTAssertThrowsError(try store.save(duplicate, replacing: snapshot))
        XCTAssertEqual(try Data(contentsOf: store.url), snapshot.data)
        config.enabled = false
        config.snippets = []
        _ = try store.save(config, replacing: snapshot)
        XCTAssertEqual(try store.load().configuration, config)
    }

    func testMalformedFieldFeedbackAndRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("voice-snippets.json")
        let store = VoiceSnippetStore(url: url)
        try #"{"enabled":true,"snippets":[{"trigger":"hello","enabled":true}]}"#
            .write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.load()) {
            XCTAssertTrue($0.localizedDescription.contains("text"))
            XCTAssertTrue($0.localizedDescription.contains("snippets"))
        }
        XCTAssertEqual(store.expandUsingLastValidConfiguration("hello"), "hello")
        try #"{"enabled":true,"snippets":[{"trigger":"hello","text":"fixed","enabled":true}]}"#
            .write(to: url, atomically: true, encoding: .utf8)
        _ = try store.load()
        XCTAssertEqual(store.expandUsingLastValidConfiguration("hello"), "fixed")
    }
}
