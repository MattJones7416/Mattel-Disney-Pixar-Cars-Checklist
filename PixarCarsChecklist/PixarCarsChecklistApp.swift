import SwiftUI

@main
struct PixarCarsChecklistApp: App {
    @StateObject private var dataManager = DataManager.shared
    @StateObject private var backupManager = BackupManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if !dataManager.isReady {
                    LoadingView()
                } else {
                    ContentView()
                        .environmentObject(dataManager)
                        .environmentObject(backupManager)
                        .environmentObject(PurchaseManager.shared)
                }
            }
            #if os(macOS) || targetEnvironment(macCatalyst)
            .background(Color.white)
            #endif
        }
        .modelContainer(dataManager.modelContainer)
    }
}
