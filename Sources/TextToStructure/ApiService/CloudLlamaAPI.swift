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

struct LlamaResponse: Codable {
    let content: String
}

class CloudLlamaAPIService {
    
    func generateVocabularyAPI(prompt: String) async throws -> String {
        //let url = URL(string: "https://crucial-heron-vastly.ngrok-free.app/maker-ai-server/manifestMaker/generateVocabulary")!
        let url = URL(string: "https://crucial-heron-vastly.ngrok-free.app/maker-ai-server/completion")!
        var request = URLRequest(url: url)
        let json: [String: String] = ["prompt": prompt]
        let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        print("JSONBODY:     ",jsonData)
        request.timeoutInterval = 600
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
        let answer = try? JSONDecoder().decode(LlamaResponse.self, from: data)
        return answer?.content ?? "new string"
    }
    
    func generateSteps(prompt: String, grammar: String) async throws -> String {
        //let url = URL(string: "https://pleasant-bluejay-next.ngrok-free.app/mistral/manifestMaker/generateSteps")!
        //let url = URL(string: "https://crucial-heron-vastly.ngrok-free.app/maker-ai-server/manifestMaker/generateSteps")!
        let url = URL(string: "https://crucial-heron-vastly.ngrok-free.app/maker-ai-server/completion")!
        var request = URLRequest(url: url)
        let json: [String: Any] = ["prompt": prompt, "grammar": grammar]
        let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        request.timeoutInterval = 600
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
        let answer = try? JSONDecoder().decode(LlamaResponse.self, from: data)
        print(answer?.content.replacingOccurrences(of: "\n", with: ""))
        return answer?.content.replacingOccurrences(of: "\n", with: "") ?? "new string"
    }
}
