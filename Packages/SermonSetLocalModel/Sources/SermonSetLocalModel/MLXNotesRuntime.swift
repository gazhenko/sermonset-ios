import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import SermonSetCore

@MainActor protocol LocalNotesRuntime: AnyObject {
    func load(directory: URL) async throws
    func unload()
    func tokenCount(_ text: String) async -> Int
    func promptTokenCount(instructions: String, prompt: String) async throws -> Int
    func respond(instructions: String, prompt: String, responseTokens: Int) async throws -> String
    var metrics: NotesGenerationMetrics { get }
}

@MainActor final class MLXNotesRuntime: LocalNotesRuntime {
    private var model: ModelContainer?
    private var oldCacheLimit: Int?
    private var promptTokens = 0, generatedTokens = 0
    private var didMeasureMemory = false
    var metrics: NotesGenerationMetrics {
        NotesGenerationMetrics(promptTokens: promptTokens, generatedTokens: generatedTokens, peakModelMemoryBytes: didMeasureMemory ? Int64(Memory.peakMemory) : nil, tokenCountMethod: "MLX GenerateCompletionInfo inference counters, summed across completed passes and retries")
    }
    static func availableMemory() -> UInt64 {
        LocalModelMemory.available()
    }
    func load(directory: URL) async throws {
        let required = UInt64(LocalModelConfiguration.sizeBytes) + 1536 * 1024 * 1024
        guard Self.availableMemory() >= required else {
            throw SermonSetError(title: "Not enough memory for Qwen", message: "This iPhone does not currently have enough app memory for Qwen and its working space. Try again or use Apple Intelligence.")
        }
        oldCacheLimit = Memory.cacheLimit
        Memory.cacheLimit = 20 * 1024 * 1024
        Memory.peakMemory = 0
        didMeasureMemory = true
        // A directory configuration resolves weights AND tokenizer locally.
        model = try await LLMModelFactory.shared.loadContainer(configuration: ModelConfiguration(directory: directory))
    }
    func unload() {
        model = nil
        Memory.clearCache()
        if let oldCacheLimit { Memory.cacheLimit = oldCacheLimit }
        oldCacheLimit = nil
    }
    func tokenCount(_ text: String) async -> Int { await model?.encode(text).count ?? Int.max }
    nonisolated private static func input(instructions: String, prompt: String) -> sending UserInput {
        UserInput(chat: [.system(instructions), .user(prompt)], additionalContext: ["enable_thinking": false])
    }
    func promptTokenCount(instructions: String, prompt: String) async throws -> Int {
        guard let model else { throw CocoaError(.coderReadCorrupt) }
        let prepared = try await model.prepare(input: Self.input(instructions: instructions, prompt: prompt))
        return prepared.text.tokens.size
    }
    func respond(instructions: String, prompt: String, responseTokens: Int) async throws -> String {
        try Task.checkCancellation()
        guard let model else { throw CocoaError(.coderReadCorrupt) }
        #if os(iOS)
        guard Self.availableMemory() >= 512 * 1024 * 1024 else {
            throw SermonSetError(title: "Qwen needs more memory", message: "App memory is running low. Your transcript and completed sections are saved; try again or use Apple Intelligence.")
        }
        #endif
        let prepared = try await model.prepare(input: Self.input(instructions: instructions, prompt: prompt))
        guard prepared.text.tokens.size + responseTokens + 128 <= 16_384 else {
            throw SermonSetError(title: "Notes input too large", message: "These notes exceed the local model's reserved context. Your transcript and completed sections are saved.")
        }
        let stream = try await model.generate(input: prepared, parameters: GenerateParameters(maxTokens: responseTokens, temperature: 0.2, prefillStepSize: 256))
        var response = ""
        for await generation in stream {
            try Task.checkCancellation()
            switch generation {
            case let .chunk(text): response += text
            case let .info(info): promptTokens += info.promptTokenCount; generatedTokens += info.generationTokenCount
            case .toolCall: break
            }
        }
        try Task.checkCancellation()
        return response
    }
}
