import Foundation
import WebKit
import Combine

// One claude.ai sign-in.
//
// Separate accounts need separate cookie jars — signing into a second one in the
// shared store would just sign you out of the first. WKWebsiteDataStore gives
// isolated persistent stores keyed by UUID, but only on macOS 14+.
struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String

    // The first account deliberately keeps the shared default store rather than
    // moving to an isolated one: that's where an existing install's sign-in
    // already lives, and migrating it would silently sign everyone out on
    // upgrade. Same reasoning as freezing the bundle identifier through the
    // rename.
    var usesLegacyStore: Bool
}

final class AccountStore: ObservableObject {
    static let shared = AccountStore()
    private let defaults = UserDefaults.standard
    private let key = "accounts"

    @Published private(set) var accounts: [Account] = []

    // Isolated cookie jars are macOS 14+. On Ventura the app stays
    // single-account rather than pretending and having two logins clobber
    // each other in one store.
    static var supportsMultipleAccounts: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    private init() {
        if let data = defaults.data(forKey: key),
           let list = try? JSONDecoder().decode([Account].self, from: data),
           !list.isEmpty {
            accounts = list
        } else {
            // First run, or upgrading from a single-account build: adopt the
            // existing sign-in as account one.
            accounts = [Account(id: UUID(), name: "Claude", usesLegacyStore: true)]
            persist()
        }
    }

    func add(name: String) {
        guard Self.supportsMultipleAccounts else { return }
        accounts.append(Account(id: UUID(), name: name, usesLegacyStore: false))
        persist()
    }

    func rename(_ account: Account, to name: String) {
        guard let i = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[i].name = name
        persist()
    }

    func remove(_ account: Account) {
        // Never drop the last one; the app has nothing to show without it.
        guard accounts.count > 1 else { return }
        accounts.removeAll { $0.id == account.id }
        persist()
        // Take the cookies with it, so "remove" actually signs out.
        if !account.usesLegacyStore, #available(macOS 14.0, *) {
            WKWebsiteDataStore.remove(forIdentifier: account.id) { _ in }
        }
    }

    // The cookie jar an account signs into.
    static func dataStore(for account: Account) -> WKWebsiteDataStore {
        if account.usesLegacyStore { return .default() }
        if #available(macOS 14.0, *) { return WKWebsiteDataStore(forIdentifier: account.id) }
        return .default()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: key)
    }
}
