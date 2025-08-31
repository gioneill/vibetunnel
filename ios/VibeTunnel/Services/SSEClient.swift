import Foundation

private let logger = Logger(category: "SSEClient")

/// Server-Sent Events (SSE) client for real-time terminal output streaming.
///
/// SSEClient handles the text-based streaming protocol used by the VibeTunnel server
/// to send terminal output in real-time. It parses the event stream format and
/// provides decoded events to a delegate.
final class SSEClient: NSObject, @unchecked Sendable {
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private let url: URL
    private var buffer = Data()
    private var firstOutputLogged = false
    weak var delegate: SSEClientDelegate?
    private weak var authenticationService: AuthenticationService?

    /// Events received from the SSE stream
    enum SSEEvent {
        case connected
        case terminalOutput(timestamp: Double, type: String, data: String)
        case exit(exitCode: Int, sessionId: String)
        case error(String)
    }

    init(url: URL, authenticationService: AuthenticationService? = nil) {
        self.url = url
        self.authenticationService = authenticationService
        super.init()

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 0 // No timeout for SSE
        configuration.timeoutIntervalForResource = 0
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }

    @MainActor
    func start() {
        var requestURL = url
        if let token = authenticationService?.getTokenForQuery() {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var queryItems = components?.queryItems ?? []
            queryItems.append(URLQueryItem(name: "token", value: token))
            components?.queryItems = queryItems
            if let urlWithToken = components?.url {
                requestURL = urlWithToken
            }
        }

        var request = URLRequest(url: requestURL)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        logger.info("SSE: Starting stream to \(maskURL(requestURL))")
        task = session?.dataTask(with: request)
        task?.resume()
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func processBuffer() {
        guard let string = String(data: buffer, encoding: .utf8) else { return }

        let events = string.components(separatedBy: "\n\n")

        if !string.hasSuffix("\n\n") && events.count > 1 {
            if let lastEvent = events.last, let lastEventData = lastEvent.data(using: .utf8) {
                buffer = lastEventData
            }
        } else {
            buffer = Data()
        }

        for (index, eventString) in events.enumerated() {
            if index == events.count - 1 && !buffer.isEmpty {
                continue
            }

            if !eventString.isEmpty {
                processEvent(eventString)
            }
        }
    }

    private func processEvent(_ eventString: String) {
        var eventType: String?
        var eventData: String?

        let lines = eventString.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("event:") {
                eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if eventData == nil {
                    eventData = data
                } else {
                    eventData = (eventData ?? "") + "\n" + data
                }
            }
        }

        if eventType == "message" || eventType == nil, let data = eventData {
            logger.verbose("SSE: Event type=\(eventType ?? "message"), dataLen=\(data.count)")
            parseTerminalData(data)
        }
    }

    private func parseTerminalData(_ data: String) {
        guard let jsonData = data.data(using: .utf8) else { return }

        do {
            if let array = try JSONSerialization.jsonObject(with: jsonData) as? [Any] {
                if array.count >= 3 {
                    if let firstElement = array[0] as? String, firstElement == "exit",
                       let exitCode = array[1] as? Int,
                       let sessionId = array[2] as? String
                    {
                        delegate?.sseClient(self, didReceiveEvent: .exit(exitCode: exitCode, sessionId: sessionId))
                    }
                    else if let timestamp = array[0] as? Double,
                            let type = array[1] as? String,
                            let outputData = array[2] as? String
                    {
                        if type == "o" && !firstOutputLogged {
                            firstOutputLogged = true
                            logger.info("SSE: First output received (len=\(outputData.count)) preview=\(outputData.prefix(80))")
                        }
                        delegate?.sseClient(
                            self,
                            didReceiveEvent: .terminalOutput(timestamp: timestamp, type: type, data: outputData)
                        )
                    }
                }
            }
        } catch {
            logger.error("Failed to parse event data: \(error)")
        }
    }

    deinit {
        stop()
    }
}

// MARK: - URLSessionDataDelegate

extension SSEClient: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("SSE: Not an HTTP response")
            completionHandler(.cancel)
            return
        }

        logger.info("SSE: Received response with status \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 200 {
            logger.info("SSE: Connection established successfully")
            // Notify delegate that connection is established
            delegate?.sseClient(self, didReceiveEvent: .connected)
            completionHandler(.allow)
        } else {
            logger.error("SSE: Connection failed with status \(httpResponse.statusCode)")
            delegate?.sseClient(self, didReceiveEvent: .error("HTTP \(httpResponse.statusCode)"))
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        logger.debug("SSE: Received \(data.count) bytes of data")
        buffer.append(data)
        processBuffer()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            // Check if this is a URLError directly
            if let urlError = error as? URLError, urlError.code != .cancelled {
                delegate?.sseClient(self, didReceiveEvent: .error(error.localizedDescription))
            } else if (error as? URLError) == nil {
                // Not a URLError, so it's some other error we should report
                delegate?.sseClient(self, didReceiveEvent: .error(error.localizedDescription))
            }
        }
    }
}

// MARK: - SSEClientDelegate

protocol SSEClientDelegate: AnyObject {
    func sseClient(_ client: SSEClient, didReceiveEvent event: SSEClient.SSEEvent)
}

// MARK: - Utilities

private func maskURL(_ url: URL) -> String {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return url.absoluteString
    }
    if let items = components.queryItems {
        components.queryItems = items.map { item in
            if item.name.lowercased() == "token" { return URLQueryItem(name: item.name, value: "***") }
            return item
        }
    }
    return components.url?.absoluteString ?? url.absoluteString
}
