import Foundation

struct ExercismAPIService: Sendable {
    enum APIError: LocalizedError {
        case invalidURL
        case decodingFailed(Error)
        case requestFailed(Int, String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Exercism API URL."
            case .decodingFailed(let error): return "Failed to decode Exercism API response: \(error.localizedDescription)"
            case .requestFailed(let statusCode, let message): return "Exercism API request failed with status \(statusCode): \(message)"
            case .networkError(let error): return "Network error connecting to Exercism: \(error.localizedDescription)"
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRustExercises(token: String) async throws -> [ExercismExercise] {
        guard let url = URL(string: "https://exercism.org/api/v2/tracks/rust/exercises") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) : (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(500, "Invalid HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(decoding: data, as: UTF8.self)
            throw APIError.requestFailed(httpResponse.statusCode, message)
        }

        do {
            let decoder = JSONDecoder()
            let decodedResponse = try decoder.decode(ExercismExercisesResponse.self, from: data)
            return decodedResponse.exercises
        } catch {
            throw APIError.decodingFailed(error)
        }
    }
}
