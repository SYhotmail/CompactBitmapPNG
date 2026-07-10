import ComposableArchitecture
import SwiftUI

@main
struct CompactBitmapPNGApp: App {
    init() {
        if ProcessInfo.processInfo.environment["UITesting"] == "true" {
            prepareDependencies {
                $0.defaultAppStorage = .inMemory
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppView(
                store: Store(initialState: initialState()) {
                    AppFeature()
                }
            )
            .frame(minWidth: 880, minHeight: 620)
        }
        .windowResizability(.contentSize)
    }

    private func initialState() -> AppFeature.State {
        var state = AppFeature.State()
        let arguments = Set(ProcessInfo.processInfo.arguments)

        if arguments.contains("UITestDisableQuantization") {
            state.compressionSettings.quantizationLevel = nil
        }

        if arguments.contains("UITestDisablePDFCheck") {
            state.enablePDFCheck = false
        }

        return state
    }
}
