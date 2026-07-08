import ComposableArchitecture
import SwiftUI

@main
struct PNGCompressorPDFVectorCheckApp: App {
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
            state.pngCompressionSettings.quantizationLevel = nil
        }

        if arguments.contains("UITestDisablePDFCheck") {
            state.enablePDFCheck = false
        }

        return state
    }
}
