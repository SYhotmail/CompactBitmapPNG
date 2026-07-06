import ComposableArchitecture
import SwiftUI

@main
struct PNGCompressorPDFVectorCheckApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(
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

        if arguments.contains("UITestEnableQuantization") {
            state.pngCompressionSettings.enableAdaptiveQuantization = true
        }

        if arguments.contains("UITestDisablePDFCheck") {
            state.enablePDFCheck = false
        }

        return state
    }
}
