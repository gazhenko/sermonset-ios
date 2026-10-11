import Foundation
import CryptoKit
import SermonSetCore

public struct SpeechModelFile: Codable, Sendable, Equatable {
    public let name: String
    public let sizeBytes: Int64
    public let sha256: String?
    public let repository: String
    public let revision: String
    public let remotePath: String
    public init(name: String, sizeBytes: Int64, sha256: String? = nil, repository: String = "", revision: String = "main", remotePath: String? = nil) {
        self.name = name; self.sizeBytes = sizeBytes; self.sha256 = sha256
        self.repository = repository; self.revision = revision; self.remotePath = remotePath ?? name
    }
}

public enum SpeechModelConfiguration {
    public static let engineName = "Parakeet Ultra (on-device)"
    public static let revision = "ultra-diarization-v1"
    /// Reviewed snapshot hashes also reject changes to Ultra's upstream main.
    public static let files: [SpeechModelFile] = {
        guard let url = Bundle.module.url(forResource: "speech-model-files", withExtension: "json"),
              let data = try? Data(contentsOf: url), let files = try? JSONDecoder().decode([SpeechModelFile].self, from: data) else {
            preconditionFailure("The speech model manifest is missing or invalid")
        }
        return files
    }()
    public static var sizeBytes: Int64 { files.reduce(0) { $0 + $1.sizeBytes } }
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SermonSet/LocalModels/Speech-\(revision)", isDirectory: true)
    }
    static func downloadURL(_ file: SpeechModelFile) -> URL {
        URL(string: "https://huggingface.co/\(file.repository)/resolve/\(file.revision)/\(file.remotePath)")!
    }
    static func isComplete(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("verified-\(revision)").path)
            && files.allSatisfy { SpeechModelFiles.matchesSize($0, directory: directory) }
    }
}

enum SpeechModelFiles {
    static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        #endif
    }
    static func write(_ data: Data, to url: URL) throws {
        try prepare(url.deletingLastPathComponent())
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
    static func matchesSize(_ file: SpeechModelFile, directory: URL) -> Bool {
        let size = try? directory.appendingPathComponent(file.name).resourceValues(forKeys: [.fileSizeKey]).fileSize
        return size.map { Int64($0) == file.sizeBytes } ?? false
    }
    static func verify(_ file: SpeechModelFile, at url: URL) throws {
        guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) == file.sizeBytes else {
            throw SermonSetError(title: "Model download incomplete", message: "The speech model file has the wrong size. Resume the download to try again.")
        }
        if let expected = file.sha256 {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected else {
                throw SermonSetError(title: "Speech model needs another try", message: "The downloaded speech model failed its integrity check. Try the download again.")
            }
        }
    }
}
