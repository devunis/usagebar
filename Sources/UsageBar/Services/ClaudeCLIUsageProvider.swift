import Foundation
import Darwin

private final class ClaudeProbeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
}

struct ClaudeCLIUsageProvider: Sendable {
    var executable: URL? = nil
    var workingDirectory: URL? = nil
    var timeout: TimeInterval = 35

    static let arguments = [
        "--safe-mode", "--strict-mcp-config",
        "--settings", "{\"remoteControlAtStartup\":false,\"disableAllHooks\":true}",
        "--no-session-persistence", "--tools", "", "--permission-mode", "dontAsk",
        "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"
    ]

    func fetchQuota() async throws -> QuotaSnapshot {
        let cancellation = ClaudeProbeCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(with: Result { try fetchBlocking(cancellation: cancellation) })
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func fetchBlocking(cancellation: ClaudeProbeCancellation) throws -> QuotaSnapshot {
        try cancellation.check()
        let process = Process()
        process.executableURL = try executable ?? executableURL(named: "claude", candidates: [
            "~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"
        ])
        process.arguments = Self.arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        else { try configureCLIProcess(process, for: "claude") }
        // Suppress SIGPIPE on this connection only. A process-wide signal policy
        // would also affect the already-working Codex provider.
        var sockets = [Int32](repeating: -1, count: 2)
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else {
            throw UsageProviderError.commandFailed("Claude Code 조회 연결을 준비하지 못했습니다.")
        }
        var noSigPipe: Int32 = 1
        guard setsockopt(sockets[0], SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
                         socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            Darwin.close(sockets[0]); Darwin.close(sockets[1])
            throw UsageProviderError.commandFailed("Claude Code 조회 연결을 안전하게 준비하지 못했습니다.")
        }
        let input = FileHandle(fileDescriptor: sockets[0], closeOnDealloc: true)
        let childInput = FileHandle(fileDescriptor: sockets[1], closeOnDealloc: true)
        let output = Pipe()
        process.standardInput = childInput
        process.standardOutput = output
        // Do not retain raw CLI stderr: it can contain session/account details.
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        var started = false
        defer {
            try? input.close()
            try? childInput.close()
            if started {
                if process.isRunning { process.terminate() }
                if finished.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                    // Only this disposable probe, never another Claude session.
                    Darwin.kill(process.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + 2)
                }
            }
            try? output.fileHandleForReading.close()
        }
        do { try process.run(); started = true; try childInput.close() }
        catch { throw UsageProviderError.commandFailed("Claude Code CLI를 실행할 수 없습니다.") }

        var session = ClaudeUsageControlSession()
        try send(session.initializeRequest, to: input)
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        var receivedBytes = 0
        var bytes = [UInt8](repeating: 0, count: 16_384)
        let descriptor = output.fileHandleForReading.fileDescriptor
        while Date() < deadline {
            try cancellation.check()
            var descriptorState = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let result = Darwin.poll(&descriptorState, 1, 100)
            if result < 0 {
                if errno == EINTR { continue }
                throw UsageProviderError.commandFailed("Claude Code 응답을 읽지 못했습니다.")
            }
            if result == 0 { continue }
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw UsageProviderError.commandFailed("Claude Code 응답을 읽지 못했습니다.")
            }
            if count == 0 { break }
            receivedBytes += count
            guard receivedBytes <= 8_000_000 else { throw UsageProviderError.invalidResponse }
            buffer.append(contentsOf: bytes.prefix(count))
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard line.count <= 1_000_000 else { throw UsageProviderError.invalidResponse }
                guard !line.isEmpty,
                      let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
                switch try session.receive(object) {
                case .ignore: break
                case .requestUsage:
                    try send(session.usageRequest, to: input)
                case .usage(let payload):
                    return try Self.parse(payload)
                }
            }
            guard buffer.count <= 1_000_000 else { throw UsageProviderError.invalidResponse }
        }
        try cancellation.check()
        throw UsageProviderError.commandFailed("Claude Code 사용량 조회가 완료되지 않았습니다. CLI 설치·로그인 상태를 확인해 주세요.")
    }

    private func send(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        // SO_NOSIGPIPE turns a closed peer into an ordinary recoverable error.
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(handle.fileDescriptor, base.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    throw UsageProviderError.commandFailed("Claude Code 조회 연결이 종료되었습니다.")
                }
                offset += count
            }
        }
    }

    static func parse(_ payload: [String: Any], now: Date = Date()) throws -> QuotaSnapshot {
        guard payload["rate_limits_available"] as? Bool == true,
              var limits = payload["rate_limits"] as? [String: Any] else {
            throw UsageProviderError.missingCredential("Claude Code에서 구독 계정으로 로그인해 주세요. API 키 계정에는 구독 한도가 제공되지 않습니다.")
        }
        var rows = limits["limits"] as? [Any] ?? []
        // SDK get_usage uses model_scoped/utilization rather than limits/percent.
        for item in (limits["model_scoped"] as? [Any] ?? []).prefix(200) {
            guard let row = item as? [String: Any], let name = row["display_name"] as? String else { continue }
            rows.append([
                "kind": "weekly_scoped", "scope": ["model": ["display_name": name]],
                "percent": row["utilization"] ?? NSNull(), "resets_at": row["resets_at"] ?? NSNull()
            ])
        }
        limits["limits"] = rows
        let parsed = try ClaudeOAuthUsageProvider.parse(limits, now: now)
        let benefits = parsed.claudeBenefits
        return QuotaSnapshot(
            provider: .anthropic, windows: parsed.windows,
            plan: payload["subscription_type"] as? String, fetchedAt: now,
            claudeBenefits: benefits?.resets != nil || benefits?.cloudCredits != nil
                ? benefits : .cliUnavailable
        )
    }
}

struct ClaudeUsageControlSession {
    enum Event { case ignore, requestUsage, usage([String: Any]) }
    private var initialized = false
    var initializeRequest: [String: Any] {
        ["type": "control_request", "request_id": "usagebar-initialize",
         "request": ["subtype": "initialize", "hooks": [:], "sdkMcpServers": []] as [String: Any]]
    }
    var usageRequest: [String: Any] {
        ["type": "control_request", "request_id": "usagebar-usage",
         "request": ["subtype": "get_usage", "skip_behaviors": true] as [String: Any]]
    }
    mutating func receive(_ object: [String: Any]) throws -> Event {
        if object["type"] as? String == "control_request" {
            throw UsageProviderError.unsupported("Claude Code가 사용량 조회 외의 요청을 보냈습니다.")
        }
        guard object["type"] as? String == "control_response",
              let response = object["response"] as? [String: Any],
              let id = response["request_id"] as? String,
              ["usagebar-initialize", "usagebar-usage"].contains(id) else { return .ignore }
        guard response["subtype"] as? String == "success" else {
            throw UsageProviderError.unsupported("설치된 Claude Code가 사용량 조회 요청을 처리하지 못했습니다.")
        }
        if id == "usagebar-initialize", !initialized {
            initialized = true
            return .requestUsage
        }
        guard initialized, id == "usagebar-usage",
              let payload = response["response"] as? [String: Any] else { return .ignore }
        return .usage(payload)
    }
}
