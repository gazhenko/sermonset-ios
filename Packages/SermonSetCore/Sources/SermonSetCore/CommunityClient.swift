import Foundation

public struct CommunityConfiguration: Hashable, Sendable {
    public static let defaultBaseURL = URL(string: "https://sower.gazhenko.dev")!
    public var baseURL: URL
    public init(baseURL: URL = Self.defaultBaseURL) { self.baseURL = baseURL }
    public static func fromLaunchArguments(_ args: [String] = ProcessInfo.processInfo.arguments) -> Self {
        if let i = (args.firstIndex(of: "-SowerServer") ?? args.firstIndex(of: "-SermonSetServer")), args.indices.contains(i+1), let url = URL(string: args[i+1]), url.host != nil, ["http","https"].contains(url.scheme) { return Self(baseURL: url) }
        return Self()
    }
    public static var current: Self { .fromLaunchArguments() }
    public var audience: String { baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
}
public struct CommunityAPIError: Error, LocalizedError, Sendable {
    public var code: String; public var message: String; public var status: Int
    public var errorDescription: String? { message }
    public var retryable: Bool { status == 429 || status >= 500 }
}
@MainActor final class CommunityClient {
    var configuration: CommunityConfiguration
    var signer: (any DeviceRequestSigner)?
    var accountID: String?
    let session: URLSession
    let store: SermonStore
    init(store: SermonStore,configuration: CommunityConfiguration,signer: (any DeviceRequestSigner)?,session: URLSession) {
        self.store = store; self.configuration = configuration; self.signer = signer; self.session = session
        accountID = store.document.features?.community?.server == configuration.audience ? store.document.features?.community?.account?.id : nil
    }
    func request<T: Decodable>(_ method: String,_ path: String,body: Data? = nil,signed: Bool = true,idempotencyKey: String? = nil) async throws -> T {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), let url = URL(string: configuration.audience+path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 30
        if body != nil { request.setValue("application/json",forHTTPHeaderField: "Content-Type") }
        if signed {
            guard let signer else { throw SermonSetError(title: "Account needed",message: "Create or recover an account to use community features. Your private library is available.") }
            try SignedRequest.authorize(&request,signer: signer,accountID: accountID)
        }
        if ["POST","PATCH","DELETE"].contains(method) {
            let digest = Data((configuration.audience+"|"+(accountID ?? "registration")+"|"+method+"|"+path+"|").utf8) + (body ?? Data())
            request.setValue(idempotencyKey ?? digest.sha256Hex,forHTTPHeaderField: "Idempotency-Key")
        }
        let (data,response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(APIFailure.self,from: data)
            throw CommunityAPIError(code: error?.error.code ?? "http_error",message: error?.error.message ?? "The community service is unavailable. Try again later.",status: http.statusCode)
        }
        guard http.value(forHTTPHeaderField: "API-Version") == "1" else { throw CommunityAPIError(code: "unsupported_version",message: "This server uses an unsupported API version.",status: 409) }
        return try APIJSON.decoder.decode(T.self,from: data)
    }
    func send<B: Encodable,T: Decodable>(_ method: String,_ path: String,body: B,signed: Bool = true,key: String? = nil) async throws -> T { try await request(method,path,body: APIJSON.encoder.encode(body),signed: signed,idempotencyKey: key) }
    func page<T: Decodable>(_ path: String,signed: Bool = true) async throws -> [T] {
        var values: [T] = [], cursor: String?, seen: Set<String> = []
        repeat {
            let suffix = cursor.map { (path.contains("?") ? "&" : "?")+"cursor="+Self.escape($0) } ?? ""
            let page: APIPage<T> = try await request("GET",path+suffix,signed: signed)
            values.append(contentsOf: page.items); cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw URLError(.badServerResponse) }
        } while cursor != nil
        return values
    }
    nonisolated static func escape(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? "" }
}
enum APIJSON {
    static var encoder: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }
    static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
            if let date = f.date(from: text) { return date }; f.formatOptions = [.withInternetDateTime]
            guard let date = f.date(from: text) else { throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),debugDescription: "Invalid UTC date") }; return date
        }; return d
    }
}

struct APIFailure: Decodable { struct Detail: Decodable { var code: String; var message: String }; var error: Detail }
