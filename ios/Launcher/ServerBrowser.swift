//  ServerBrowser.swift -- finding live RTCW servers from the launcher.
//
//  This speaks the Quake 3 out-of-band protocol directly rather than going
//  through the engine, for one practical reason: the launcher runs before
//  Com_Init, so there is no engine yet. It also means the list is ready by the
//  time the player reaches the tab, instead of after the game has loaded.
//
//  The protocol, as measured against the live masters (docs/RU/server.md):
//
//    -> master   \xff\xff\xff\xff getservers <protocol>
//    <- master   \xff\xff\xff\xff getserversResponse \<4-byte IPv4><2-byte port> ... \EOT
//    -> server   \xff\xff\xff\xff getstatus x
//    <- server   \xff\xff\xff\xff statusResponse \n \<infostring> \n <player lines>
//
//  Two things about the masters that cost time to find and are easy to get
//  wrong:
//
//    * wolfmaster.idsoftware.com -- the official one, still alive -- answers
//      only the short form. Send it "getservers wolfmp 60" and it says nothing
//      at all. The short form is what the stock client sends, because
//      com_gamename is "wolfmp", which is LEGACY_MASTER_GAMENAME.
//    * Protocol 61, iortcw's own, is empty on every master. Every public server
//      registers as 60, including the iortcw ones, because com_legacyprotocol
//      defaults to 60. Asking only for 61 finds nothing and looks like a bug.
//
//  BSD sockets rather than Network.framework: this fires one datagram at each
//  of forty-odd hosts and collects whatever comes back, which is a poor fit for
//  an API built around a connection object per peer.

import Foundation
import Combine
import Darwin

// MARK: - Model

/// One server as the browser knows it.
struct GameServer: Identifiable, Equatable {
    let host: String
    let port: UInt16

    var id: String { "\(host):\(port)" }
    var address: String { "\(host):\(port)" }

    var name: String = ""
    var mapName: String = ""
    var mod: String = ""
    var humans: Int = 0
    var bots: Int = 0
    var maxClients: Int = 0
    var needsPassword: Bool = false
    var protocolVersion: String = ""
    var version: String = ""
    var pingMs: Int = 0

    /// Players excluding bots -- the number that actually says whether there is
    /// a game happening. Counting bots makes an empty server look full, and on
    /// this network most of them run 20+ of them.
    var occupancy: String { "\(humans)/\(maxClients)" }

    var isEmpty: Bool { humans == 0 }

    /// The engine build, coarsely. Useful because the 1.0 competitive line and
    /// the 1.4 line cannot see each other.
    var family: String {
        // The version string is the more reliable of the two: a fair number of
        // servers answer getstatus without a "protocol" key at all.
        if version.contains("iortcw") { return "iortcw" }
        if version.contains("1.41") || version.contains("1.4-") { return "1.4" }
        if version.contains("1.0") || version.contains("1.1") { return "1.0/1.1" }
        if protocolVersion == "57" { return "1.0/1.1" }
        if protocolVersion == "60" { return "1.4" }
        return protocolVersion.isEmpty ? "?" : "proto \(protocolVersion)"
    }
}

/// Strip Quake 3 colour codes (^1, ^7 ...) from a name for display.
func stripColorCodes(_ s: String) -> String {
    var out = ""
    var iterator = s.makeIterator()
    var pending: Character? = nil

    while let c = pending ?? iterator.next() {
        pending = nil
        if c == "^" {
            if let next = iterator.next() {
                // ^^ is a literal caret; ^<anything else> is a colour code.
                if next == "^" { out.append("^") } else if next.isNumber || next.isLetter {
                    continue
                } else {
                    pending = next
                }
            }
            continue
        }
        out.append(c)
    }
    return out.trimmingCharacters(in: .whitespaces)
}

// MARK: - Browser

@MainActor
final class ServerBrowser: ObservableObject {
    @Published private(set) var servers: [GameServer] = []
    @Published private(set) var isScanning = false
    @Published private(set) var status = ""
    @Published var hideEmpty = false

    private var scanTask: Task<Void, Never>?

    var visibleServers: [GameServer] {
        let list = hideEmpty ? servers.filter { !$0.isEmpty } : servers
        // Populated first, then by ping: the useful order for picking a game.
        return list.sorted {
            if $0.humans != $1.humans { return $0.humans > $1.humans }
            return $0.pingMs < $1.pingMs
        }
    }

    var summary: String {
        let people = servers.reduce(0) { $0 + $1.humans }
        return "Серверов: \(servers.count) · Игроков: \(people)"
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        status = "Опрашиваем мастер-серверы…"
        servers = []

        scanTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                ServerQuery.queryMasters()
            }.value

            guard let self, !Task.isCancelled else { return }

            if found.isEmpty {
                self.status = "Мастер-серверы не ответили. Проверьте подключение к сети."
                self.isScanning = false
                return
            }

            self.status = "Найдено адресов: \(found.count). Опрашиваем серверы…"

            let results = await Task.detached(priority: .userInitiated) {
                ServerQuery.queryServers(found)
            }.value

            guard !Task.isCancelled else { return }

            self.servers = results
            self.status = results.isEmpty
                ? "Ни один сервер не ответил."
                : "Онлайн: \(results.count) из \(found.count) адресов."
            self.isScanning = false
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        status = ""
    }
}

// MARK: - The wire protocol

/// Blocking UDP helpers. Always called off the main actor.
enum ServerQuery {
    static let oob: [UInt8] = [0xff, 0xff, 0xff, 0xff]

    /// The three masters that answer today. Measured, not assumed -- see
    /// docs/RU/server.md. The official one is first because it carries the
    /// fullest list.
    static let masters = [
        "wolfmaster.idsoftware.com",
        "dpmaster.deathmask.net",
        "master.iortcw.org",
    ]

    /// Protocols worth asking for. 60 is where everything modern lives; 57 is
    /// the 1.0 competitive scene, which is a third of the network; 59 and 50 are
    /// stragglers but cost one datagram each.
    static let protocols = [60, 57, 59, 50]

    static let masterPort: UInt16 = 27950

    /// Resolve a hostname to one IPv4 address.
    static func resolve(_ host: String) -> in_addr? {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_DGRAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil,
                             ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
            return nil
        }
        defer { freeaddrinfo(first) }

        return first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            $0.pointee.sin_addr
        }
    }

    private static func makeSockaddr(_ addr: in_addr, _ port: UInt16) -> sockaddr_in {
        var sa = sockaddr_in()
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_family = sa_family_t(AF_INET)
        sa.sin_port = port.bigEndian
        sa.sin_addr = addr
        return sa
    }

    private static func send(_ fd: Int32, _ payload: [UInt8], to addr: in_addr, port: UInt16) {
        var sa = makeSockaddr(addr, port)
        _ = withUnsafePointer(to: &sa) { saPtr in
            saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                payload.withUnsafeBufferPointer { buf in
                    sendto(fd, buf.baseAddress, buf.count, 0, generic,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private static func command(_ text: String) -> [UInt8] {
        oob + Array(text.utf8)
    }

    /// Ask every master for every protocol; return the union of the addresses.
    static func queryMasters() -> [(String, UInt16)] {
        var found = Set<String>()
        var ordered: [(String, UInt16)] = []

        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var tv = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        for master in masters {
            guard let addr = resolve(master) else { continue }

            for proto in protocols {
                // The short form only. The official master ignores the one with
                // a game name, and the other two accept both.
                send(fd, command("getservers \(proto)"), to: addr,
                     port: masterPort)
            }
        }

        // Collect for a fixed window rather than per-request: the replies come
        // back interleaved from three hosts and there is no request id to pair
        // them with.
        let deadline = Date().addingTimeInterval(3.0)
        var buffer = [UInt8](repeating: 0, count: 65536)

        while Date() < deadline {
            let n = recv(fd, &buffer, buffer.count, 0)
            if n <= 0 { continue }

            for (host, port) in parseServerList(Array(buffer[0..<n])) {
                let key = "\(host):\(port)"
                if found.insert(key).inserted {
                    ordered.append((host, port))
                }
            }
        }

        return ordered
    }

    /// Pull `\<ip><port>` records out of a getserversResponse.
    static func parseServerList(_ data: [UInt8]) -> [(String, UInt16)] {
        guard let start = find(data, Array("getserversResponse".utf8)) else { return [] }

        var out: [(String, UInt16)] = []
        var i = start + "getserversResponse".utf8.count

        while i + 6 < data.count {
            guard data[i] == UInt8(ascii: "\\") else { i += 1; continue }

            // "EOT" terminates the list.
            if i + 3 < data.count,
               data[i + 1] == UInt8(ascii: "E"),
               data[i + 2] == UInt8(ascii: "O"),
               data[i + 3] == UInt8(ascii: "T") {
                break
            }

            let host = "\(data[i+1]).\(data[i+2]).\(data[i+3]).\(data[i+4])"
            let port = (UInt16(data[i+5]) << 8) | UInt16(data[i+6])
            if port != 0 && host != "0.0.0.0" {
                out.append((host, port))
            }
            i += 7
        }
        return out
    }

    private static func find(_ haystack: [UInt8], _ needle: [UInt8]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for i in 0...(haystack.count - needle.count) where Array(haystack[i..<i+needle.count]) == needle {
            return i
        }
        return nil
    }

    /// Send getstatus to everything at once and gather the replies.
    static func queryServers(_ list: [(String, UInt16)]) -> [GameServer] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var tv = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var sentAt: [String: Date] = [:]

        for (host, port) in list {
            guard let addr = resolve(host) else { continue }
            sentAt["\(host):\(port)"] = Date()
            send(fd, command("getstatus x"), to: addr, port: port)
        }

        var found: [String: GameServer] = [:]
        var buffer = [UInt8](repeating: 0, count: 65536)
        let deadline = Date().addingTimeInterval(4.0)

        while Date() < deadline {
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let n = withUnsafeMutablePointer(to: &from) { fromPtr in
                fromPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    recvfrom(fd, &buffer, buffer.count, 0, generic, &fromLen)
                }
            }
            if n <= 0 { continue }

            let host = String(cString: inet_ntoa(from.sin_addr))
            let port = UInt16(bigEndian: from.sin_port)
            let key = "\(host):\(port)"

            guard var server = parseStatus(Array(buffer[0..<n]), host: host, port: port) else {
                continue
            }
            if let t = sentAt[key] {
                server.pingMs = max(1, Int(Date().timeIntervalSince(t) * 1000))
            }
            found[key] = server
        }

        return Array(found.values)
    }

    /// Turn a statusResponse into a GameServer.
    static func parseStatus(_ data: [UInt8], host: String, port: UInt16) -> GameServer? {
        // latin-1 keeps every byte addressable; names carry raw high bytes.
        let text = String(decoding: data.dropFirst(4), as: UTF8.self)
        let raw = text.isEmpty ? String(bytes: data.dropFirst(4), encoding: .isoLatin1) ?? "" : text

        let lines = raw.components(separatedBy: "\n")
        guard let head = lines.first, head.hasPrefix("statusResponse") else { return nil }
        guard lines.count > 1 else { return nil }

        var info: [String: String] = [:]
        let fields = lines[1].components(separatedBy: "\\").dropFirst()
        var iterator = fields.makeIterator()
        while let key = iterator.next(), let value = iterator.next() {
            info[key] = value
        }

        var server = GameServer(host: host, port: port)
        server.name = stripColorCodes(info["sv_hostname"] ?? info["hostname"] ?? host)
        server.mapName = info["mapname"] ?? "?"
        server.mod = stripColorCodes(info["gamename"] ?? "")
        server.maxClients = Int(info["sv_maxclients"] ?? "") ?? 0
        server.needsPassword = (info["needpass"] ?? "0") != "0"
        server.protocolVersion = info["protocol"] ?? ""
        server.version = info["version"] ?? ""

        // A bot always reports a ping of zero. Without this split the browser
        // shows 28/32 on a server where nobody is playing.
        for line in lines.dropFirst(2) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 2, let ping = Int(parts[1]) else { continue }
            if ping == 0 { server.bots += 1 } else { server.humans += 1 }
        }

        return server
    }
}
