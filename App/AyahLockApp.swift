import SwiftUI

@main
struct AyahLockApp: App {
    @StateObject private var player = RecitationPlayer.shared
    @StateObject private var library = LibraryModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                QuranHomeView()
                    .tabItem { Label("Quran", systemImage: "book") }
                ContentView()
                    .tabItem { Label("Lock Screen", systemImage: "lock.iphone") }
            }
            .environmentObject(player)
            .environmentObject(library)
            .task {
                if !player.isActive {
                    await RecitationPlayer.endStaleActivities()
                }
            }
        }
    }
}
