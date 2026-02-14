import Testing
import Foundation
@testable import EchoNotes

@Suite("KeychainStore")
struct KeychainStoreTests {
    // Use unique keys per test run to avoid collisions
    let testKey = "echonotes_test_\(UUID().uuidString)"

    @Test("Save and load round-trip")
    func saveAndLoad() throws {
        let data = Data("hello-keychain".utf8)
        try KeychainStore.save(key: testKey, data: data)

        let loaded = try KeychainStore.load(key: testKey)
        #expect(loaded == data)

        // Clean up
        try KeychainStore.delete(key: testKey)
    }

    @Test("Load returns nil for missing key")
    func loadMissing() throws {
        let result = try KeychainStore.load(key: "nonexistent_key_\(UUID().uuidString)")
        #expect(result == nil)
    }

    @Test("Delete removes stored data")
    func deleteKey() throws {
        let data = Data("to-delete".utf8)
        try KeychainStore.save(key: testKey, data: data)
        try KeychainStore.delete(key: testKey)

        let result = try KeychainStore.load(key: testKey)
        #expect(result == nil)
    }

    @Test("Save overwrites existing value")
    func overwrite() throws {
        let first = Data("first".utf8)
        let second = Data("second".utf8)

        try KeychainStore.save(key: testKey, data: first)
        try KeychainStore.save(key: testKey, data: second)

        let loaded = try KeychainStore.load(key: testKey)
        #expect(loaded == second)

        try KeychainStore.delete(key: testKey)
    }

    @Test("Delete nonexistent key does not throw")
    func deleteNonexistent() throws {
        try KeychainStore.delete(key: "nonexistent_\(UUID().uuidString)")
    }
}
