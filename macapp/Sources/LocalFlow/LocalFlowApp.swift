import SwiftUI

@main
struct LocalFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu-bar accessory; Settings scene satisfies SwiftUI App requirements.
        Settings {
            EmptyView()
        }
    }
}
