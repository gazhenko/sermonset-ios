import Foundation
import FoundationModels

/// Recovery applies to one model response, never to cancellation or persistence.
enum FoundationModelRecovery {
    static func isRecoverable(_ error: any Error) -> Bool {
        if error is DecodingError { return true }
        guard let error = error as? LanguageModelSession.GenerationError else { return false }
        switch error {
        case .decodingFailure, .guardrailViolation, .refusal, .exceededContextWindowSize: return true
        default: return false
        }
    }

    @MainActor static func unit<T>(_ operation: () async throws -> T) async throws -> T? {
        for attempt in 0...1 {
            try Task.checkCancellation()
            do { return try await operation() }
            catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                guard isRecoverable(error) else { throw error }
                if attempt == 1 { return nil }
            }
        }
        return nil
    }
}
