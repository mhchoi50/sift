import SwiftData
import SwiftUI

@main
struct SiftApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Item.self, Capture.self)
        } catch {
            fatalError("Couldn't open the Sift store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
#if DEBUG
                .task { SampleData.installIfRequested(in: container.mainContext) }
#endif
        }
        .modelContainer(container)
    }
}
