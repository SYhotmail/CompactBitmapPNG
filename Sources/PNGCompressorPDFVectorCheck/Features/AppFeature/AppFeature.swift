import ComposableArchitecture
import Foundation

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var processingState = ProcessingState.idle
        var pngResults = [PNGCompressionResult]()
        var pdfResults = [PDFAnalysisResult]()
        var pendingPNGURLs = [URL]()
        var pendingPDFURLs = [URL]()
        var enablePNGCompression = true
        var enablePDFCheck = true
        var pngCompressionSettings = PNGCompressionSettings()
        var intakeMessage = L10n.string("intake.defaultMessage")
        var rootSelections = [URL]()
        @Presents var alert: AlertState<Action.Alert>?
    }

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case alert(PresentationAction<Alert>)
        case clearResults
        case processURLs([URL])
        case preparationFinished(IntakeSummary, pngURLs: [URL], pdfURLs: [URL])
        case processingFinished([PNGCompressionResult], [PDFAnalysisResult])

        enum Alert: Equatable {}
    }

    @Dependency(\.processingClient) var processingClient

    private enum CancelID {
        case processing
    }

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .alert(.dismiss):
                state = State() // reset..
                fallthrough
            case .alert:
                return .none
            case .clearResults:
                state = State()
                return .cancel(id: CancelID.processing)

            case let .processURLs(urls):
                state.rootSelections = urls

                let enablePNGCompression = state.enablePNGCompression
                let enablePDFCheck = state.enablePDFCheck
                let pngCompressionSettings = state.pngCompressionSettings

                return .run { send in
                    let discovered = await processingClient.discoverSupportedFiles(urls)
                    let summary = summarize(
                        files: discovered,
                        enablePNGCompression: enablePNGCompression,
                        enablePDFCheck: enablePDFCheck
                    )
                    let pngURLs = enablePNGCompression ? discovered.compactMap { $0.kind == .png ? $0.url : nil } : []
                    let pdfURLs = enablePDFCheck ? discovered.compactMap { $0.kind == .pdf ? $0.url : nil } : []

                    await send(.preparationFinished(summary, pngURLs: pngURLs, pdfURLs: pdfURLs))

                    guard !pngURLs.isEmpty || !pdfURLs.isEmpty else { return }

                    async let pngResults = processingClient.processPNGs(pngURLs, pngCompressionSettings)
                    async let pdfResults = processingClient.processPDFs(pdfURLs)
                    let results = await (pngResults, pdfResults)
                    await send(.processingFinished(results.0, results.1))
                }
                .cancellable(id: CancelID.processing, cancelInFlight: true)

            case let .preparationFinished(summary, pngURLs, pdfURLs):
                state.intakeMessage = summary.description
                state.pngResults = []
                state.pdfResults = []
                state.pendingPNGURLs = pngURLs
                state.pendingPDFURLs = pdfURLs

                if pngURLs.isEmpty && pdfURLs.isEmpty {
                    state.processingState = .idle
                    state.alert = AlertState {
                        TextState(L10n.string("alert.nothingProcessed.title"))
                    } actions: {
                        ButtonState(role: .cancel) {
                            TextState(L10n.string("alert.ok"))
                        }
                    } message: {
                        TextState(summary.description)
                    }
                } else {
                    state.processingState = .running(statusMessage(pngCount: pngURLs.count, pdfCount: pdfURLs.count))
                }

                return .none

            case let .processingFinished(pngResults, pdfResults):
                state.pngResults = pngResults
                state.pdfResults = pdfResults
                state.pendingPNGURLs = []
                state.pendingPDFURLs = []
                state.processingState = .idle
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

private func summarize(
    files: [DiscoveredFile],
    enablePNGCompression: Bool,
    enablePDFCheck: Bool
) -> IntakeSummary {
    let pngCount = files.filter { $0.kind == .png }.count
    let pdfCount = files.filter { $0.kind == .pdf }.count
    let unsupportedCount = files.count - pngCount - pdfCount

    let disabledCount =
        (enablePNGCompression ? 0 : pngCount) +
        (enablePDFCheck ? 0 : pdfCount)

    return IntakeSummary(
        acceptedPNGCount: enablePNGCompression ? pngCount : 0,
        acceptedPDFCount: enablePDFCheck ? pdfCount : 0,
        skippedUnsupportedCount: unsupportedCount,
        skippedDisabledCount: disabledCount
    )
}

private func statusMessage(pngCount: Int, pdfCount: Int) -> String {
    if pngCount > 0 && pdfCount > 0 {
        return L10n.format(
            "status.compressingAndChecking",
            L10n.plural("status.pngFileCount", pngCount),
            L10n.plural("status.pdfFileCount", pdfCount)
        )
    }

    if pngCount > 0 {
        return L10n.format("status.compressingOnly", L10n.plural("status.pngFileCount", pngCount))
    }

    return L10n.format("status.checkingOnly", L10n.plural("status.pdfFileCount", pdfCount))
}
