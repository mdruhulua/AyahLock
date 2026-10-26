import SwiftUI

@main
struct AyahLockApp: App {
    @StateObject private var player = RecitationPlayer.shared
    @StateObject private var library = LibraryModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
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
