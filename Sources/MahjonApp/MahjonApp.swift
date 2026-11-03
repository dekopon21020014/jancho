import SwiftData
import SwiftUI

@main
struct MahjonApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // 対局記録は端末内にSwiftDataで保存する．
        // iCloud同期を有効化するときは，iCloud capability追加のうえ
        // ModelConfiguration(cloudKitDatabase: .private("iCloud.com.deko.mahjon"))
        // を指定した ModelContainer に差し替える．
        .modelContainer(for: GameRecord.self)
    }
}
