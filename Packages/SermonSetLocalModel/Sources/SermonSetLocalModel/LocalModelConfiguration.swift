import Foundation
import CryptoKit
import SermonSetCore

public struct LocalModelFile: Codable, Sendable, Equatable {
    public let name: String
    public let sizeBytes: Int64
    public let sha256: String?
    public init(name: String, sizeBytes: Int64, sha256: String? = nil) {
        self.name = name; self.sizeBytes = sizeBytes; self.sha256 = sha256
    }
}

public enum LocalModelConfiguration {
    public static let repository = "mlx-community/Qwen3.5-4B-MLX-4bit"
    public static let revision = "32f3e8ecf65426fc3306969496342d504bfa13f3"
    public static let engineName = "Qwen 3.5 4B (on-device)"
    public static let files: [LocalModelFile] = [
        .init(name: "config.json", sizeBytes: 3366),
        .init(name: "tokenizer_config.json", sizeBytes: 1139),
        .init(name: "chat_template.jinja", sizeBytes: 7756),
        .init(name: "model.safetensors.index.json", sizeBytes: 101944),
        .init(name: "tokenizer.json", sizeBytes: 19989343, sha256: "87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4"),
        .init(name: "model.safetensors", sizeBytes: 3034300695, sha256: "5fb9acd0246866381cf8c5c354c6db1019f6498eec4ccb4f5edcc71ffeacb2db")
    ]
    public static var sizeBytes: Int64 { files.reduce(0) { $0 + $1.sizeBytes } }
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SermonSet/LocalModels/Qwen35-\(revision)", isDirectory: true)
    }
    static func downloadURL(_ file: LocalModelFile) -> URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.name)")!
    }
}

enum ModelFiles {
    static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        #endif
    }
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
    static func matchesSize(_ file: LocalModelFile, directory: URL) -> Bool {
        let size = try? directory.appendingPathComponent(file.name).resourceValues(forKeys: [.fileSizeKey]).fileSize
        return size.map { Int64($0) == file.sizeBytes } ?? false
    }
    static func verify(_ file: LocalModelFile, at url: URL) throws {
        guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) == file.sizeBytes else {
            throw SermonSetError(title: "Model download incomplete", message: "The model file has the wrong size. Resume the download to try again.")
        }
        if let expected = file.sha256 {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected else {
                throw SermonSetError(title: "Model download needs another try", message: "The downloaded model did not pass its integrity check. Try the download again.")
            }
        }
    }
}
