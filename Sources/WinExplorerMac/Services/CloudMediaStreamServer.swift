import Foundation
import AppKit

public struct CloudStreamItem {
    public let id: String
    public let remoteURL: URL
    public let authBase64: String
    public let userAgent: String
    public let filename: String
    public let registeredAt: Date
}

public final class CloudMediaStreamServer: NSObject {
    public static let shared = CloudMediaStreamServer()

    private var serverSocket: Int32 = -1
    private(set) var port: Int = 0
    private let queue = DispatchQueue(label: "com.winexplorermac.mediastreamer", qos: .userInitiated, attributes: .concurrent)
    private var streams: [String: CloudStreamItem] = [:]
    private let lock = NSLock()
    private var isRunning = false

    private override init() {
        super.init()
        startServer()
    }

    deinit {
        stopServer()
    }

    public func startServer() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return }

        // Ignore SIGPIPE globally so closed client sockets never crash the process
        signal(SIGPIPE, SIG_IGN)

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return }

        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // Dynamic port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindRes == 0 else {
            Darwin.close(sock)
            return
        }

        guard Darwin.listen(sock, 64) == 0 else {
            Darwin.close(sock)
            return
        }

        var assignedAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameRes = withUnsafeMutablePointer(to: &assignedAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.getsockname(sock, sockPtr, &addrLen)
            }
        }
        guard nameRes == 0 else {
            Darwin.close(sock)
            return
        }

        self.serverSocket = sock
        self.port = Int(UInt16(bigEndian: assignedAddr.sin_port))
        self.isRunning = true

        queue.async { [weak self] in
            self?.acceptLoop(sock)
        }
    }

    public func stopServer() {
        lock.lock()
        defer { lock.unlock() }
        isRunning = false
        if serverSocket >= 0 {
            Darwin.close(serverSocket)
            serverSocket = -1
        }
    }

    public func register(item: FileItem, remoteURL: URL, authBase64: String, userAgent: String) -> URL {
        lock.lock()
        defer { lock.unlock() }

        if serverSocket < 0 || !isRunning {
            startServer()
        }

        let token = UUID().uuidString.prefix(8).lowercased()
        let streamItem = CloudStreamItem(
            id: String(token),
            remoteURL: remoteURL,
            authBase64: authBase64,
            userAgent: userAgent,
            filename: item.name,
            registeredAt: Date()
        )
        streams[String(token)] = streamItem

        // Clean up items older than 2 hours
        let cutoff = Date().addingTimeInterval(-7200)
        streams = streams.filter { $0.value.registeredAt > cutoff }

        let ext = item.fileExtension.isEmpty ? "mp4" : item.fileExtension
        let safeName = item.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "video.\(ext)"
        return URL(string: "http://127.0.0.1:\(port)/stream/\(token)/\(safeName)")!
    }

    public func openInVideoPlayer(streamURL: URL, withApplication appURL: URL?) -> Bool {
        // 1. If QuickTime Player or nil, use native AppleScript open URL
        let isQuickTime = appURL == nil || appURL?.lastPathComponent.lowercased().contains("quicktime") == true
        if isQuickTime {
            let script = """
            tell application "QuickTime Player"
                activate
                open URL "\(streamURL.absoluteString)"
            end tell
            """
            var errorInfo: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&errorInfo)
                if errorInfo == nil {
                    return true
                }
            }
        }

        // 2. If specific app or AppleScript failed, open via NSWorkspace
        let targetApp = appURL ?? NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: "/tmp/dummy.mp4"))
        if let targetApp {
            let config = NSWorkspace.OpenConfiguration()
            var opened = false
            let sema = DispatchSemaphore(value: 0)
            NSWorkspace.shared.open([streamURL], withApplicationAt: targetApp, configuration: config) { _, error in
                opened = (error == nil)
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 2.0)
            if opened { return true }
        }

        // 3. Fallback: default handler for http URLs
        return NSWorkspace.shared.open(streamURL)
    }

    private func acceptLoop(_ sock: Int32) {
        while isRunning {
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.accept(sock, sockPtr, &clientLen)
                }
            }

            guard clientFd >= 0 else {
                if !isRunning { break }
                usleep(50_000)
                continue
            }

            var nosig: Int32 = 1
            setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))

            queue.async { [weak self] in
                self?.handleClient(clientFd)
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = Darwin.recv(fd, &buffer, buffer.count - 1, 0)
        guard bytesRead > 0 else {
            Darwin.close(fd)
            return
        }

        buffer[bytesRead] = 0
        guard let requestString = String(bytes: buffer[0..<bytesRead], encoding: .utf8) else {
            Darwin.close(fd)
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        guard let reqLine = lines.first else {
            Darwin.close(fd)
            return
        }
        let reqParts = reqLine.components(separatedBy: " ")
        guard reqParts.count >= 2, reqParts[0] == "GET" || reqParts[0] == "HEAD" else {
            Darwin.close(fd)
            return
        }

        let reqPath = reqParts[1]
        let isHead = (reqParts[0] == "HEAD")

        // Parse path: /stream/<token>/<filename>
        let pathComponents = reqPath.split(separator: "/").map(String.init)
        guard pathComponents.count >= 2, pathComponents[0] == "stream" else {
            send404(fd: fd)
            Darwin.close(fd)
            return
        }

        let token = pathComponents[1]
        lock.lock()
        let streamItem = streams[token]
        lock.unlock()

        guard let item = streamItem else {
            send404(fd: fd)
            Darwin.close(fd)
            return
        }

        // Extract Range header if present
        var rangeHeader: String?
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("range:") {
                let rangeVal = line.dropFirst("range:".count).trimmingCharacters(in: .whitespaces)
                if !rangeVal.isEmpty {
                    rangeHeader = rangeVal
                }
                break
            }
        }

        // Create async streaming connection (NEVER blocks GCD threads with semaphores)
        var req = URLRequest(url: item.remoteURL, timeoutInterval: 60)
        req.httpMethod = isHead ? "HEAD" : "GET"
        req.setValue("Basic \(item.authBase64)", forHTTPHeaderField: "Authorization")
        req.setValue(item.userAgent, forHTTPHeaderField: "User-Agent")
        if let range = rangeHeader {
            req.setValue(range, forHTTPHeaderField: "Range")
        }

        let connection = StreamProxyConnection(clientFd: fd, isHead: isHead)
        connection.start(request: req)
    }

    private func send404(fd: Int32) {
        let resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        if let d = resp.data(using: .utf8) {
            d.withUnsafeBytes { ptr in
                _ = Darwin.send(fd, ptr.baseAddress, ptr.count, 0)
            }
        }
    }
}

// MARK: - Fully Non-Blocking Streaming Proxy Connection
private final class StreamProxyConnection: NSObject, URLSessionDataDelegate {
    private var clientFd: Int32
    private let isHead: Bool
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var headersSent = false
    private var isClosed = false
    private let lock = NSLock()
    private var retainCycle: StreamProxyConnection?

    init(clientFd: Int32, isHead: Bool) {
        self.clientFd = clientFd
        self.isHead = isHead
        super.init()
    }

    func start(request: URLRequest) {
        // Retain self while stream connection is active
        self.retainCycle = self

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 86400
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        self.session = s
        let t = s.dataTask(with: request)
        self.task = t
        t.resume()
    }

    private func closeSocketAndFinish() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        isClosed = true
        let fd = clientFd
        clientFd = -1
        let s = session
        session = nil
        let t = task
        task = nil
        lock.unlock()

        t?.cancel()
        s?.finishTasksAndInvalidate()
        if fd >= 0 {
            Darwin.close(fd)
        }
        DispatchQueue.main.async { [weak self] in
            self?.retainCycle = nil
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            closeSocketAndFinish()
            return
        }

        let status = http.statusCode
        let statusText = status == 206 ? "Partial Content" : (status == 200 ? "OK" : "Error")
        var headerOut = "HTTP/1.1 \(status) \(statusText)\r\n"
        headerOut += "Server: WinExplorerMac-Streamer\r\n"
        headerOut += "Accept-Ranges: bytes\r\n"
        headerOut += "Connection: close\r\n"

        for (k, v) in http.allHeaderFields {
            if let ks = k as? String, let vs = v as? String {
                let lower = ks.lowercased()
                if lower == "content-type" || lower == "content-range" || lower == "content-length" {
                    headerOut += "\(ks): \(vs)\r\n"
                }
            }
        }
        headerOut += "\r\n"

        lock.lock()
        let fd = clientFd
        lock.unlock()

        guard fd >= 0 else {
            completionHandler(.cancel)
            closeSocketAndFinish()
            return
        }

        if let hData = headerOut.data(using: .utf8) {
            let sent = hData.withUnsafeBytes { ptr in
                Darwin.send(fd, ptr.baseAddress, ptr.count, 0)
            }
            if sent <= 0 {
                completionHandler(.cancel)
                closeSocketAndFinish()
                return
            }
        }

        headersSent = true

        if isHead {
            completionHandler(.cancel)
            closeSocketAndFinish()
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isHead, headersSent else { return }

        lock.lock()
        let fd = clientFd
        lock.unlock()

        guard fd >= 0 else {
            closeSocketAndFinish()
            return
        }

        let sent = data.withUnsafeBytes { ptr in
            Darwin.send(fd, ptr.baseAddress, ptr.count, 0)
        }

        // If client closed socket or aborted (e.g. QuickTime seeking to another timestamp), cancel immediately!
        if sent <= 0 {
            closeSocketAndFinish()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        closeSocketAndFinish()
    }
}
