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
    private var llamaState: LlamaState
    private var generationTask: Task<String, any Error>? = nil
    private var observer: NSObjectProtocol? = nil
    private var isMemoryOut: Bool = false
    @MainActor
    public init(grammar: String, modelPath: String, systemPrompt: String, streamResult: Binding<String>? = nil, inputText: String) async throws {
        print("init text to structure")
        self.grammar = grammar
        self.modelPath = modelPath
        self.systemPrompt = systemPrompt
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
            self.generationTask = Task(priority: .background) {
                var grammarString: String = self.grammar
                if self.grammar.contains("containers/Bundle/Application") {
                    let url = URL(filePath: self.grammar)
                    grammarString = try! String(contentsOf: url, encoding: .utf8)
                }
                let withNotes = !grammarString.contains("step_short_description")
                print(withNotes)
                let possiblePromptsWithNotes = [
                    "[INST]create list of parts for this table saw[/INST]",
                    "[INST]divide into instructions[/INST]",
                    "[INST]generate manual[/INST]",
                ]
                let possiblePromptsWithoutNotes = [
                    "[INST]Give me list of parts with short definition for this table saw[/INST]",
                    "[INST]create instructions description[/INST]",
                    "[INST]generate instructions[/INST]",
                ]
                
                
                var result = try await llamaState.generateWithGrammar(prompt: """
                    \(possiblePromptsWithNotes[0])\(prompt)
                """, grammar: LlamaGrammar(grammarString)!)
                
                return result
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
    
    public func generateRaw (prompt: String, extraKnowledge: String? = "") async throws -> String {
        do {
            self.generationTask = Task {
//                var result = try await llamaState.generateRaw(prompt: """
//<|system|>
//Answer questions using this helpful information \(extraKnowledge). Finish your answer woth <end> tag.</s>
//<|user|>
//\(prompt)</s>
//<|assistant|>
//""")
                var listOfModels = """
List of 3d models:
riving knife: RivingKnife_model.usdz
saw blade: SawBlade_model.usdz
table insert: TableInsert_model.usdz
"""
//                var result = try await llamaState.generateRaw(prompt: """
//           <s>[INST] Help user with using, maintaining and repairing some facility.
//            Act like an smart assistant, your name is Taqi.
//            You have a list of parts with corresponding 3d model files for each part, check if your answer mention parts from this list.
//            If yes replace mentioned part with corresponding rcproject file name for mentioned part. Finish your answer with <end> tag. [/INST]
//            3D MODELS: \(listOfModels)
//            CONTEXT: \(extraKnowledge)
//            </s>
//            [INST]
//            QUESTION: \(prompt)
//            [/INST]
//""")

                var result = try await llamaState.generateRaw(prompt: "<s>[INST]You are AI assistant, your name is Taqi. Answer questions. Use this helpful information to answer questions. Finish your answer with <end> tag.[/INST]\(extraKnowledge)</s>[INST]\(prompt)[/INST]")
                return result
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
        Task { await self.llamaState.llamaContext?.forceStop() }
        //NotificationCenter.default.removeObserver(observer)
    }
}
