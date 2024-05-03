import Foundation
import llama
import SwiftUI

@available(iOS 13.0.0, *)
@MainActor
public class TextToStructure {
    private var systemPrompt: String
    private var grammar: String
    private var modelPath: String
    private var llamaState: LlamaState
    private var generationTask: Task<String, any Error>? = nil
    @MainActor
    public init(grammar: String, modelPath: String, systemPrompt: String, streamResult: Binding<String>? = nil) async {
        self.grammar = grammar
        self.modelPath = modelPath
        self.systemPrompt = systemPrompt
        if streamResult == nil {
            self.llamaState = LlamaState(modelUrl: modelPath)
        } else {
            self.llamaState = LlamaState(modelUrl: modelPath, streamResult: streamResult)
        }
    }
    
    public func generate (prompt: String) async throws -> String {
        do {
            self.generationTask = Task {
                var grammarString: String = self.grammar
                if self.grammar.contains("containers/Bundle/Application") {
                    let url = URL(filePath: self.grammar)
                    grammarString = try! String(contentsOf: url, encoding: .utf8)
                }
                let result = try await llamaState.generateWithGrammar(prompt: "\(prompt)", grammar: LlamaGrammar(grammarString)!)
                return result
            }
            return try await self.generationTask!.value
        } catch {
            print("generation stopped")
            return ""
        }
    }
}
