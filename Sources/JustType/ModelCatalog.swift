import Foundation

/// Fetches the list of models available on the configured endpoint.
/// Works with any OpenAI-compatible `/models` endpoint (OpenRouter, OpenAI,
/// LiteLLM, vLLM, etc.) — the response shape is `{ data: [{ id, ... }] }`.
final class ModelCatalog {
    struct Model: Identifiable, Hashable {
        let id: String
        let name: String?
        let contextLength: Int?
        let supportsImage: Bool

        var displayName: String { name ?? id }
    }

    enum CatalogError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case http(Int, String)
        case decoding

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:        return L10n.errorMissingAPIKey.t
            case .invalidURL:           return L10n.errorInvalidURL.t
            case .http(let c, let m):   return L10n.httpError(c, m)
            case .decoding:             return L10n.errorParseModelList.t
            }
        }
    }

    static let shared = ModelCatalog()

    func fetch(baseURL: String, apiKey: String) async throws -> [Model] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw CatalogError.missingAPIKey }

        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = trimmedBase.hasSuffix("/")
            ? "\(trimmedBase)models"
            : "\(trimmedBase)/models"
        guard let url = URL(string: urlString) else { throw CatalogError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        req.setValue("https://justype.app", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("JustType", forHTTPHeaderField: "X-Title")
        req.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw CatalogError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw CatalogError.http(http.statusCode, String(msg.prefix(200)))
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let arr = root["data"] as? [[String: Any]]
        else { throw CatalogError.decoding }

        let models: [Model] = arr.compactMap { obj in
            guard let id = obj["id"] as? String, !id.isEmpty else { return nil }
            let name = obj["name"] as? String
            // OpenRouter exposes `context_length`; OpenAI uses `context_window`
            // on some endpoints; fall back to nil.
            let context = (obj["context_length"] as? Int)
                ?? (obj["context_window"] as? Int)
            let supportsImage = Self.detectImageSupport(obj)
            return Model(id: id, name: name, contextLength: context, supportsImage: supportsImage)
        }
        // De-dupe and stable sort.
        var seen = Set<String>()
        let unique = models.filter { seen.insert($0.id).inserted }
        return unique.sorted { lhs, rhs in
            // Image-capable models bubble up — JustType uses screen context.
            if lhs.supportsImage != rhs.supportsImage { return lhs.supportsImage }
            return lhs.id < rhs.id
        }
    }

    /// Best-effort detection of vision support across providers.
    private static func detectImageSupport(_ obj: [String: Any]) -> Bool {
        // OpenRouter: `architecture.input_modalities` is an array like ["text","image"].
        if let arch = obj["architecture"] as? [String: Any] {
            if let mods = arch["input_modalities"] as? [String] {
                if mods.contains(where: { $0.lowercased() == "image" }) { return true }
            }
            if let mods = arch["modality"] as? String {
                if mods.lowercased().contains("image") { return true }
            }
        }
        // OpenAI-style: `capabilities.vision` boolean (some compatible servers).
        if let caps = obj["capabilities"] as? [String: Any],
           let vision = caps["vision"] as? Bool, vision {
            return true
        }
        return false
    }
}
