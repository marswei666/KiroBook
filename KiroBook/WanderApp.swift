import SwiftUI

@main
struct WanderApp: App {
    @StateObject private var store = EntryStore()
    @StateObject private var lang = LanguageManager()
    @StateObject private var subscription = AppleSubscriptionManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(lang)
                .environmentObject(subscription)
        }
    }
}
