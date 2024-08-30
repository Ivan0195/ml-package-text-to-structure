import Foundation
import llama
import SwiftUI
import LlamaHelpers
import Combine

@available(iOS 13.0.0, *)
public struct StepsJSON: Codable {
    public var steps: [GeneratedStep]
}

public struct StepsJSONWithClips: Codable {
    public var steps: [GeneratedStepWithClip]
}

public struct GeneratedStepWithClip: Codable {
    public var step_name: String
    public var step_description: String?
    public var start: Int?
    public var end: Int?
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
    private var isRequestCanceled: Bool = false
    
    
    public init(modelPath: String = "", streamResult: Binding<String>? = nil) async throws {
        print("init text to structure")
        self.modelPath = modelPath
        guard !modelPath.isEmpty else {
            print("modelPath is empty")
            return
        }
        self.streamResult = streamResult
    }
    
    public func generateWithScheme(prompt: String, systemPrompt: String?, grammar: String, useCloudModel: Bool = false, withClips: Bool = false) async throws -> String {
        isGenerating = true
        var subsString = prompt.components(separatedBy: "},")
        let noClipsInput = prompt.contains("{sentence: ")
        ? subsString.reduce("", {acc, str in
            let endSkip = ", start:"
            let startSkip = "{sentence: "
            let description = str.slice(from: startSkip, to: endSkip) ?? ""
            return acc + description + "  "
        })
        : prompt
        print(noClipsInput)
        print(prompt)
        if useCloudModel {
            isRequestCanceled = false
            var grammarString: String = grammar
            if grammar.contains("containers/Bundle/Application") {
                let url = URL(filePath: grammar)
                grammarString = try! String(contentsOf: url, encoding: .utf8)
            }
            let result = try await apiLlama.generateSteps(subtitles: withClips ? prompt : noClipsInput, withDescription: grammarString.contains("step_name"))
            isGenerating = false
            guard !isRequestCanceled else {throw GenerationError.interrupt}
            return result
        } else {
            if streamResult == nil {
                do {
                    self.llamaState = try await LlamaState(modelUrl: modelPath, inputText: withClips ? prompt : noClipsInput)
                } catch {
                    throw error
                }
            } else {
                do {
                    self.llamaState = try await LlamaState(modelUrl: modelPath, streamResult: streamResult, inputText: withClips ? prompt : noClipsInput)
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
                var result = try await llamaState?.generateWithGrammar(
                    prompt: withClips ? "[INST]skip introduction and conclusion, make steps for manual\(prompt)[/INST]" : "[INST]return list of instructions \(noClipsInput)[/INST]"
                    , grammar: LlamaGrammar(grammarString)!)
                isGenerating = false
                self.llamaState = nil
                if withClips {
                    let jsonstring = result?.data(using: .utf8)
                    var steps = try! JSONDecoder().decode(StepsJSONWithClips.self, from: jsonstring!)
                    let newSteps = steps.steps.enumerated().map{(index, step) in
                        return GeneratedStepWithClip(step_name: step.step_name, step_description: step.step_description, start: step.start, end: index+1 == steps.steps.count ? nil : steps.steps[index+1].start ?? nil)
                        
                    }
                    steps.steps = newSteps
                    let stepsToJson = try JSONEncoder().encode(steps)
                    let stepsJsonString = String(data: stepsToJson, encoding: .utf8)
                    result = stepsJsonString
                }
                return result ?? ""
            }
            return try await self.generationTask!.value
        }
    }
    
    public func generateRaw(prompt: String, extraKnowledge: String = "", useCloudModel: Bool = false) async throws -> String {
        if useCloudModel {
            isRequestCanceled = false
            do {
                let res = try await apiLlama.generateVocabularyAPI(prompt: prompt, extraInfo: extraKnowledge)
                guard !isRequestCanceled else {throw GenerationError.interrupt}
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
        isRequestCanceled = true
        self.generationTask?.cancel()
        Task { await self.llamaState?.llamaContext?.forceStop() }
    }
}
