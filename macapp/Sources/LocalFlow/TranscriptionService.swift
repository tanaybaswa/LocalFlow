import Foundation

enum TranscriptionError: LocalizedError {
    case sidecarNotReady
    case badStatus(Int, String)
    case emptyTranscript
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .sidecarNotReady: return "Whisper sidecar is not ready yet."
        case .badStatus(let code, let body): return "Whisper HTTP \(code): \(body.prefix(200))"
        case .emptyTranscript: return "Empty transcript from Whisper."
        case .network(let err): return err.localizedDescription
        }
    }
}

struct TranscriptionService: Sendable {
    var endpoint: URL = AppPaths.inferenceEndpoint
    var language: String = "en"

    func transcribe(wavData: Data) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120

        let boundary = "LocalFlow-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"utterance.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        append("\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        append("json\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        append("\(language)\r\n")

        append("--\(boundary)--\r\n")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranscriptionError.network(error)
        }

        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.badStatus(code, body)
        }

        struct Payload: Decodable { let text: String }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let text = payload.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.emptyTranscript }
        return text
    }
}
