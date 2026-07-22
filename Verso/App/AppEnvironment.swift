import Combine
import VersoApplication
import VersoFileSystem
import VersoDomain
import VersoObservability
import VersoPersistence

@MainActor
final class AppEnvironment: ObservableObject {
    let commandBus: CommandBus
    let workspaceService: WorkspaceLifecycleService
    let workspaceDocumentService: WorkspaceDocumentService

    private let diagnostics: UnifiedDiagnosticsRecorder
    private var isConfigured = false

    init(
        commandBus: CommandBus = CommandBus(),
        diagnostics: UnifiedDiagnosticsRecorder = UnifiedDiagnosticsRecorder(),
        deviceID: DeviceID? = nil,
        workspaceService: WorkspaceLifecycleService? = nil,
        workspaceDocumentService: WorkspaceDocumentService? = nil
    ) {
        self.commandBus = commandBus
        self.diagnostics = diagnostics
        let resolvedDeviceID = deviceID ?? LocalDeviceIdentityStore().loadOrCreate()
        self.workspaceService = workspaceService ?? WorkspaceLifecycleService(
            deviceID: resolvedDeviceID,
            diagnostics: diagnostics
        )
        self.workspaceDocumentService = workspaceDocumentService ??
            WorkspaceDocumentService(diagnostics: diagnostics)
    }

    func start() async throws {
        guard !isConfigured else { return }
        let trace = await diagnostics.begin(.appStartup)

        do {
            try await WorkspaceCommandRegistration.install(
                on: commandBus,
                service: workspaceService
            )
            try await WorkspaceDocumentCommandRegistration.install(
                on: commandBus,
                service: workspaceDocumentService
            )
            isConfigured = true
            await diagnostics.end(trace, outcome: .success)
        } catch {
            await diagnostics.record(
                ClassifiedError(
                    category: .invariantViolation,
                    operation: DiagnosticOperation.appStartup.rawValue,
                    technicalCode: String(describing: error),
                    traceID: trace.id
                )
            )
            await diagnostics.end(trace, outcome: .failure)
            throw error
        }
    }
}
