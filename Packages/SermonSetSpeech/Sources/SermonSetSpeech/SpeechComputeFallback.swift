import Foundation
import CoreML
import OSLog

enum SpeechComputeUnits: String, Codable, CaseIterable, Sendable {
    case cpuAndNeuralEngine, cpuAndGPU, cpuOnly
    var coreML: MLComputeUnits {
        switch self {
        case .cpuAndNeuralEngine: .cpuAndNeuralEngine
        case .cpuAndGPU: .cpuAndGPU
        case .cpuOnly: .cpuOnly
        }
    }
}

struct SpeechModelDiagnostic: Codable, Equatable, Sendable {
    var modelFile: String
    var computeUnits: String
    var stage: String
    var errorDomain: String?
    var errorCode: Int?
    var errorDescription: String?
    var underlyingErrors: [String]
    var detail: String {
        "\(modelFile) [\(computeUnits)] \(stage)" + (errorDomain.map { " — \($0) (\(errorCode ?? 0)): \(errorDescription ?? "")" } ?? " succeeded")
            + (underlyingErrors.isEmpty ? "" : "\n" + underlyingErrors.joined(separator: "\n"))
    }
}

struct SpeechComputeFailure: Error, LocalizedError {
    var diagnostics: [SpeechModelDiagnostic]
    var errorDescription: String? { diagnostics.map(\.detail).joined(separator: "\n") }
}

actor SpeechRunDiagnostics {
    private var entries: [SpeechModelDiagnostic] = []
    func replace(_ entries: [SpeechModelDiagnostic]) { self.entries = entries }
    func snapshot() -> [SpeechModelDiagnostic] { entries }
}

/// Each component is loaded and predicted independently. Only a successful
/// prediction persists placement; the cache is scoped to this model revision.
final class SpeechComputeFallback {
    private static let logger = Logger(subsystem: "com.gazhenko.sower", category: "SpeechModels")
    private let cacheURL: URL
    private var choices: [String: SpeechComputeUnits]
    private var pendingChoices: [String: SpeechComputeUnits] = [:]
    private(set) var diagnostics: [SpeechModelDiagnostic] = []
    init(directory: URL, revision: String = SpeechModelConfiguration.revision) {
        cacheURL = directory.appendingPathComponent("compute-units-\(revision).json")
        choices = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode([String: SpeechComputeUnits].self, from: $0) } ?? [:]
    }

    /// FluidAudio doesn't identify the component when a batch prediction throws.
    /// In that case retry the named group, leaving CPU-pinned stages alone.
    func advance(files: [String]) -> Bool {
        var changed = false
        for file in files {
            switch pendingChoices[file] ?? choices[file] ?? .cpuAndNeuralEngine {
            case .cpuAndNeuralEngine: pendingChoices[file] = .cpuAndGPU; changed = true
            case .cpuAndGPU: pendingChoices[file] = .cpuOnly; changed = true
            case .cpuOnly: break
            }
        }
        return changed
    }
    func placement(files: [String]) -> String {
        files.map { "\($0)=\((pendingChoices[$0] ?? choices[$0] ?? .cpuAndNeuralEngine).rawValue)" }.joined(separator: ", ")
    }

    func load<Model>(file: String, cpuOnly: Bool = false,
                     loader: (SpeechComputeUnits) throws -> Model,
                     firstPrediction: (Model) throws -> Void) throws -> Model {
        let order = SpeechComputeUnits.allCases
        let first = cpuOnly ? SpeechComputeUnits.cpuOnly : pendingChoices[file] ?? choices[file] ?? .cpuAndNeuralEngine
        let candidates = cpuOnly ? [.cpuOnly] : Array(order.dropFirst(order.firstIndex(of: first) ?? 0))
        for units in candidates {
            try Task.checkCancellation()
            var stage = "load"
            do {
                let model = try loader(units)
                stage = "first prediction"
                try Task.checkCancellation()
                try firstPrediction(model)
                try Task.checkCancellation()
                choices[file] = units
                pendingChoices[file] = nil
                try? SpeechModelFiles.write(try JSONEncoder().encode(choices), to: cacheURL)
                diagnostics.append(.init(modelFile: file, computeUnits: units.rawValue, stage: stage,
                    underlyingErrors: []))
                Self.logger.info("Speech component \(file, privacy: .public) ready with \(units.rawValue, privacy: .public)")
                return model
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                record(error, file: file, units: units.rawValue, stage: stage)
            }
        }
        throw SpeechComputeFailure(diagnostics: diagnostics)
    }

    func record(_ error: any Error, file: String, units: String = "not applicable", stage: String) {
        let ns = error as NSError
        var chain: [String] = [], next = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        for _ in 0..<8 {
            guard let underlying = next else { break }
            chain.append("\(underlying.domain) (\(underlying.code)): \(underlying.localizedDescription)")
            next = underlying.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let entry = SpeechModelDiagnostic(modelFile: file, computeUnits: units, stage: stage,
            errorDomain: ns.domain, errorCode: ns.code, errorDescription: ns.localizedDescription, underlyingErrors: chain)
        diagnostics.append(entry)
        Self.logger.error("Speech model failure: \(entry.detail, privacy: .public)")
    }

    func model(at directory: URL, file: String, cpuOnly: Bool = false) throws -> MLModel {
        try load(file: file, cpuOnly: cpuOnly) { units in
            let config = MLModelConfiguration(); config.computeUnits = units.coreML
            return try MLModel(contentsOf: directory.appendingPathComponent(file), configuration: config)
        } firstPrediction: { model in
            // These models use tensor inputs. Use their declared shapes/types,
            // valid token zero, and nonempty lengths to force Core ML's first
            // execution plan before handing them to FluidAudio.
            var features: [String: MLFeatureValue] = [:]
            for (name, description) in model.modelDescription.inputDescriptionsByName {
                guard let constraint = description.multiArrayConstraint else {
                    throw NSError(domain: "SowerSpeechModelInput", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported model input \(name)"])
                }
                let array = try MLMultiArray(shape: constraint.shape, dataType: constraint.dataType)
                let width: Int
                switch constraint.dataType {
                case .double: width = 8
                case .float16: width = 2
                case .int32, .float32: width = 4
                @unknown default:
                    throw NSError(domain: "SowerSpeechModelInput", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported tensor type for \(name)"])
                }
                memset(array.dataPointer, 0, array.count * width)
                if name.lowercased().contains("length") { array[0] = 1 }
                features[name] = MLFeatureValue(multiArray: array)
            }
            _ = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: features))
        }
    }
}

enum SpeechDiarizationRecovery {
    static func turns(_ operation: () async throws -> [SpeakerTurn],
                      onFailure: (any Error) -> Void,
                      isolation: isolated (any Actor)? = #isolation) async throws -> [SpeakerTurn] {
        do { return try await operation() }
        catch is CancellationError { throw CancellationError() }
        catch { try Task.checkCancellation(); onFailure(error); return [] }
    }
}
