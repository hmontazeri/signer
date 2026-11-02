import Foundation
import Network
import Security

struct HTTPRequest {
    var method: String
    var path: String
    var query: [String: String]
    var body: Data
}

struct HTTPResponse {
    var status = 200
    var contentType = "application/json"
    var body = Data()

    static func text(_ s: String, status: Int = 200, type: String = "text/plain; charset=utf-8") -> HTTPResponse {
        HTTPResponse(status: status, contentType: type, body: Data(s.utf8))
    }

    static func json(_ obj: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, contentType: "application/json", body: data)
    }
}

/// Minimaler HTTP-Server im lokalen Netz, damit das iPhone per Safari unterschreiben kann.
final class PhoneServer {
    /// 128 Bit Zufall, nur für diesen App-Start gültig (wird nicht gespeichert).
    let token: String = {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }()

    func isValid(token candidate: String?) -> Bool {
        guard let c = candidate?.utf8 else { return false }
        let a = Array(token.utf8), b = Array(c)
        var diff = a.count ^ b.count
        for i in 0..<a.count { diff |= Int(a[i] ^ (i < b.count ? b[i] : 0)) }
        return diff == 0
    }

    private(set) var port: UInt16 = 0
    var handler: (@Sendable (HTTPRequest) async -> HTTPResponse)?
    var onReady: (() -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "signer.phoneserver")

    func start() {
        let l: NWListener
        if let fixed = try? NWListener(using: .tcp, on: 8765) {
            l = fixed
        } else if let any = try? NWListener(using: .tcp) {
            l = any
        } else { return }
        l.stateUpdateHandler = { [weak self, weak l] state in
            if case .ready = state, let p = l?.port?.rawValue {
                self?.port = p
                DispatchQueue.main.async { self?.onReady?() }
            }
        }
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.start(queue: queue)
        listener = l
    }

    // MARK: Verbindungen

    private final class Conn {
        let nw: NWConnection
        var buffer = Data()
        init(_ nw: NWConnection) { self.nw = nw }
    }

    private func accept(_ nw: NWConnection) {
        let c = Conn(nw)
        nw.start(queue: queue)
        receive(c)
    }

    private func receive(_ c: Conn) {
        c.nw.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            guard let self else { return }
            if let data { c.buffer.append(data) }
            if c.buffer.count > 8_000_000 { c.nw.cancel(); return }
            switch Self.parse(c.buffer) {
            case .complete(let req):
                Task {
                    let resp = await self.handler?(req) ?? .text("no handler", status: 500)
                    self.send(resp, on: c)
                }
            case .incomplete:
                if error == nil && !done { self.receive(c) } else { c.nw.cancel() }
            case .invalid:
                self.send(.text("Bad Request", status: 400), on: c)
            }
        }
    }

    private func send(_ r: HTTPResponse, on c: Conn) {
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found"][r.status] ?? "Error"
        var head = "HTTP/1.1 \(r.status) \(reason)\r\n"
        head += "Content-Type: \(r.contentType)\r\nContent-Length: \(r.body.count)\r\n"
        head += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        c.nw.send(content: Data(head.utf8) + r.body, completion: .contentProcessed { _ in c.nw.cancel() })
    }

    private enum Parsed { case complete(HTTPRequest), incomplete, invalid }

    private static func parse(_ data: Data) -> Parsed {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        guard let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { return .invalid }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count >= 2 else { return .invalid }
        var length = 0
        for l in lines.dropFirst() {
            let kv = l.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].lowercased() == "content-length" {
                guard let n = Int(kv[1].trimmingCharacters(in: .whitespaces)), n >= 0, n <= 8_000_000 else { return .invalid }
                length = n
            }
        }
        let body = data[end.upperBound...]
        if body.count < length { return .incomplete }
        let comps = URLComponents(string: String(parts[1]))
        var q: [String: String] = [:]
        for item in comps?.queryItems ?? [] { q[item.name] = item.value ?? "" }
        return .complete(HTTPRequest(method: String(parts[0]), path: comps?.path ?? "/", query: q, body: Data(body.prefix(length))))
    }

    // MARK: LAN-Adresse

    static func lanIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var fallback: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = ptr.pointee
            guard let sa = i.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(i.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: i.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if ip.hasPrefix("169.254") { continue }
            if name == "en0" { return ip }
            fallback = fallback ?? ip
        }
        return fallback
    }
}
