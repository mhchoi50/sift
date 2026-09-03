import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var engine = CaptureParser.engine
    @State private var address = ServerConfig.urlString
    @State private var checkResult: String?
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Parse with", selection: $engine) {
                        ForEach(ParseEngine.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text(engine.blurb)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSoft)

                    if engine == .onDevice, let problem = OnDeviceParser.unavailableExplanation {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.backlog)
                    }
                } header: {
                    Text("Engine")
                }

                if engine == .server {
                    Section {
                        TextField("http://localhost:8787", text: $address)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(Theme.mono)
                        Button(checking ? "Checking…" : "Test connection") { check() }
                            .disabled(checking)
                        if let checkResult {
                            Text(checkResult)
                                .font(Theme.caption)
                                .foregroundStyle(checkResult.hasPrefix("Reached") ? Theme.note : Theme.backlog)
                        }
                    } header: {
                        Text("Parse server")
                    } footer: {
                        Text("On the simulator, localhost works. On a real phone, use your Mac's address on the same Wi-Fi, e.g. http://192.168.1.20:8787")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        CaptureParser.engine = engine
                        ServerConfig.urlString = address.trimmingCharacters(in: .whitespaces)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func check() {
        checking = true
        checkResult = nil
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        Task {
            defer { checking = false }
            guard let base = URL(string: trimmed), let url = URL(string: "health", relativeTo: base) else {
                checkResult = "That doesn't look like a URL."
                return
            }
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                checkResult = code == 200 ? "Reached the server." : "Server answered \(code)."
            } catch {
                checkResult = "No answer. Is the server running?"
            }
        }
    }
}
