import Foundation

/// Download state surfaced to the import/sync UI (§8: 进度/取消/重试).
enum SnapshotDownloadState: Equatable {
    case idle
    case downloading(progress: Double)   // 0…1, -1 when the size is unknown
    case failed(String)
}

/// Downloads a GitHub zipball to a temp file with progress reporting.
/// One downloader per operation; `cancel()` aborts the in-flight task and
/// `download(from:)` can be called again to retry.
final class SnapshotDownloader: NSObject, @unchecked Sendable {
    private var session: URLSession!
    private var continuation: CheckedContinuation<URL, Error>?
    private var task: URLSessionDownloadTask?
    private var targetURL: URL?

    /// UI-observable state. Updated on the main actor.
    @MainActor var onStateChange: ((SnapshotDownloadState) -> Void)?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        // Delegate queue: serial, so progress callbacks are ordered.
        session = URLSession(configuration: config, delegate: self,
                             delegateQueue: OperationQueue())
        session.delegateQueue.maxConcurrentOperationCount = 1
    }

    /// Downloads `url` (with `auth`) to a temp `.zip` file.
    /// Throws `GitHubError.cancelled` after `cancel()`.
    func download(from url: URL, auth: GitHubAuthProvider) async throws -> URL {
        // Retry support: a fresh attempt replaces any stale state.
        cleanupTarget()
        var req = URLRequest(url: url)
        req.setValue("CodeBerry-Lite/4.0", forHTTPHeaderField: "User-Agent")
        if let header = auth.authorizationHeader() {
            req.setValue(header, forHTTPHeaderField: "Authorization")
        }
        setState(.downloading(progress: -1))
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.task = self.session.downloadTask(with: req)
            self.task?.resume()
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: - Private

    private func setState(_ state: SnapshotDownloadState) {
        Task { @MainActor in self.onStateChange?(state) }
    }

    private func finish(with result: Result<URL, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        task = nil
        switch result {
        case .success(let url):
            setState(.idle)
            cont.resume(returning: url)
        case .failure(let error):
            if let urlError = error as? URLError, urlError.code == .cancelled {
                cleanupTarget()
                setState(.idle)
                cont.resume(throwing: GitHubError.cancelled)
            } else {
                cleanupTarget()
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                setState(.failed(message))
                cont.resume(throwing: error)
            }
        }
    }

    private func cleanupTarget() {
        if let targetURL { try? FileManager.default.removeItem(at: targetURL) }
        targetURL = nil
    }
}

// MARK: - URLSessionDownloadDelegate

extension SnapshotDownloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : -1
        setState(.downloading(progress: progress))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            // HTTP-level failures surface here as a small error body:
            // the zipball endpoint returns JSON errors, never a valid zip.
            if let http = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                let body = (try? String(contentsOf: location, encoding: .utf8)) ?? ""
                if http.statusCode == 401 { throw GitHubError.unauthorized }
                throw GitHubError.http(status: http.statusCode,
                                       message: String(body.prefix(200)))
            }
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent("codeberry-\(UUID().uuidString).zip")
            try FileManager.default.moveItem(at: location, to: target)
            targetURL = target
            finish(with: .success(target))
        } catch {
            finish(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(with: .failure(error)) }
    }
}
