import Foundation
import AppKit
import Network
import CryptoKit
import Observation

/// Unread inbox through the Gmail API, read-only. The user brings their own OAuth client (Desktop app type);
/// consent runs in the browser and comes back on a loopback port. Only the refresh token is kept, in the Keychain.
@Observable final class Gmail {
    static let shared = Gmail()

    struct Message: Identifiable {
        let id: String
        let from: String
        let subject: String
        let snippet: String
        let date: Date
        var link: URL { URL(string: "https://mail.google.com/mail/u/0/#inbox/\(id)")! }
    }

    var messages: [Message] = []
    var error: String?
    var loading = false
    var connecting = false

    static let clientAccount = "gmail-client-id"
    static let secretAccount = "gmail-client-secret"
    static let refreshAccount = "gmail-refresh-token"

    private var accessToken: String?
    private var expiry = Date.distantPast
    private var listener: NWListener?

    var hasClient: Bool { !(Keychain.get(Self.clientAccount) ?? "").isEmpty && !(Keychain.get(Self.secretAccount) ?? "").isEmpty }
    var connected: Bool { Keychain.get(Self.refreshAccount) != nil }

    func disconnect() {
        Keychain.set("", account: Self.refreshAccount)
        accessToken = nil
        messages = []
    }

    // MARK: OAuth

    func connect() async {
        guard let clientID = Keychain.get(Self.clientAccount), let secret = Keychain.get(Self.secretAccount) else { return }
        connecting = true
        defer { connecting = false }
        do {
            let verifier = Self.random(64)
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
            let state = Self.random(16)
            let (code, port) = try await waitForCode(expectedState: state) { port in
                var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
                c.queryItems = [
                    .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: "http://127.0.0.1:\(port)"),
                    .init(name: "response_type", value: "code"), .init(name: "scope", value: "https://www.googleapis.com/auth/gmail.readonly"),
                    .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent"),
                    .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                    .init(name: "state", value: state),
                ]
                NSWorkspace.shared.open(c.url!)
            }
            let token = try await tokenRequest([
                "code": code, "client_id": clientID, "client_secret": secret, "code_verifier": verifier,
                "redirect_uri": "http://127.0.0.1:\(port)", "grant_type": "authorization_code",
            ])
            guard let refresh = token["refresh_token"] as? String else { throw GmailError("Google did not return a refresh token. Remove Wave at myaccount.google.com/permissions and connect again.") }
            Keychain.set(refresh, account: Self.refreshAccount)
            error = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Opens a loopback listener, hands the port to `open`, resolves with the authorization code.
    private func waitForCode(expectedState: String, open: @escaping (UInt16) -> Void) async throws -> (String, UInt16) {
        listener?.cancel()
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            listener.stateUpdateHandler = { state in
                if case .ready = state, let port = listener.port?.rawValue { open(port) }
                if case .failed(let e) = state, !resumed { resumed = true; continuation.resume(throwing: e) }
            }
            listener.newConnectionHandler = { conn in
                conn.start(queue: .main)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                    let request = String(decoding: data ?? Data(), as: UTF8.self)
                    let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                    let items = URLComponents(string: "http://127.0.0.1" + path)?.queryItems ?? []
                    let code = items.first { $0.name == "code" }?.value
                    let state = items.first { $0.name == "state" }?.value
                    let ok = code != nil && state == expectedState
                    let body = "<html><body style=\"font-family:-apple-system,sans-serif;padding:48px;color:#111\"><h2>\(ok ? "Wave is connected to Gmail." : "Something went wrong.")</h2><p>You can close this tab.</p></body></html>"
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                    conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                        conn.cancel()
                        guard !resumed else { return }
                        resumed = true
                        listener.cancel()
                        if ok, let code, let port = listener.port?.rawValue { continuation.resume(returning: (code, port)) }
                        else { continuation.resume(throwing: GmailError("Google sent back an error instead of a code.")) }
                    })
                }
            }
            listener.start(queue: .main)
        }
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }.joined(separator: "&").utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let e = json["error"] as? String { throw GmailError("Google: \(e) \(json["error_description"] as? String ?? "")") }
        return json
    }

    private func token() async throws -> String {
        if let accessToken, expiry > .now.addingTimeInterval(60) { return accessToken }
        guard let refresh = Keychain.get(Self.refreshAccount), let clientID = Keychain.get(Self.clientAccount), let secret = Keychain.get(Self.secretAccount) else {
            throw GmailError("Not connected.")
        }
        let json = try await tokenRequest(["refresh_token": refresh, "client_id": clientID, "client_secret": secret, "grant_type": "refresh_token"])
        guard let access = json["access_token"] as? String else { throw GmailError("Could not refresh the Google token.") }
        accessToken = access
        expiry = .now.addingTimeInterval(TimeInterval(json["expires_in"] as? Int ?? 3600))
        return access
    }

    // MARK: Inbox

    func load() async {
        guard connected else { return }
        loading = true
        defer { loading = false }
        do {
            let list = try await get("messages?q=is:unread%20in:inbox&maxResults=12")
            let ids = ((list["messages"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
            var out: [Message] = []
            for id in ids {
                let m = try await get("messages/\(id)?format=metadata&metadataHeaders=From&metadataHeaders=Subject")
                let headers = ((m["payload"] as? [String: Any])?["headers"] as? [[String: Any]]) ?? []
                func header(_ name: String) -> String { headers.first { ($0["name"] as? String) == name }?["value"] as? String ?? "" }
                let ms = Double(m["internalDate"] as? String ?? "") ?? 0
                out.append(Message(id: id, from: Self.displayName(header("From")), subject: header("Subject").isEmpty ? "(no subject)" : header("Subject"),
                                   snippet: (m["snippet"] as? String ?? "").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\""),
                                   date: Date(timeIntervalSince1970: ms / 1000)))
            }
            messages = out
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func get(_ path: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/" + path)!)
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GmailError("Gmail: \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func displayName(_ from: String) -> String {
        from.split(separator: "<").first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) } ?? from
    }

    private static func random(_ count: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<count).map { _ in chars.randomElement()! })
    }
}

struct GmailError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
