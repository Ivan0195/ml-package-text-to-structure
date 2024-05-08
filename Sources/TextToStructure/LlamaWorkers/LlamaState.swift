import Foundation
import SwiftUI
#if os(iOS)
import class UIKit.UIDevice
#endif

enum GenerationError: Error {
    case interrupt
    case noLlamaContext
}


@MainActor
class LlamaState: ObservableObject {
    
    private var generationTask: Task<Void, any Error>?
    public var llamaContext: LlamaContext?
    private var modelUrl: String
    init(modelUrl: String, streamResult: Binding<String>? = nil) throws {
        self.modelUrl = modelUrl
        do {
            self.llamaContext = try LlamaContext.createContext(path: modelUrl, stream: streamResult)
        } catch {
            throw LlamaError.invalidModelUrl
        }
    }
    
    func generateWithGrammar(prompt: String, grammar: LlamaGrammar) async throws -> String {
        if prompt.count == 0 {
            throw LlamaError.emptyPrompt
        }
        guard let llamaContext else {
            throw GenerationError.noLlamaContext
        }
        await llamaContext.completion_init(text: prompt)
        var result = ""
        while !Task.isCancelled {
            let completion = await llamaContext.completion_loop_with_grammar(grammar: grammar)
            result.append(contentsOf: completion.piece)
            if result.contains(#/\n+/#) {
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
    }
}
