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
    
    @Published var isGenerating = false
    private var generationTask: Task<Void, any Error>?
    public var llamaContext: LlamaContext?
    private var modelUrl: String
    init(modelUrl: String, streamResult: Binding<String>? = nil) {
        self.modelUrl = modelUrl
        do {
            self.llamaContext = try LlamaContext.createContext(path: modelUrl, stream: streamResult)
        } catch {
            print(error)
        }
    }
    
    func generateWithGrammar(prompt: String, grammar: LlamaGrammar) async throws -> String {
        guard let llamaContext else {
            throw GenerationError.noLlamaContext
        }
        self.isGenerating = true
        await llamaContext.completion_init(text: prompt)
        print("initialized")
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
            self.isGenerating = false
        }
        return result
    }
}
