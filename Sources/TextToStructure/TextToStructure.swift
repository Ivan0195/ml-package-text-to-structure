import Foundation

@available(iOS 13.0.0, *)
public class TextToStructure {
    private var systemPrompt: String
    private var grammar: String
    private var modelPath: String
    private var llamaState: LlamaState
    private var generationTask: Task<String, any Error>? = nil
    
   public init(grammar: String, modelPath: String, systemPrompt: String) async {
        self.grammar = grammar
        self.modelPath = modelPath
        self.systemPrompt = systemPrompt
        self.llamaState = await LlamaState(modelUrl: modelPath)
    }
    
    public func generate (prompt: String) async throws -> String {
        do {
            self.generationTask = Task {
                var grammarString: String = self.grammar
                if self.grammar.contains("containers/Bundle/Application") {
                    let url = URL(filePath: self.grammar)
                    grammarString = try! String(contentsOf: url, encoding: .utf8)
                }
                let result = try! await llamaState.generateWithGrammar(prompt: "\(prompt)", grammar: LlamaGrammar(grammarString)!)
                return result
            }
            return try! await self.generationTask!.value
        } catch {
            print("generation stopped")
        }
    }
    
    private func stopGeneration () async {
        self.generationTask?.cancel()
        await llamaState.llamaContext?.forceStop()
    }
}
