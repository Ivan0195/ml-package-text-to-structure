import Foundation
import SwiftUI
#if os(iOS)
import class UIKit.UIDevice
#endif

enum GenerationError: Error {
    case interrupt
    case noLlamaContext
}



class LlamaState: ObservableObject {
    
    private var generationTask: Task<Void, any Error>?
    public var llamaContext: LlamaContext?
    private var modelUrl: String
    init(modelUrl: String, streamResult: Binding<String>? = nil, inputText: String) throws {
        self.modelUrl = modelUrl
        do {
            self.llamaContext = try LlamaContext(modelPath: modelUrl, stream: streamResult, inputText: inputText)
        } catch {
            throw error
        }
    }
    
    func generateWithGrammar(prompt: String, grammar: LlamaGrammar) async throws -> String {
        guard !prompt.isEmpty else {
            throw LlamaError.tooShortText
        }
        guard let llamaContext else {
            throw GenerationError.noLlamaContext
        }
        await llamaContext.completion_init(text: prompt)
        var result = ""
        while !Task.isCancelled {
            let completion = await llamaContext.completion_loop_with_grammar(grammar: grammar)
            result.append(contentsOf: completion.piece)
            if completion.state != .normal {
                break
            }
        }
        if !Task.isCancelled {
            await llamaContext.clear()
        }
        return result
    }
    
    func generateRaw(prompt: String) async throws -> String {
            guard !prompt.isEmpty else {
                throw LlamaError.tooShortText
            }
            guard let llamaContext else {
                throw GenerationError.noLlamaContext
            }
            await llamaContext.completion_init(text: prompt)
            var result = ""
            while !Task.isCancelled {
                let completion = await llamaContext.completion_loop()
                result.append(contentsOf: completion.piece)
                if result.contains("<end>") || result.contains("</end>") {
                    break
                }
                if completion.state != .normal {
                    break
                }
            }
            if !Task.isCancelled {
                await llamaContext.clear()
            }
            return result
                .replacingOccurrences(of: "<end>", with: "")
                .replacingOccurrences(of: "</end>", with: "")
        }
}
