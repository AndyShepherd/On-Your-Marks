// Sources/Document/FileWatcher.swift
import Foundation
import CryptoKit

final class FileWatcher {
    private let url: URL
    private var knownHash: String
    private let onChange: (String) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var debounceWork: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.15 // 150ms

    init(url: URL, knownHash: String, onChange: @escaping (String) -> Void) {
        self.url = url
        self.knownHash = knownHash
        self.onChange = onChange
    }

    func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.handleFileEvent()
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        source.resume()
    }

    func stop() {
        debounceWork?.cancel()
        source?.cancel()
        source = nil
    }

    func updateKnownHash(_ hash: String) {
        knownHash = hash
    }

    private func handleFileEvent() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.checkForChange()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: work
        )
    }

    private func checkForChange() {
        guard let newHash = Self.sha256(of: url) else {
            onChange("")
            return
        }

        if newHash != knownHash {
            knownHash = newHash
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                onChange(content)
            }
        }
    }

    // MARK: - Static Helpers

    static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
