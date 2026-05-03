import Foundation

/// Minimal OpenAI-compatible chat-completions client used by the IME.
/// Reads `Base URL`, `API Key`, and `Model` from the same UserDefaults
/// suite the main JustType app writes to, so settings stay in sync.
enum IMELLMClient {
    enum ClientError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case http(Int, String)
        case decoding
        case empty

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:      return "API key not set"
            case .invalidURL:         return "Invalid Base URL"
            case .http(let c, let m): return "HTTP \(c): \(m)"
            case .decoding:           return "Failed to parse response"
            case .empty:              return "Empty response"
            }
        }
    }

    private static let systemPrompt = """
    The input is a raw stream of keystrokes the user typed without an IME or autocorrect. It usually has no punctuation, no word boundaries, no casing, and may contain typos. Output the final text the user intended — exactly that, ready to insert into a text field.

    Rules:
    1. Output only the final text. No quotes, no explanation, no markdown.
    2. Preserve meaning. Don't rephrase, expand, or summarize.
    3. Parts already correct in any language must be kept as-is.
    4. Insert punctuation, casing, spacing, and script characters as a native writer would, but only what the user obviously meant.
    5. If the input is already correct, return it unchanged.

    Examples:
    leisi de renwu → 类似的任务
    wo yao yong python xie ge script → 我要用 Python 写个 script
    konnichiwa sekai → こんにちは世界
    annyeonghaseyo → 안녕하세요
    hello world → hello world
    """

    static func convert(_ raw: String) async throws -> String {
        let defaults = UserDefaults.standard
        let baseURL = (defaults.string(forKey: "jt.baseURL") ?? "https://openrouter.ai/api/v1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey  = (defaults.string(forKey: "jt.apiKey") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model   = (defaults.string(forKey: "jt.model") ?? "google/gemini-2.5-flash")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !apiKey.isEmpty else { throw ClientError.missingAPIKey }
        let path = baseURL.hasSuffix("/") ? "\(baseURL)chat/completions" : "\(baseURL)/chat/completions"
        guard let url = URL(string: path) else { throw ClientError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("https://justype.app", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("JustType IME", forHTTPHeaderField: "X-Title")
        req.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": raw]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ClientError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.http(http.statusCode, String(msg.prefix(200)))
        }

        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw ClientError.decoding }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClientError.empty }
        return stripWrappingQuotes(trimmed)
    }

    private static func stripWrappingQuotes(_ s: String) -> String {
        var t = s
        let pairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("「", "」"), ("\u{201C}", "\u{201D}")]
        for (a, b) in pairs where t.first == a && t.last == b && t.count >= 2 {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }
}
