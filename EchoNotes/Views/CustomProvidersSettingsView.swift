import SwiftUI

struct CustomProvidersSettingsView: View {
    @ObservedObject var tm: TranscriptionManager
    @ObservedObject var recorder: RecordingEngine
    @StateObject private var providerStore = CustomProviderStore()
    
    @State private var showAddSheet = false
    @State private var selectedProvider: CustomProvider?
    
    var body: some View {
        VStack(spacing: 0) {
            if providerStore.providers.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(providerStore.providers) { provider in
                        CustomProviderRow(provider: provider)
                            .tag(provider)
                            .onTapGesture {
                                selectedProvider = provider
                            }
                    }
                }
            }
        }
        .navigationTitle("Custom Providers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCustomProviderSheet(providerStore: providerStore)
        }
        .confirmationDialog("Edit Provider", isPresented: .init(get: { selectedProvider != nil }, set: { if !$0 { selectedProvider = nil } })) {
            if let provider = selectedProvider {
                editButton(for: provider)
            }
        } message: {
            Text("Choose an action for \(providerStore.providers.first(where: { $0.id == selectedProvider?.id })?.name ?? "")")
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.circle")
                .font(.system(size: 64))
                .foregroundStyle(.gray)
            
            Text("No Custom Providers")
                .font(.headline)
            
            Text("Add a custom AI provider to use with your own API endpoint and credentials.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    func editButton(for provider: CustomProvider) -> some View {
        Button("Edit") {
            selectedProvider = provider
            showAddSheet = true
        }
        
        Button("Delete", role: .destructive) {
            providerStore.remove(id: provider.id)
            selectedProvider = nil
        }
    }
}

struct CustomProviderRow: View {
    let provider: CustomProvider
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.box")
                .font(.title2)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(provider.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text(provider.endpoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if provider.isValid {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddCustomProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var providerStore: CustomProviderStore
    
    @State private var name: String = ""
    @State private var endpoint: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var authHeaderName: String = "Authorization"
    @State private var authHeaderValue: String = "Bearer {key}"
    @State private var modelOptions: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Basic Info") {
                    TextField("Provider Name", text: $name)
                    
                    TextField("API Endpoint", text: $endpoint)
                }
                
                Section("Authentication") {
                    SecureTextField(text: $apiKey)
                    
                    TextField("Auth Header Name", text: $authHeaderName)
                    
                    TextField("Auth Header Value (use {key} for API key)", text: $authHeaderValue)
                }
                
                Section("Model") {
                    TextField("Default Model", text: $model)
                    
                    TextField("Model Options (comma-separated)", text: $modelOptions)
                        .help("Optional: List available models separated by commas")
                }
                
                Section("Preview") {
                    HStack {
                        Label(name.isEmpty ? "Your Custom Provider" : name, systemImage: "cube.box")
                            .foregroundStyle(.orange)
                        Spacer()
                        if isValid {
                            Label("Ready", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle(name.isEmpty ? "Add Provider" : "Edit Provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProvider()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty && !endpoint.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }
    
    private func saveProvider() {
        let models = modelOptions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let provider = CustomProvider(
            name: name,
            endpoint: endpoint,
            apiKey: apiKey,
            model: model,
            authHeaderName: authHeaderName,
            authHeaderValue: authHeaderValue,
            modelOptions: models
        )
        
        providerStore.add(provider)
        dismiss()
    }
}

struct SecureTextField: View {
    @Binding var text: String
    
    var body: some View {
        SecureField("", text: $text)
    }
}