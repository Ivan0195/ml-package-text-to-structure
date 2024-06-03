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
                
                
                
                //                let result = try await llamaState.generateWithGrammar(prompt: """
                //[INST]generate manual[/INST]\(prompt)
                //""", grammar: LlamaGrammar(grammarString)!)
                
                //                var result = try await llamaState.generateWithGrammar(prompt: """
                //                    [INST]return list of logical steps[/INST]\(prompt)
                //                """, grammar: LlamaGrammar(grammarString)!)
                
                
                
                
                let withNotes = !grammarString.contains("step_short_description")
                let possiblePromptsWithNotes = [
                    "[INST]divide into instructions[/INST]",
                    "[INST]generate manual[/INST]",
                    "[INST]return list of instructions[/INST]",
                ]
                let possiblePromptsWithoutNotes = [
                    "[INST]return list of instructions[/INST]",
                    "[INST]group into instructions[/INST]",
                    "[INST]generate steps[/INST]",
                ]
                
                
                var result = try await llamaState.generateWithGrammar(prompt: """
                    \(withNotes ? possiblePromptsWithNotes[0] : possiblePromptsWithoutNotes[0])\(prompt)
                """, grammar: LlamaGrammar(grammarString)!)
                
                do {
                    var generatedJSON = result.data(using: .utf8)!
                    if withNotes {
                        var decodedSteps = try JSONDecoder().decode(StepsJSON.self, from: generatedJSON)
                    } else {
                        var decodedSteps = try JSONDecoder().decode(StepsJSONWithoutNotes.self, from: generatedJSON)
                    }
                } catch {
                    if await !llamaState.llamaContext!.isItForceStop {
                        print("invalid json, regeneration started")
                        result = try await llamaState.generateWithGrammar(prompt: """
                            \(withNotes ? possiblePromptsWithNotes[1] : possiblePromptsWithoutNotes[1])\(prompt.dropLast())
                            """, grammar: LlamaGrammar(grammarString)!)
                    }
                    do {
                        var generatedJSON = result.data(using: .utf8)!
                        if withNotes {
                            var decodedSteps = try JSONDecoder().decode(StepsJSON.self, from: generatedJSON)
                        } else {
                            var decodedSteps = try JSONDecoder().decode(StepsJSONWithoutNotes.self, from: generatedJSON)
                        }
                    } catch {
                        if await !llamaState.llamaContext!.isItForceStop {
                            print("invalid json, regeneration started")
                            result = try await llamaState.generateWithGrammar(prompt: "\(withNotes ? possiblePromptsWithNotes[2] : possiblePromptsWithoutNotes[2])\(prompt)", grammar: LlamaGrammar(grammarString)!)
                        }
                        do {
                            var generatedJSON = result.data(using: .utf8)!
                            if withNotes {
                                var decodedSteps = try JSONDecoder().decode(StepsJSON.self, from: generatedJSON)
                            } else {
                                var decodedSteps = try JSONDecoder().decode(StepsJSONWithoutNotes.self, from: generatedJSON)
                            }
                        } catch {
                            if await !llamaState.llamaContext!.isItForceStop {
                                print("invalid json, regeneration started")
                                result = try await llamaState.generateWithGrammar(prompt: "\(withNotes ? "" : "divide into instructions")\(prompt.dropLast())", grammar: LlamaGrammar(grammarString)!)
                            }
                        }
                    }
                }
                
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
