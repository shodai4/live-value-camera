import SwiftUI

@main
struct LiveValueCameraApp: App {
    init() {
        AdsSetup.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
