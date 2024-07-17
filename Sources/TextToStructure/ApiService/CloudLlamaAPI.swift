import Foundation

struct VocabulareRequestPayload: Codable {
    let prompt: String
    let extraInfo: String
    
    init(prompt: String, extraInfo: String) {
        self.prompt = prompt
        self.extraInfo = extraInfo
    }
}

struct APIRequest: Codable {
    let data: VocabulareRequestPayload
    let service: String
}


struct APIResponse: Codable {
    let response: String
}

class CloudLlamaAPIService {
    
    func generateVocabularyAPI(prompt: String, extraInfo: String) async throws -> String {
        let url = URL(string: "https://pleasant-bluejay-next.ngrok-free.app/mistral/manifestMaker/generateVocabulary")!
        var request = URLRequest(url: url)
        let json: [String: String] = ["prompt": prompt, "extraInfo": extraInfo]
        let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        print("JSONBODY:     ",jsonData)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        print("send Request")
        let answer = String(decoding: data, as: UTF8.self)
        return answer ?? "new string"
    }
}
