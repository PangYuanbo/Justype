import Foundation

enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case badResponse(Int, String)
    case decoding
    case empty

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:        return "API Key 未配置"
        case .invalidURL:           return "Base URL 无效"
        case .badResponse(let c, let m): return "HTTP \(c): \(m)"
        case .decoding:             return "返回解析失败"
        case .empty:                return "返回为空"
        }
    }
}

final class LLMClient {
    static let shared = LLMClient()

    static let systemPrompt = """
    The input is a raw stream of keystrokes the user typed directly on the keyboard, without any IME or autocorrect in between. It usually has no punctuation, no word boundaries, no casing, and may contain typos, missing letters, or run-on tokens. It represents what the user wants to express, written in the "naked" keyboard form that an IME would normally turn into the final text.

    A screenshot of the user's current screen may also be attached. Use it ONLY as context to help understand what the user is trying to write — for example: which app they're in, the language of the surrounding text, the cursor's neighborhood, technical terms or names visible on screen. Do NOT transcribe or describe the screenshot, and do NOT insert content from it. The output must come only from converting the typed keystrokes.

    Your job is to infer the final text the user intended and output exactly that, ready to be inserted into a text field.

    Rules:
    1. Output only the final text. No quotes, no explanation, no markdown, no prefix or suffix.
    2. Preserve the user's meaning. Do not rephrase, expand, summarize, or substitute synonyms. Only resolve the keyboard form into the proper written form.
    3. Parts that are already correct (in any language or script) must be kept as-is.
    4. Insert punctuation, casing, spacing, and script characters as a normal native writer would, based on what the user obviously meant — but do not add content the user did not express.
    5. If the input is already correct and complete, return it unchanged.

    Examples:
    leisi de renwu → 类似的任务
    wo yao yong python xie ge script → 我要用 Python 写个 script
    konnichiwa sekai → こんにちは世界
    annyeonghaseyo → 안녕하세요
    xin chao the gioi → Xin chào thế giới
    hello world → hello world
    """

    func convert(_ raw: String, imageData: Data? = nil, prefixContext: String = "") async throws -> String {
        let state = AppState.shared
        let apiKey = state.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        let baseURL = state.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: baseURL.hasSuffix("/") ? "\(baseURL)chat/completions" : "\(baseURL)/chat/completions") else {
            throw LLMError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("https://justype.app", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("JustType", forHTTPHeaderField: "X-Title")

        // Build the text payload. If there's already-committed prefix text from
        // an earlier segment of the same session, expose it so the model knows
        // the surrounding context but only converts the trailing raw part.
        let textBody: String
        if prefixContext.isEmpty {
            textBody = raw
        } else {
            textBody = """
            ALREADY_WRITTEN: \(prefixContext)
            TO_CONVERT: \(raw)

            Output only the conversion of TO_CONVERT, written so it naturally continues ALREADY_WRITTEN. Do not repeat ALREADY_WRITTEN.
            """
        }

        // OpenAI-compatible vision format. When imageData is nil, fall back to a
        // simple string content for maximum compatibility with text-only models.
        let userContent: Any
        if let imageData = imageData {
            let base64 = imageData.base64EncodedString()
            userContent = [
                [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/jpeg;base64,\(base64)",
                        "detail": "low"
                    ]
                ],
                ["type": "text", "text": textBody]
            ] as [[String: Any]]
        } else {
            userContent = textBody
        }

        let body: [String: Any] = [
            "model": state.model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user",   "content": userContent]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw LLMError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.badResponse(http.statusCode, String(msg.prefix(300)))
        }

        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw LLMError.decoding
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMError.empty }
        return stripWrappingQuotes(trimmed)
    }

    private func stripWrappingQuotes(_ s: String) -> String {
        var t = s
        let pairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("「", "」"), ("“", "”")]
        for (a, b) in pairs where t.first == a && t.last == b && t.count >= 2 {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }
}
