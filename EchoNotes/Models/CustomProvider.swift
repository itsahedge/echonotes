import Foundation

/// Custom AI provider configuration
struct CustomProvider: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var name: String
    var endpoint: String
    var apiKey: String
    var model: String
    var authHeaderName: String
    var authHeaderValue: String
    var modelOptions: [String]
    
    init(id: String = UUID().uuidString, name: String, endpoint: String, apiKey: String, model: String, authHeaderName: String = "Authorization", authHeaderValue: String = "Bearer {key}", modelOptions: [String] = []) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.authHeaderName = authHeaderName
        self.authHeaderValue = authHeaderValue
        self.modelOptions = modelOptions.isEmpty ? [model] : modelOptions
    }
    
    var isValid: Bool {
        !name.isEmpty && !endpoint.isEmpty && !apiKey.isEmpty
    }
}

/// Storage for custom providers
final class CustomProviderStore: ObservableObject {
    @Published var providers: [CustomProvider] = []
    
    private static let key = "customProviders"
    
    init() {
        load()
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([CustomProvider].self, from: data) {
            providers = decoded
        }
    }
    
    func add(_ provider: CustomProvider) {
        providers.append(provider)
        save()
    }
    
    func update(_ provider: CustomProvider) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
            save()
        }
    }
    
    func remove(id: String) {
        providers.removeAll { $0.id == id }
        save()
    }
}