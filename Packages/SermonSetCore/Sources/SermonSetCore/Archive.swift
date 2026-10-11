import Foundation
import CryptoKit
import CommonCrypto
import Observation

struct WrappedSecret: Codable, Sendable {
    var version: Int = 1
    var salt: Data
    var rounds: Int = 210_000
    var sealed: Data
    static func key(passphrase: String,salt: Data,rounds: Int) throws -> SymmetricKey {
        guard !passphrase.isEmpty, (100_000...1_000_000).contains(rounds), salt.count == 16 else { throw SermonSetError(title: "Passphrase needed",message: "Enter the archive's passphrase.") }
        let password = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
        var result = [UInt8](repeating: 0,count: 32)
        let status = password.withUnsafeBytes { p in salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),p.baseAddress!.assumingMemoryBound(to: Int8.self),password.count,s.baseAddress!.assumingMemoryBound(to: UInt8.self),salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),UInt32(rounds),&result,result.count)
        } }
        guard status == kCCSuccess else { throw SermonSetError(title: "Encryption unavailable",message: "The encryption key could not be derived.") }
        return SymmetricKey(data: result)
    }
    static func wrap(_ data: Data,passphrase: String) throws -> Self {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let key = try key(passphrase: passphrase,salt: salt,rounds: 210_000)
        let sealed = try AES.GCM.seal(data,using: key,authenticating: Data("SermonSet-secret-v1".utf8))
        return Self(salt: salt,sealed: sealed.combined!)
    }
    func open(passphrase: String) throws -> Data {
        guard version == 1 else { throw SermonSetError(title: "Archive unavailable",message: "This encrypted archive version is unsupported.") }
        do { return try AES.GCM.open(AES.GCM.SealedBox(combined: sealed),using: Self.key(passphrase: passphrase,salt: salt,rounds: rounds),authenticating: Data("SermonSet-secret-v1".utf8)) }
        catch { throw SermonSetError(title: "Could not unlock",message: "The passphrase is incorrect or the encrypted file has been changed.") }
    }
}
private extension Data {
    mutating func little<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) } }
    func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i+1]) << 8 }
    func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i+2)) << 16 }
}
enum LibraryZIP {
    static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n); for _ in 0..<8 { c = c & 1 != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1 }; return c
    }
    static func crc(_ data: Data,seed: UInt32 = 0xffffffff) -> UInt32 { data.reduce(seed) { ( $0 >> 8 ) ^ crcTable[Int(($0 ^ UInt32($1)) & 255)] } }
    static func safe(_ name: String) -> Bool { !name.isEmpty && !name.hasPrefix("/") && !name.contains("\\") && name.split(separator: "/",omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." } }
    @concurrent static func writeAsync(files: [(String,URL)],to url: URL) async throws { try write(files: files,to: url) }
    static func write(files: [(String,URL)],to url: URL) throws {
        guard files.count < 65535 else { throw SermonSetError(title: "Archive too large",message: "This archive has too many files for ZIP version 1.") }
        FileManager.default.createFile(atPath: url.path,contents: nil)
        let output = try FileHandle(forWritingTo: url); defer { try? output.close() }
        var central = Data(), offset: UInt32 = 0
        for (name,file) in files {
            guard safe(name), let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber, size.uint64Value <= UInt32.max else { throw SermonSetError(title: "Archive too large",message: "A file is too large for this ZIP format.") }
            let input = try FileHandle(forReadingFrom: file); defer { try? input.close() }
            var checksum: UInt32 = 0xffffffff
            while let data = try input.read(upToCount: 1_048_576), !data.isEmpty { checksum = crc(data,seed: checksum) }
            checksum ^= 0xffffffff; try input.seek(toOffset: 0)
            let bytes = Data(name.utf8), length = size.uint32Value
            guard bytes.count < 65535, UInt64(offset)+30+UInt64(bytes.count)+UInt64(length) < UInt32.max else { throw SermonSetError(title: "Archive too large",message: "ZIP archives over 4 GB are not supported yet.") }
            var header = Data(); header.little(UInt32(0x04034b50)); header.little(UInt16(20)); header.little(UInt16(0x800)); header.little(UInt16(0)); header.little(UInt32(0)); header.little(checksum); header.little(length); header.little(length); header.little(UInt16(bytes.count)); header.little(UInt16(0)); header.append(bytes)
            try output.write(contentsOf: header)
            while let data = try input.read(upToCount: 1_048_576), !data.isEmpty { try output.write(contentsOf: data) }
            central.little(UInt32(0x02014b50)); central.little(UInt16(20)); central.little(UInt16(20)); central.little(UInt16(0x800)); central.little(UInt16(0)); central.little(UInt32(0)); central.little(checksum); central.little(length); central.little(length); central.little(UInt16(bytes.count)); central.little(UInt16(0)); central.little(UInt16(0)); central.little(UInt16(0)); central.little(UInt16(0)); central.little(UInt32(0)); central.little(offset); central.append(bytes)
            offset += UInt32(header.count)+length
        }
        try output.write(contentsOf: central)
        var end = Data(); end.little(UInt32(0x06054b50)); end.little(UInt32(0)); end.little(UInt16(files.count)); end.little(UInt16(files.count)); end.little(UInt32(central.count)); end.little(offset); end.little(UInt16(0)); try output.write(contentsOf: end)
        try LocalFiles.protect(url)
    }
    static func extract(_ data: Data,to directory: URL) throws -> [String:URL] {
        var offset = 0, files: [String:URL] = [:], total: UInt64 = 0
        while offset+4 <= data.count && data.u32(offset) == 0x04034b50 {
            guard offset+30 <= data.count else { throw invalid }
            let flags = data.u16(offset+6), method = data.u16(offset+8), checksum = data.u32(offset+14), size = Int(data.u32(offset+18)), uncompressed = Int(data.u32(offset+22)), nameSize = Int(data.u16(offset+26)), extraSize = Int(data.u16(offset+28))
            let start = offset+30+nameSize+extraSize
            guard flags & ~0x800 == 0, method == 0, size == uncompressed, start <= data.count, size <= data.count-start, offset+30+nameSize <= data.count, let name = String(data: data.subdata(in: offset+30..<offset+30+nameSize),encoding: .utf8), safe(name), files[name] == nil else { throw invalid }
            total += UInt64(size); guard total < UInt32.max else { throw invalid }
            let contents = data.subdata(in: start..<start+size)
            guard crc(contents) ^ 0xffffffff == checksum else { throw invalid }
            let url = directory.appendingPathComponent(name)
            try LocalFiles.createDirectory(url.deletingLastPathComponent()); try contents.write(to: url,options: .atomic); try LocalFiles.protect(url)
            files[name] = url; offset = start+size
        }
        guard !files.isEmpty, offset+4 <= data.count, data.u32(offset) == 0x02014b50 else { throw invalid }
        let centralStart = offset
        var centralNames = Set<String>()
        while offset+4 <= data.count, data.u32(offset) == 0x02014b50 {
            guard offset+46 <= data.count else { throw invalid }
            let length = Int(data.u16(offset+28)), extra = Int(data.u16(offset+30)), comment = Int(data.u16(offset+32))
            let finish = offset+46+length+extra+comment
            guard finish <= data.count, let name = String(data: data.subdata(in: offset+46..<offset+46+length),encoding: .utf8), files[name] != nil, centralNames.insert(name).inserted, data.u16(offset+10) == 0 else { throw invalid }
            offset = finish
        }
        guard centralNames.count == files.count, offset+22 <= data.count, data.u32(offset) == 0x06054b50,
              data.u32(offset+4) == 0, Int(data.u16(offset+8)) == files.count, Int(data.u16(offset+10)) == files.count,
              Int(data.u32(offset+12)) == offset-centralStart, Int(data.u32(offset+16)) == centralStart,
              offset+22+Int(data.u16(offset+20)) == data.count else { throw invalid }
        return files
    }
    static var invalid: SermonSetError { SermonSetError(title: "Backup could not be read",message: "The ZIP backup is invalid, changed, or uses an unsupported format. Your existing library is preserved.") }
}
public struct BackupRestoreResult: Sendable, Hashable {
    public var addedSermons: Int
    public var skippedSermons: Int
}
extension SermonStore {
    public func exportLibraryBackup(passphrase: String? = nil) async throws -> URL {
        do {
            try LocalFiles.createDirectory(exportsDirectory)
            let stage = exportsDirectory.appendingPathComponent(UUID().uuidString)
            try LocalFiles.createDirectory(stage); defer { try? FileManager.default.removeItem(at: stage) }
            var snapshot = document
            var files: [(String,URL)] = []
            for asset in snapshot.audio.values {
                if asset.byteCount == 0 && asset.checksumSHA256 == nil && audioURL(for: asset) == nil { continue }
                guard let url = audioURL(for: asset) else { throw SermonSetError(title: "Audio missing",message: "A recording could not be found. Restore its file before exporting a complete backup.") }
                let name = "\(asset.id).\(url.pathExtension)"
                snapshot.audioPaths[asset.id] = name
                files.append(("audio/\(name)",url))
            }
            let manifest = stage.appendingPathComponent("library.json"); try LocalFiles.write(snapshot,to: manifest)
            files.insert(("library.json",manifest),at: 0)
            let zip = exportsDirectory.appendingPathComponent("Library-\(UUID()).zip")
            try await LibraryZIP.writeAsync(files: files,to: zip)
            if let passphrase {
                guard (try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 512_000_000 else { try? FileManager.default.removeItem(at: zip); throw SermonSetError(title: "Encrypted backup too large",message: "Use an unencrypted ZIP for libraries larger than 512 MB.") }
                let wrapped = try WrappedSecret.wrap(Data(contentsOf: zip),passphrase: passphrase)
                let encrypted = zip.deletingPathExtension().appendingPathExtension("ssbackup")
                try LocalFiles.write(wrapped,to: encrypted); try FileManager.default.removeItem(at: zip); return encrypted
            }
            return zip
        } catch { throw report(error) }
    }
    public func restoreLibraryBackup(from url: URL,passphrase: String? = nil) async throws -> BackupRestoreResult {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let stage = root.appendingPathComponent("Restore-\(UUID())")
        var installed: [URL] = []
        do {
            try LocalFiles.createDirectory(stage); defer { try? FileManager.default.removeItem(at: stage) }
            var data = try Data(contentsOf: url,options: .mappedIfSafe)
            if data.first != 0x50 {
                guard let passphrase else { throw SermonSetError(title: "Passphrase needed",message: "Enter the passphrase used to encrypt this backup.") }
                data = try LocalFiles.decoder.decode(WrappedSecret.self,from: data).open(passphrase: passphrase)
            }
            let files = try LibraryZIP.extract(data,to: stage)
            guard let manifest = files["library.json"] else { throw LibraryZIP.invalid }
            let restored = try LocalFiles.decoder.decode(StoreDocument.self,from: Data(contentsOf: manifest)); try restored.validate()
            guard files.count == restored.audioPaths.count+1, restored.audio.values.filter({ $0.byteCount > 0 || $0.checksumSHA256 != nil }).count == restored.audioPaths.count else { throw LibraryZIP.invalid }
            for (id,name) in restored.audioPaths {
                guard let file = files["audio/\(name)"], let asset = restored.audio[id], try LocalFiles.checksum(file) == asset.checksumSHA256, (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1) == asset.byteCount else { throw LibraryZIP.invalid }
                if let existing = document.audio[id], existing.checksumSHA256 != asset.checksumSHA256 { throw LibraryZIP.invalid }
            }
            let added = restored.sermons.keys.filter { document.sermons[$0] == nil }.count
            var merged = document
            for (id,sermon) in restored.sermons where merged.sermons[id] == nil { merged.sermons[id] = sermon }
            for (id,value) in restored.history where merged.history[id] == nil { merged.history[id] = value }
            for (id,value) in restored.features?.communityEditions ?? [:] { if merged.features == nil { merged.features = CoreFeatures() }; if merged.features?.communityEditions == nil { merged.features?.communityEditions = [:] }; merged.features?.communityEditions?[id] = value }
            for (id,value) in restored.editions where merged.editions[id] == nil { merged.editions[id] = value }
            for (id,value) in restored.cards where merged.cards[id] == nil && (restored.features?.communityEditions?[value.editionID] != nil || !merged.cards.values.contains(where: { $0.sermonID == value.sermonID })) { merged.cards[id] = value }
            for (id,value) in restored.notes where merged.notes[id] == nil { merged.notes[id] = value }
            for (id,value) in restored.moments where merged.moments[id] == nil { merged.moments[id] = value }
            for (id,values) in restored.transcripts {
                for value in values where !(merged.transcripts[id] ?? []).contains(where: { $0.id == value.id }) { merged.transcripts[id,default: []].append(value) }
            }
            for (id,value) in restored.insights where merged.insights[id] == nil { merged.insights[id] = value }
            if merged.features == nil { merged.features = CoreFeatures() }
            for (id,value) in restored.features?.trims ?? [:] where merged.features?.trims[id] == nil { merged.features?.trims[id] = value }
            for (id,value) in restored.features?.derivatives ?? [:] where merged.features?.derivatives[id] == nil { merged.features?.derivatives[id] = value }
            for (id,value) in restored.features?.officialSources ?? [:] { if merged.features?.officialSources == nil { merged.features?.officialSources = [:] }; merged.features?.officialSources?[id] = value }
            for (id,value) in restored.features?.serviceTokens ?? [:] { if merged.features?.serviceTokens == nil { merged.features?.serviceTokens = [:] }; if merged.features?.serviceTokens?[id] == nil { merged.features?.serviceTokens?[id] = value } }
            for (id,value) in restored.features?.locales ?? [:] where merged.features?.locales[id] == nil { merged.features?.locales[id] = value }
            merged.features?.staleTakeaways.formUnion(restored.features?.staleTakeaways ?? [])
            merged.features?.staleOutline.formUnion(restored.features?.staleOutline ?? [])
            for (id,asset) in restored.audio where merged.audio[id] == nil && restored.audioPaths[id] == nil { merged.audio[id] = asset }
            for (id,asset) in restored.audio where merged.audioPaths[id] == nil && restored.audioPaths[id] != nil {
                let name = restored.audioPaths[id]!, file = files["audio/\(name)"]!, destination = recordingsDirectory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: destination.path) { guard try LocalFiles.checksum(destination) == asset.checksumSHA256 else { throw LibraryZIP.invalid } }
                else { try FileManager.default.moveItem(at: file,to: destination); installed.append(destination) }
                merged.audio[id] = asset; merged.audioPaths[id] = name
            }
            try merged.validate()
            let protectedBeforeRestore = writesBlocked; writesBlocked = false
            do { try transaction { $0 = merged } } catch { writesBlocked = protectedBeforeRestore; throw error }
            clearError()
            return BackupRestoreResult(addedSermons: added,skippedSermons: restored.sermons.count-added)
        } catch { for file in installed { try? FileManager.default.removeItem(at: file) }; try? FileManager.default.removeItem(at: stage); throw report(error) }
    }
}
@MainActor @Observable public final class BackupController {
    public private(set) var state: JobState = .idle
    public private(set) var exportedURL: URL?
    public private(set) var restoreResult: BackupRestoreResult?
    private let store: SermonStore
    public init(store: SermonStore) { self.store = store }
    public func export(passphrase: String? = nil) async { state = .running(progress: nil); do { exportedURL = try await store.exportLibraryBackup(passphrase: passphrase); state = .done } catch { state = .failed(message: error.localizedDescription) } }
    public func restore(from url: URL,passphrase: String? = nil) async { state = .running(progress: nil); do { restoreResult = try await store.restoreLibraryBackup(from: url,passphrase: passphrase); state = .done } catch { state = .failed(message: error.localizedDescription) } }
}
