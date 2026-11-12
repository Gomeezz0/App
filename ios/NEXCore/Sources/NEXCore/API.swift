import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Modelos del contrato HTTP (docs/API.md)

public struct AuthTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String

    public init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

public struct UserProfile: Codable, Equatable, Sendable {
    public struct Stats: Codable, Equatable, Sendable {
        public var reports: Int
        public var confirmationsReceived: Int
        public var votesCast: Int
    }

    public var id: String
    public var email: String
    public var displayName: String
    public var reputation: Int
    public var createdAt: Date
    public var stats: Stats
}

public struct ReportResult: Codable, Sendable {
    public var alert: CommunityAlert
    public var merged: Bool
}

public struct VoteResult: Codable, Sendable {
    public var alert: CommunityAlert?
    public var removed: Bool
}

public enum APIError: LocalizedError, Equatable {
    /// Error devuelto por el servidor con su código y mensaje.
    case server(status: Int, code: String, message: String)
    /// Hace falta iniciar sesión (o la sesión ha caducado y no se pudo renovar).
    case unauthorized
    case network(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .server(_, _, let message): return message
        case .unauthorized: return "Inicia sesión para continuar."
        case .network: return "Sin conexión con el servidor de NEX."
        case .invalidResponse: return "Respuesta inesperada del servidor."
        }
    }
}

/// Almacén de credenciales. En la app se implementa sobre el Keychain.
public protocol TokenStore: AnyObject {
    func load() -> AuthTokens?
    func save(_ tokens: AuthTokens)
    func clear()
}

// MARK: - Cliente

/// Cliente del backend de NEX. Renueva el token de acceso de forma transparente.
public actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let store: TokenStore
    private var refreshTask: Task<AuthTokens, Error>?

    public init(baseURL: URL, tokenStore: TokenStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.store = tokenStore
        self.session = session
    }

    public var isSignedIn: Bool { store.load() != nil }

    // MARK: Cuenta

    private struct SessionResponse: Decodable {
        var accessToken: String
        var refreshToken: String
        var user: UserProfile?
    }

    public func register(email: String, password: String, displayName: String) async throws -> UserProfile {
        try await authenticate(
            "v1/auth/register", ["email": email, "password": password, "displayName": displayName])
    }

    public func login(email: String, password: String) async throws -> UserProfile {
        try await authenticate("v1/auth/login", ["email": email, "password": password])
    }

    private func authenticate(_ path: String, _ body: [String: String]) async throws -> UserProfile {
        let response: SessionResponse = try await send("POST", path, body: body, authorized: false)
        store.save(AuthTokens(accessToken: response.accessToken, refreshToken: response.refreshToken))
        guard let user = response.user else { throw APIError.invalidResponse }
        return user
    }

    public func logout() async {
        if let tokens = store.load() {
            let _: Empty? = try? await send(
                "POST", "v1/auth/logout", body: ["refreshToken": tokens.refreshToken], authorized: false)
        }
        store.clear()
    }

    public func me() async throws -> UserProfile {
        try await send("GET", "v1/me")
    }

    public func updateDisplayName(_ name: String) async throws -> UserProfile {
        try await send("PATCH", "v1/me", body: ["displayName": name])
    }

    public func deleteAccount(password: String) async throws {
        let _: Empty = try await send("DELETE", "v1/me", body: ["password": password])
        store.clear()
    }

    // MARK: Avisos

    private struct AlertList: Decodable { var alerts: [CommunityAlert] }

    public func alerts(near center: Coordinate, radius: Double) async throws -> [CommunityAlert] {
        let query = [
            URLQueryItem(name: "lat", value: String(center.latitude)),
            URLQueryItem(name: "lon", value: String(center.longitude)),
            URLQueryItem(name: "radius", value: String(Int(radius))),
        ]
        // Lectura pública: se envía la sesión si la hay, pero no es obligatoria.
        let list: AlertList = try await send("GET", "v1/alerts", query: query, authorized: isSignedIn)
        return list.alerts
    }

    private struct ReportBody: Encodable {
        var type: AlertType
        var lat: Double
        var lon: Double
        var heading: Double?
        var country: String?
        var reporterLat: Double
        var reporterLon: Double
    }

    public func report(_ type: AlertType, at location: Coordinate, heading: Double?, country: String?) async throws
        -> ReportResult
    {
        let body = ReportBody(
            type: type, lat: location.latitude, lon: location.longitude, heading: heading, country: country,
            reporterLat: location.latitude, reporterLon: location.longitude)
        return try await send("POST", "v1/alerts", body: body)
    }

    private struct VoteBody: Encodable {
        var vote: AlertVote
        var lat: Double
        var lon: Double
    }

    public func vote(_ vote: AlertVote, on alertID: String, from location: Coordinate) async throws -> VoteResult {
        try await send(
            "POST", "v1/alerts/\(alertID)/votes",
            body: VoteBody(vote: vote, lat: location.latitude, lon: location.longitude))
    }

    // MARK: Transporte

    private struct Empty: Decodable {}
    private struct NoBody: Encodable {}
    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable {
            var code: String
            var message: String
        }
        var error: Detail
    }

    private func send<Response: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], authorized: Bool = true
    ) async throws -> Response {
        try await send(method, path, query: query, body: Optional<NoBody>.none, authorized: authorized)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Body?, authorized: Bool = true
    ) async throws -> Response {
        let payload = try body.map { try JSONEncoder().encode($0) }
        var (data, status) = try await perform(method, path, query, payload, token: authorized ? store.load()?.accessToken : nil)

        if status == 401, authorized, store.load() != nil {
            let tokens = try await refreshedTokens()
            (data, status) = try await perform(method, path, query, payload, token: tokens.accessToken)
        }
        if status == 401, authorized { throw APIError.unauthorized }

        guard (200..<300).contains(status) else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw APIError.server(status: status, code: envelope.error.code, message: envelope.error.message)
            }
            throw APIError.invalidResponse
        }
        if data.isEmpty, let empty = Empty() as? Response { return empty }
        do {
            return try Self.decoder().decode(Response.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    private func perform(_ method: String, _ path: String, _ query: [URLQueryItem], _ body: Data?, token: String?)
        async throws -> (Data, Int)
    {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            return (data, http.statusCode)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    /// Renueva la sesión. Las peticiones concurrentes comparten una única renovación,
    /// porque el refresh token es de un solo uso.
    private func refreshedTokens() async throws -> AuthTokens {
        if let refreshTask { return try await refreshTask.value }
        guard let current = store.load() else { throw APIError.unauthorized }
        let task = Task { () throws -> AuthTokens in
            let payload = try JSONEncoder().encode(["refreshToken": current.refreshToken])
            let (data, status) = try await perform("POST", "v1/auth/refresh", [], payload, token: nil)
            guard status == 200, let response = try? JSONDecoder().decode(SessionResponse.self, from: data) else {
                // Solo se cierra la sesión si el servidor la rechaza; un fallo de red no la invalida.
                if status == 401 { store.clear() }
                throw APIError.unauthorized
            }
            let tokens = AuthTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)
            store.save(tokens)
            return tokens
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// Decodificador con las fechas ISO 8601 con milisegundos que emite el backend.
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let text = try container.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath, debugDescription: "Fecha no válida: \(text)"))
        }
        return decoder
    }
}
