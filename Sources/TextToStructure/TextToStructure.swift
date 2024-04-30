import Foundation

@available(iOS 13.0.0, *)
public struct TextToStructure {
    private var systemPrompt: String
    private var grammar: String
    private var modelPath: String
    private var llamaState: LlamaState
    
   public init(grammar: String, modelPath: String, systemPrompt: String) async {
        self.grammar = grammar
        self.modelPath = modelPath
        self.systemPrompt = systemPrompt
        self.llamaState = await LlamaState(modelUrl: modelPath)
    }
    
    public func generate (prompt: String) async throws -> String {
        var grammarString: String = self.grammar
        if self.grammar.contains("containers/Bundle/Application") {
            let url = URL(filePath: self.grammar)
            grammarString = try! String(contentsOf: url, encoding: .utf8)
        }
        let result = try! await llamaState.generateWithGrammar(prompt: "\(systemPrompt) from this text: \(prompt)", grammar: LlamaGrammar(grammarString)!)
        return result
    }
}
