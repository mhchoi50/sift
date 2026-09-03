import SwiftData
import SwiftUI

struct CaptureView: View {
    @Environment(\.modelContext) private var context
    @Query private var allItems: [Item]

    @StateObject private var speech = SpeechRecognizer()
    @State private var draft = ""
    @State private var isParsing = false
    @State private var proposal: ProposalContext?
    @State private var errorText: String?
    @State private var showingSettings = false
    @FocusState private var typing: Bool

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isParsing
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcriptArea
                Rule()
                controls
            }
            .background(Theme.paper)
            .navigationTitle("sift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(item: $proposal) { ctx in
                ReviewSheet(transcript: ctx.transcript, drafts: ctx.items) { committed in
                    finish(committed: committed)
                }
            }
            .alert("Couldn't organize that", isPresented: .constant(errorText != nil)) {
                Button("OK") { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: Pieces

    private var transcriptArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if draft.isEmpty && !speech.isRecording {
                    Text("What's going on?")
                        .font(Theme.display)
                        .foregroundStyle(Theme.ink)
                    Text("Talk the way you'd tell a friend. Sift pulls out the events, tasks and notes.")
                        .font(Theme.serif(16))
                        .foregroundStyle(Theme.inkSoft)
                } else {
                    Text(draft.isEmpty ? "Listening…" : draft)
                        .font(Theme.serif(20))
                        .foregroundStyle(draft.isEmpty ? Theme.inkFaint : Theme.ink)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let message = speech.errorMessage {
                    Text(message).font(Theme.caption).foregroundStyle(Theme.backlog)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                TextField("or type it", text: $draft, axis: .vertical)
                    .font(Theme.body)
                    .lineLimit(1...4)
                    .focused($typing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(Theme.rule, lineWidth: 0.5)
                    )
                    .disabled(speech.isRecording)

                Button(action: submit) {
                    Image(systemName: isParsing ? "ellipsis" : "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.paper)
                        .frame(width: 40, height: 40)
                        .background(canSubmit ? Theme.ink : Theme.inkFaint, in: Circle())
                }
                .disabled(!canSubmit)
            }

            Button(action: toggleRecording) {
                HStack(spacing: 9) {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 15, weight: .medium))
                    Text(speech.isRecording ? "Stop" : "Hold that thought")
                        .font(Theme.serif(17, .medium))
                }
                .foregroundStyle(speech.isRecording ? Theme.paper : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(speech.isRecording ? Theme.backlog : Theme.paperRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(speech.isRecording ? .clear : Theme.rule, lineWidth: 0.5)
                )
            }
            .disabled(isParsing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Theme.paper)
        .onChange(of: speech.transcript) { _, new in
            if speech.isRecording { draft = new }
        }
    }

    // MARK: Actions

    private func toggleRecording() {
        typing = false
        if speech.isRecording {
            speech.stop()
        } else {
            speech.reset()
            draft = ""
            Task { await speech.start() }
        }
    }

    private func submit() {
        speech.stop()
        typing = false
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isParsing = true
        Task {
            do {
                let response = try await CaptureParser.parse(transcript: text)
                isParsing = false
                if response.items.isEmpty {
                    errorText = "Nothing in that looked like a task, event or note."
                } else {
                    proposal = ProposalContext(transcript: response.transcript, items: response.items)
                }
            } catch {
                isParsing = false
                errorText = error.localizedDescription
            }
        }
    }

    /// Called once the review sheet has been accepted.
    private func finish(committed: [Item]) {
        guard !committed.isEmpty else {
            proposal = nil
            return
        }
        let capture = Capture(transcript: proposal?.transcript ?? draft)
        context.insert(capture)
        for item in committed {
            item.capture = capture
            context.insert(item)
        }
        try? context.save()

        proposal = nil
        draft = ""
        speech.reset()

        // @Query hasn't refreshed yet at this point, so fold the new items in by hand.
        var byID: [UUID: Item] = [:]
        for item in allItems + committed { byID[item.id] = item }
        let snapshot = Array(byID.values)
        Task {
            // Asked here rather than at launch: permission requested before you
            // have anything scheduled is permission denied.
            _ = await Scheduler.requestAuthorization()
            await Scheduler.rebuild(items: snapshot)
        }
    }
}

/// Carries a parse result into the review sheet.
struct ProposalContext: Identifiable {
    let id = UUID()
    let transcript: String
    let items: [ParsedItemDTO]
}
