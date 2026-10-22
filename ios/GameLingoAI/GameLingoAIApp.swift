import SwiftUI

@main
struct GameLingoAIApp: App {
    var body: some Scene {
        WindowGroup {
            #if DIRECT_CAPTURE
            DirectHomeView()
                .preferredColorScheme(.dark)
            #else
            ContentView()
                .preferredColorScheme(.dark)
            #endif
        }
    }
}
