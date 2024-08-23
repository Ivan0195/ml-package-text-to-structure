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
        let (data, response) = try await URLSession.shared.data(for: request)
        print("send Request")
        let res = response as? HTTPURLResponse
        let validStatusCodes = 200...399
        guard validStatusCodes.contains(res?.statusCode ?? 999) else {
            if res?.statusCode == 413 {
                throw LlamaError.tooLongText
            }
            throw LlamaError.couldNotInitializeContext
        }
        let answer = String(decoding: data, as: UTF8.self)
        return answer ?? "new string"
    }
    
    func generateSteps(subtitles: String, withDescription: Bool) async throws -> String {
        let url = URL(string: "https://pleasant-bluejay-next.ngrok-free.app/mistral/manifestMaker/generateSteps")!
        var request = URLRequest(url: url)
        let json: [String: Any] = ["subtitles": subtitles, "withDescription": withDescription]
        let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        print("send Request")
        let res = response as? HTTPURLResponse
        let validStatusCodes = 200...399
        guard validStatusCodes.contains(res?.statusCode ?? 999) else {
            if res?.statusCode == 413 {
                throw LlamaError.tooLongText
            }
            throw LlamaError.couldNotInitializeContext
        }
        let answer = String(decoding: data, as: UTF8.self)
        return answer ?? "new string"
    }
}
