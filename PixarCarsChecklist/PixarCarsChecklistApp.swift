import SwiftUI

@main
struct PixarCarsChecklistApp: App {
    #if os(iOS) && !targetEnvironment(macCatalyst)
    @UIApplicationDelegateAdaptor(MEPushNotificationAppDelegate.self) private var pushNotificationDelegate
    #endif

    @StateObject private var dataManager = DataManager.shared
    @StateObject private var backupManager = BackupManager()
    @Environment(\.scenePhase) private var scenePhase

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
            .task(id: dataManager.isReady) {
                guard dataManager.isReady else { return }
                _ = await dataManager.refreshCatalogForAppActivation()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, dataManager.isReady else { return }
                Task {
                    _ = await dataManager.refreshCatalogForAppActivation()
                }
            }
            #if os(macOS) || targetEnvironment(macCatalyst)
            .background(Color.white)
            #endif
        }
        .modelContainer(dataManager.modelContainer)
    }
}
