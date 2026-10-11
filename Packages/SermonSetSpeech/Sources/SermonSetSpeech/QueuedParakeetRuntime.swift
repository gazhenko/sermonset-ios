import Foundation
import FluidAudio

/// A FIFO gate around the shared model runtime. Waiting does not allocate models.
actor QueuedParakeetRuntime: ParakeetRuntime {
    static let shared = QueuedParakeetRuntime(runtime: FluidSpeechRuntime.shared)
    private let runtime: any ParakeetRuntime
    private var running = false
    private var waiters: [(UUID, CheckedContinuation<Void, any Error>)] = []
    var isBusy: Bool { running }

    init(runtime: any ParakeetRuntime) { self.runtime = runtime }

    func recognize(fileURL: URL, startingAt: TimeInterval, directory: URL, language: Language,
                   onProgress: @escaping @MainActor @Sendable (Double) -> Void,
                   onWaiting: @escaping @MainActor @Sendable (Bool) -> Void) async throws -> SpeechRecognition {
        try await acquire(onWaiting: onWaiting)
        defer { release() }
        await onWaiting(false)
        try Task.checkCancellation()
        return try await runtime.recognize(fileURL: fileURL, startingAt: startingAt, directory: directory,
                                           language: language, onProgress: onProgress, onWaiting: onWaiting)
    }

    private func acquire(onWaiting: @escaping @MainActor @Sendable (Bool) -> Void) async throws {
        try Task.checkCancellation()
        if !running { running = true; return }
        let id = UUID()
        // Register without yielding the actor, preserving FIFO arrival order.
        // Await the notification before reporting that this run has started.
        let notification = Task { @MainActor in
            guard !Task.isCancelled else { return }
            onWaiting(true)
        }
        defer { notification.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters.append((id, continuation)) }
            }
        } onCancel: { Task { await self.cancel(id) } }
        await notification.value
    }
    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }
    private func release() {
        if waiters.isEmpty { running = false }
        else { waiters.removeFirst().1.resume() }
    }
}
