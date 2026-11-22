// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit
import os.lock

public struct ExtractedMediaItem: Codable, Sendable, Identifiable {
    public let id: UUID
    public let url: URL
    public let type: String
    public let name: String

    public init(id: UUID = UUID(), url: URL, type: String, name: String) {
        self.id = id
        self.url = url
        self.type = type
        self.name = name
    }
}

public final class MediaBatchDownloaderEngine: @unchecked Sendable {
    public static let shared = MediaBatchDownloaderEngine()

    private var lock = os_unfair_lock()
    private let session = URLSession(configuration: .default)

    private init() {
        let dir = downloadDirectoryURL
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public var downloadDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Downloads", isDirectory: true)
    }

    public func extractMediaItems(from webView: WKWebView) async -> [ExtractedMediaItem] {
        let js = """
        (function() {
            var items = [];
            var seen = new Set();

            function add(url, type) {
                if (!url || seen.has(url)) return;
                try {
                    var full = new URL(url, document.baseURI).href;
                    if (full.startsWith('http://') || full.startsWith('https://')) {
                        seen.add(full);
                        items.push({ url: full, type: type });
                    }
                } catch(e) {}
            }

            document.querySelectorAll('video, video source').forEach(function(el) {
                add(el.src || el.getAttribute('src'), 'video');
            });

            document.querySelectorAll('audio, audio source').forEach(function(el) {
                add(el.src || el.getAttribute('src'), 'audio');
            });

            document.querySelectorAll('img').forEach(function(el) {
                add(el.currentSrc || el.src || el.getAttribute('src'), 'image');
            });

            document.querySelectorAll('a[href]').forEach(function(el) {
                var h = el.getAttribute('href') || '';
                if (h.match(/\\.(mp4|m3u8|webm|mp3|wav|flac|png|jpg|jpeg|gif|webp|pdf)$/i)) {
                    add(h, 'link');
                }
            });

            return JSON.stringify(items);
        })();
        """

        let result = try? await webView.evaluateJavaScript(js)
        guard let jsonString = result as? String,
              let data = jsonString.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return []
        }

        return array.compactMap { dict in
            guard let urlStr = dict["url"], let url = URL(string: urlStr), let type = dict["type"] else { return nil }
            let filename = url.lastPathComponent.isEmpty ? "\(UUID().uuidString).dat" : url.lastPathComponent
            return ExtractedMediaItem(url: url, type: type, name: filename)
        }
    }

    public func downloadItem(_ item: ExtractedMediaItem) async throws -> URL {
        let (tempURL, response) = try await session.download(from: item.url)
        let suggestedName = response.suggestedFilename ?? item.name
        let destURL = downloadDirectoryURL.appendingPathComponent(suggestedName)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        return destURL
    }

    public func archivePageAsPDF(from webView: WKWebView, filename: String = "WebArchive_\(Date().timeIntervalSince1970).pdf") async throws -> URL {
        let destURL = downloadDirectoryURL.appendingPathComponent(filename)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let config = WKPDFConfiguration()
                webView.createPDF(configuration: config) { result in
                    switch result {
                    case .success(let data):
                        do {
                            try data.write(to: destURL, options: .atomic)
                            continuation.resume(returning: destURL)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
