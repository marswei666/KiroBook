import Foundation

struct CheckSubscriptionResponse: Decodable {
    var success: Bool = false
    var tier: String = "free"
    var isActive: Bool = false
    var email: String = ""
    var expiresAt: String = ""
    var message: String = ""
    var mode: String = ""

    enum CodingKeys: String, CodingKey {
        case success
        case tier
        case isActive
        case email
        case expiresAt
        case message
        case mode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        tier = try container.decodeIfPresent(String.self, forKey: .tier) ?? "free"
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? ""
    }
}

struct RecordTransactionResponse: Decodable {
    var success: Bool = false
    var message: String = ""
}

final class SubscriptionApiService {
    private let baseURL = "https://wanderlog-stats-d4fnpamqed206c68-1445354193.ap-shanghai.app.tcloudbase.com"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private var mode: String {
        #if DEBUG
        "test"
        #else
        "live"
        #endif
    }

    func checkSubscription(userUUID: String) async throws -> CheckSubscriptionResponse {
        try await post(
            path: "/checkSubscription",
            body: [
                "userUUID": userUUID,
                "mode": mode
            ]
        )
    }

    func recordTransaction(
        userUUID: String,
        source: String,
        eventType: String,
        tier: SubscriptionTier,
        amount: Int,
        currency: String,
        transactionId: String
    ) async throws -> RecordTransactionResponse {
        try await post(
            path: "/recordTransaction",
            body: [
                "userUUID": userUUID,
                "source": source,
                "eventType": eventType,
                "tier": tier.id,
                "amount": amount,
                "currency": currency,
                "transactionId": transactionId,
                "mode": mode
            ]
        )
    }

    private func post<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SubscriptionApiService", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"
            ])
        }
        return try decoder.decode(T.self, from: data)
    }
}
