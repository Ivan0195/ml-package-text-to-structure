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
    public var isGenerating: Bool = false
    private var modelPath: String
    private var llamaState: LlamaState? = nil
    private let apiLlama = CloudLlamaAPIService()
    private var generationTask: Task<String, any Error>? = nil
    private var streamResult: Binding<String>? = nil
    
    
    public init(modelPath: String = "", streamResult: Binding<String>? = nil) async throws {
        print("init text to structure")
        self.modelPath = modelPath
        guard !modelPath.isEmpty else {
            print("modelPath is empty")
            return
        }
        self.streamResult = streamResult
    }
    
    public func generateWithScheme(prompt: String, systemPrompt: String?, grammar: String, useCloudModel: Bool = false) async throws -> String {
        isGenerating = true
        if useCloudModel {
            var grammarString: String = grammar
            if grammar.contains("containers/Bundle/Application") {
                let url = URL(filePath: grammar)
                grammarString = try! String(contentsOf: url, encoding: .utf8)
            }
            let result = try await apiLlama.generateSteps(subtitles: prompt, grammarScheme: grammarString)
            isGenerating = false
            return result
        } else {
            if streamResult == nil {
                do {
                    self.llamaState = try await LlamaState(modelUrl: modelPath, inputText: prompt)
                } catch {
                    throw error
                }
            } else {
                do {
                    self.llamaState = try await LlamaState(modelUrl: modelPath, streamResult: streamResult, inputText: prompt)
                } catch {
                    throw error
                }
            }
            self.generationTask = Task {
                var grammarString: String = grammar
                if grammar.contains("containers/Bundle/Application") {
                    let url = URL(filePath: grammar)
                    grammarString = try! String(contentsOf: url, encoding: .utf8)
                }
                let _instruction: String = "[INST]\(systemPrompt ?? "return list of instructions")[/INST] prompt"
                let result = try await llamaState?.generateWithGrammar(prompt: """
                [INST]return list of instructions[/INST]\(prompt)
            """, grammar: LlamaGrammar(grammarString)!)
                isGenerating = false
                self.llamaState = nil
                return result ?? ""
            }
            return try await self.generationTask!.value
        }
    }
    
    public func generateRaw(prompt: String, extraKnowledge: String = "", useCloudModel: Bool = false) async throws -> String {
        if useCloudModel {
            do {
                let res = try await apiLlama.generateVocabularyAPI(prompt: prompt, extraInfo: extraKnowledge)
                return res.replacingOccurrences(of: "<end>", with: "")
            } catch {
                throw LlamaError.couldNotInitializeContext
            }
        } else {
            do {
                let promptForGeneration = "<s>[INST]You are AI assistant, your name is Taqi. Answer questions. Use this helpful information to answer questions. Finish your answer with <end> tag.[/INST]\(String(describing: extraKnowledge))</s>[INST]\(prompt)[/INST]"
                if streamResult == nil {
                    do {
                        self.llamaState = try await LlamaState(modelUrl: modelPath, inputText: promptForGeneration)
                    } catch {
                        throw error
                    }
                } else {
                    do {
                        self.llamaState = try await LlamaState(modelUrl: modelPath, streamResult: streamResult, inputText: promptForGeneration)
                    } catch {
                        throw error
                    }
                }
                self.generationTask = Task {
                    let promptForGeneration = "<s>[INST]You are AI assistant, your name is Taqi. Answer questions. Use this helpful information to answer questions. Finish your answer with <end> tag.[/INST]\(String(describing: extraKnowledge))</s>[INST]\(prompt)[/INST]"
                    let result = try await llamaState?.generateRaw(prompt: promptForGeneration)
                    self.llamaState = nil
                    return result ?? "no result"
                }
                return try await self.generationTask!.value
            } catch  {
                    throw LlamaError.error(title: "Error while generation", message: "Some error occured while generation, try one more time")
            }
        }
    }
    
    public func stop () {
        self.generationTask?.cancel()
        Task { await self.llamaState?.llamaContext?.forceStop() }
    }
}
