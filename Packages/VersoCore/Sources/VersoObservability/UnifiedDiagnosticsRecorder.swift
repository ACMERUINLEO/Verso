import Foundation
import VersoApplication

public actor UnifiedDiagnosticsRecorder: DiagnosticsRecording {
    private let logger: VersoLogger
    private let performanceTracer: PerformanceTracer
    private let maximumRecentErrors: Int
    private var activeTraces: [UUID: PerformanceTracer.Token] = [:]
    private var recentErrors: [ClassifiedError] = []

    public init(
        logger: VersoLogger = VersoLogger(category: .diagnostics),
        performanceTracer: PerformanceTracer = PerformanceTracer(),
        maximumRecentErrors: Int = 50
    ) {
        self.logger = logger
        self.performanceTracer = performanceTracer
        self.maximumRecentErrors = max(1, maximumRecentErrors)
    }

    public func begin(_ operation: DiagnosticOperation) -> DiagnosticTrace {
        let trace = DiagnosticTrace(operation: operation)
        activeTraces[trace.id] = performanceTracer.begin(operation)
        logger.info(
            "begin operation=\(operation.rawValue) trace=\(trace.id.uuidString)"
        )
        return trace
    }

    public func end(
        _ trace: DiagnosticTrace,
        outcome: DiagnosticOutcome
    ) {
        if let token = activeTraces.removeValue(forKey: trace.id) {
            performanceTracer.end(token)
        }
        logger.info(
            "end operation=\(trace.operation.rawValue) trace=\(trace.id.uuidString) outcome=\(outcome.rawValue)"
        )
    }

    public func record(_ error: ClassifiedError) {
        recentErrors.append(error)
        if recentErrors.count > maximumRecentErrors {
            recentErrors.removeFirst(recentErrors.count - maximumRecentErrors)
        }
        logger.error(error)
    }

    public func recentErrorsSnapshot() -> [ClassifiedError] {
        recentErrors
    }
}
