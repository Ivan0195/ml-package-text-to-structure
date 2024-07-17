import Foundation
import llama
import SwiftUI
import LlamaHelpers
import Combine

@available(iOS 13.0.0, *)

public struct StepsJSON: Codable {
    public var steps: [GeneratedStep]
}
public struct StepsJSONWithoutNotes: Codable {
    public var steps: [GeneratedStepWithoutDescription]
}
public struct GeneratedStep: Codable {
    public var step_name: String
    public var step_description: String?
}

public struct GeneratedStepWithoutDescription: Codable {
    public var step_short_description: String
}

public class TextToStructure {
    private var systemPrompt: String
    private var grammar: String
    private var modelPath: String
    private var llamaState: LlamaState? = nil
    private var generationTask: Task<String, any Error>? = nil
    private var observer: NSObjectProtocol? = nil
    private var isMemoryOut: Bool = false
    private let apiLlama = CloudLlamaAPIService()
    @MainActor
    public init(grammar: String = "", modelPath: String = "", systemPrompt: String = "", streamResult: Binding<String>? = nil, inputText: String) async throws {
        print("init text to structure")
        self.grammar = grammar
        self.modelPath = modelPath
        self.systemPrompt = systemPrompt
        guard !modelPath.isEmpty else { return }
        if streamResult == nil {
            do {
                self.llamaState = try LlamaState(modelUrl: modelPath, inputText: inputText)
            } catch {
                throw error
            }
        } else {
            do {
                self.llamaState = try LlamaState(modelUrl: modelPath, streamResult: streamResult, inputText: inputText)
            } catch {
                throw error
            }
        }
    }
    
    deinit {
        print("deinit TextToStructure instance")
    }
    
    public func generate (prompt: String) async throws -> String {
        do {
            guard !grammar.isEmpty else { throw LlamaError.invalidJSONScheme }
            self.generationTask = Task(priority: .background) {
                var grammarString: String = self.grammar
                if self.grammar.contains("containers/Bundle/Application") {
                    let url = URL(filePath: self.grammar)
                    grammarString = try! String(contentsOf: url, encoding: .utf8)
                }
                let result = try await llamaState?.generateWithGrammar(prompt: """
                    [INST]return list of instructions[/INST]\(prompt)
                """, grammar: LlamaGrammar(grammarString)!)
                return result ?? ""
            }
            return try await self.generationTask!.value
        } catch  {
            if isMemoryOut {
                throw LlamaError.outOfMemory
            } else {
                throw LlamaError.error(title: "Error while generation", message: "Some error occured while generation, try one more time")
            }
        }
    }
    
    public func rawCloudGeneration (prompt: String, extraInfo: String) async throws -> String {
        var answer: String = "default string"
        do {
            let res = try await apiLlama.generateVocabularyAPI(prompt: prompt, extraInfo: extraInfo)
            return res.replacingOccurrences(of: "<end>", with: "")
        } catch {
            throw LlamaError.couldNotInitializeContext
        }
    }
    
    public func generateRaw (prompt: String, extraKnowledge: String? = "") async throws -> String {
        do {
            self.generationTask = Task {
                let result = try await llamaState?.generateRaw(prompt: "<s>[INST]You are AI assistant, your name is Taqi. Answer questions. Use this helpful information to answer questions. Finish your answer with <end> tag.[/INST]\(String(describing: extraKnowledge))</s>[INST]\(prompt)[/INST]")
                return result ?? ""
            }
            return try await self.generationTask!.value
        } catch  {
            if isMemoryOut {
                throw LlamaError.outOfMemory
            } else {
                throw LlamaError.error(title: "Error while generation", message: "Some error occured while generation, try one more time")
            }
        }
    }
    
    public func stop () {
        self.generationTask?.cancel()
        Task { await self.llamaState?.llamaContext?.forceStop() }
        //NotificationCenter.default.removeObserver(observer)
    }
}
