import Foundation
import llama
import SwiftUI
import LlamaHelpers
import Combine

@available(iOS 13.0.0, *)
//
//public struct StepsJSON: Codable {
//    public var steps: [GeneratedStep]
//}
//public struct GeneratedStep: Codable {
//    public var step_name: String
//    public var step_description: String?
//}

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
    private let apiLlama = CloudLlamaAPIService()
    @MainActor
    public init(grammar: String = "", modelPath: String = "", systemPrompt: String = "", streamResult: Binding<String>? = nil, inputText: String) async throws {
        print("init text to structure")
        self.grammar = grammar
        self.modelPath = modelPath
        self.systemPrompt = systemPrompt
        guard !modelPath.isEmpty else {
            print("modelPath is empty")
            return
        }
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
    
    public func generate (prompt: String) async throws -> String {
        do {
            print("inside generate function")
            print(grammar)
            guard !grammar.isEmpty else { throw LlamaError.invalidJSONScheme }
            self.generationTask = Task(priority: .background) {
                print(llamaState)
                if llamaState == nil {
                    print("usingCloudGeneration")
//                    var result = try await apiLlama.generateSteps(subtitles: prompt, withDescription: true)
//                    print(result)
//                    return result
                    return ""
                } else {
                    print("trying to use local instead of cloud")
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
            }
            return try await self.generationTask!.value
        } catch  {
                throw LlamaError.error(title: "Error while generation", message: "Some error occured while generation, try one more time")
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
                throw LlamaError.error(title: "Error while generation", message: "Some error occured while generation, try one more time")
        }
    }
    
    public func stop () {
        self.generationTask?.cancel()
        Task { await self.llamaState?.llamaContext?.forceStop() }
    }
}

public class NewTextToStructure {
    public var isGenerating: Bool = false
    private var modelPath: String
    private var llamaState: LlamaState? = nil
    private let apiLlama = CloudLlamaAPIService()
    private var generationTask: Task<String, any Error>? = nil
    
    @MainActor
    public init(modelPath: String = "", streamResult: Binding<String>? = nil, inputText: String) async throws {
        print("init text to structure")
        self.modelPath = modelPath
        guard !modelPath.isEmpty else {
            print("modelPath is empty")
            return
        }
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
    
    public func generateWithScheme(prompt: String, systemPrompt: String?, grammar: String, useLocalModel: Bool = true) async throws -> String {
        isGenerating = true
        var grammarString: String = grammar
        if grammar.contains("containers/Bundle/Application") {
            let url = URL(filePath: grammar)
            grammarString = try! String(contentsOf: url, encoding: .utf8)
        }
        if !useLocalModel {
            var result = try await apiLlama.generateSteps(subtitles: prompt, grammarScheme: grammar)
            isGenerating = true
            return result
        } else {
            let instruction: String = "[INST]\(systemPrompt ?? "return list of instructions")[/INST] prompt"
            let result = try await llamaState?.generateWithGrammar(prompt: """
                [INST]return list of instructions[/INST]\(prompt)
            """, grammar: LlamaGrammar(grammarString)!)
            isGenerating = true
            return result ?? ""
        }
    }
    
    public func generateRaw(prompt: String, extraKnowledge: String = "", useLocalModel: Bool = true) async throws -> String {
        if useLocalModel {
            do {
                self.generationTask = Task {
                    let result = try await llamaState?.generateRaw(prompt: "<s>[INST]You are AI assistant, your name is Taqi. Answer questions. Use this helpful information to answer questions. Finish your answer with <end> tag.[/INST]\(String(describing: extraKnowledge))</s>[INST]\(prompt)[/INST]")
                    return result ?? ""
                }
                return try await self.generationTask!.value
            } catch  {
                    throw LlamaError.error(title: "Error while generation", message: "Some error occured while generation, try one more time")
            }
        } else {
            do {
                let res = try await apiLlama.generateVocabularyAPI(prompt: prompt, extraInfo: extraKnowledge)
                return res.replacingOccurrences(of: "<end>", with: "")
            } catch {
                throw LlamaError.couldNotInitializeContext
            }
        }
    }
    
    public func stop () {
        self.generationTask?.cancel()
        Task { await self.llamaState?.llamaContext?.forceStop() }
    }
}
