// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit
import os.lock

public enum AIProviderType: String, Codable, CaseIterable, Sendable {
    case openAI
    case gemini
}

public enum AIPromptTask: Sendable {
    case summarize
    case translate(targetLanguage: String)
    case questionAnswering(question: String)
    case generateElementRemover(instruction: String)
}

public final class AISummaryEngine: @unchecked Sendable {
    public static let shared = AISummaryEngine()

    private var lock = os_unfair_lock()
    private let session = URLSession(configuration: .ephemeral)

    private init() {}

    public func extractPageContent(from webView: WKWebView) async throws -> String {
        let js = """
        (function() {
            var clone = document.body ? document.body.cloneNode(true) : null;
            if (!clone) return '';
            var removeSelectors = ['script', 'style', 'noscript', 'iframe', 'svg'];
            removeSelectors.forEach(function(sel) {
                var els = clone.querySelectorAll(sel);
                for (var i = 0; i < els.length; i++) els[i].remove();
            });
            var text = clone.innerText || '';
            return text.substring(0, 16000);
        })();
        """

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                webView.evaluateJavaScript(js) { result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (result as? String) ?? "")
                    }
                }
            }
        }
    }

    public func executeTask(
        task: AIPromptTask,
        content: String,
        apiKey: String,
        provider: AIProviderType = .gemini
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "AISummaryEngine", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key is empty"])
        }

        let systemInstruction: String
        let userPrompt: String

        switch task {
        case .summarize:
            systemInstruction = "You are a concise executive assistant. Provide a clear 3-bullet-point summary of the following webpage content in the same language as the content."
            userPrompt = "Please summarize this webpage in exactly 3 bullet points:\n\n\(content)"
        case .translate(let targetLang):
            systemInstruction = "You are an expert translator. Translate the text into \(targetLang) accurately preserving meaning."
            userPrompt = "Translate the following text to \(targetLang):\n\n\(content)"
        case .questionAnswering(let question):
            systemInstruction = "You are a helpful assistant. Answer the user's question accurately based only on the provided webpage content."
            userPrompt = "Webpage content:\n\(content)\n\nQuestion: \(question)"
        case .generateElementRemover(let instruction):
            systemInstruction = "You are a CSS/JavaScript DOM expert. Generate a single CSS selector or single line of JavaScript (e.g., document.querySelectorAll('...').forEach(e => e.remove())) that eliminates the unwanted element described by the user. Respond with ONLY the executable JavaScript or CSS selector without markdown or commentary."
            userPrompt = "Element description to remove: \(instruction)"
        }

        if provider == .openAI {
            return try await callOpenAI(apiKey: apiKey, systemPrompt: systemInstruction, userPrompt: userPrompt)
        } else {
            return try await callGemini(apiKey: apiKey, systemPrompt: systemInstruction, userPrompt: userPrompt)
        }
    }

    private func callOpenAI(apiKey: String, systemPrompt: String, userPrompt: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw NSError(domain: "AISummaryEngine", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 1000,
            "temperature": 0.3
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP Error"
            throw NSError(domain: "AISummaryEngine", code: 500, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "AISummaryEngine", code: 502, userInfo: [NSLocalizedDescriptionKey: "Malformed AI response"])
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func callGemini(apiKey: String, systemPrompt: String, userPrompt: String) async throws -> String {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "AISummaryEngine", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let fullPrompt = "\(systemPrompt)\n\n\(userPrompt)"
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": fullPrompt]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 1000,
                "temperature": 0.3
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP Error"
            throw NSError(domain: "AISummaryEngine", code: 500, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw NSError(domain: "AISummaryEngine", code: 502, userInfo: [NSLocalizedDescriptionKey: "Malformed Gemini response"])
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func applyElementRemovalScript(_ scriptOrSelector: String, in webView: WKWebView) {
        let clean = scriptOrSelector.trimmingCharacters(in: .whitespacesAndNewlines)
        let js: String
        if clean.contains("document.") || clean.contains("querySelectorAll") || clean.contains("remove()") {
            js = clean
        } else {
            let escapedSelector = clean.replacingOccurrences(of: "'", with: "\\'")
            js = "document.querySelectorAll('\(escapedSelector)').forEach(function(e){ e.remove(); });"
        }

        DispatchQueue.main.async {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
