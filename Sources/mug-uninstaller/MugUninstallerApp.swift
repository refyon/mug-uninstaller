import SwiftUI

@main
struct MugUninstallerApp: App {
    var body: some Scene {
        WindowGroup {
            AppListView()
                .frame(minWidth: 560, minHeight: 420)
        }
        .defaultSize(width: 640, height: 480)
    }
}
