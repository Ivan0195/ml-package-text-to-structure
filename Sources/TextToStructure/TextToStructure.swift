import Foundation
import llama
import SwiftUI
import LlamaHelpers
import Combine

extension String {
    var condensedWhitespace: String {
        let components = self.components(separatedBy: NSCharacterSet.whitespacesAndNewlines)
        return components.filter { !$0.isEmpty }.joined(separator: " ")
    }

    func removeSpecialCharacters() -> String {
        let okayChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLKMNOPQRSTUVWXYZ1234567890 ")
        return String(self.unicodeScalars.filter { okayChars.contains($0) || $0.properties.isEmoji })
    }
}

@available(iOS 13.0.0, *)
public struct StepsJSON: Codable {
    public var steps: [GeneratedStep]
}

public struct StepsJSONWithClips: Codable {
    public var steps: [GeneratedStepWithClip]
}

public struct GeneratedStepWithClip: Codable {
    public var step_name: String?
    public var step_description: String?
    public var step_short_description: String?
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
    public var isAvailableOnDevice: Bool = false
    public var isGenerating: Bool = false
    private var modelPath: String
    private var llamaState: LlamaState? = nil
    private let apiLlama = CloudLlamaAPIService()
    private var generationTask: Task<String, any Error>? = nil
    private var streamResult: Binding<String>? = nil
    private var isRequestCanceled: Bool = false
    private var finishTime: Int?
    
    
    public init(modelPath: String = "", streamResult: Binding<String>? = nil) async throws {
        print("init text to structure")
        self.modelPath = modelPath
        guard !modelPath.isEmpty else {
            print("modelPath is empty")
            return
        }
        self.streamResult = streamResult
        if MTLCreateSystemDefaultDevice()!.name.contains("M") || MTLCreateSystemDefaultDevice()!.name.contains("A17 Pro") {
            self.isAvailableOnDevice = true
        }
        
    }
    
    public func generateWithScheme(prompt: String, systemPrompt: String?, grammar: String, useCloudModel: Bool = false, withClips: Bool = false) async throws -> String {
        isGenerating = true
        var subsString = prompt.components(separatedBy: ",\n")
        let noClipsInput = prompt.contains("{sentence: ")
        ? subsString.reduce("", {acc, str in
            let endSkip = ", start:"
            let startSkip = "{sentence: "
            let description = str.slice(from: startSkip, to: endSkip) ?? ""
            return acc + description
        })
        : prompt
        finishTime = Int(subsString[subsString.count - 1].slice(from: "start: ", to: "}"))
//        print(noClipsInput)
//        print(prompt)
        if useCloudModel {
            isRequestCanceled = false
            var grammarString: String = grammar
            if grammar.contains("containers/Bundle/Application") {
                let url = URL(filePath: grammar)
                grammarString = try! String(contentsOf: url, encoding: .utf8)
            }
            var steps: StepsJSONWithClips
            var result = try await apiLlama.generateSteps(subtitles: withClips ? prompt : noClipsInput, withDescription: grammarString.contains("step_name"), withClips: withClips)
            if withClips {
                let jsonstring = result.data(using: .utf8)
                do {
                    steps = try JSONDecoder().decode(StepsJSONWithClips.self, from: jsonstring!)
                } catch {
                    if await llamaState?.llamaContext?.isItForceStop == true {
                        throw GenerationError.interrupt
                    }
                    throw LlamaError.couldNotInitializeContext
                }
                
                let newSteps = steps.steps.enumerated().map{(index, step) in
                    return GeneratedStepWithClip(step_name: step.step_name, step_description: step.step_description, step_short_description: step.step_short_description, start: step.start, end: index+1 == steps.steps.count ? finishTime ?? nil : steps.steps[index+1].start ?? nil)
                    
                }
                steps.steps = newSteps
                let stepsToJson = try JSONEncoder().encode(steps)
                let stepsJsonString = String(data: stepsToJson, encoding: .utf8)
                result = stepsJsonString ?? ""
            }
            isGenerating = false
            guard !isRequestCanceled else {throw GenerationError.interrupt}
            if !grammarString.contains("step_name") {
                return result.replacingOccurrences(of: "step_short_description", with: "step_name")
            } else {
                return result
            }
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
                let withoutDescription = grammarString.contains("step_short_description")
                var requestPrompt: String
                
//                withClips
//                    ? (
//                        withoutDescription
//                            //? "[INST]return short list of instructions without introduction and conclusion: \(prompt)[/INST]"
//                            ? "[INST]skip introduction and conclusion, make list of operations from provided information: \(prompt)[/INST]"
//                            : "<s>[INST]make manual from provided information: \(prompt)[/INST]</s>[INST]skip introduction and other unnecessary parts[/INST]"
//                    )
//                    : "[INST]return list of instructions \(noClipsInput)[/INST]"
                
                
#if os(visionOS)
                print("visionOS prompt")
                requestPrompt = withClips
                    ? (
                        withoutDescription
                            ? "[INST]skip introduction and conclusion, generate list of operations from provided information: \(prompt)[/INST]"
                            : "[INST]gemerate manual from provided information: \(prompt)[/INST]"
                    )
                    : "[INST]return list of operations \(noClipsInput)[/INST]"
#else
                requestPrompt = withClips
                    ? (
                        withoutDescription
                            //? "[INST]return short list of instructions without introduction and conclusion: \(prompt)[/INST]"
                            //? "[INST]skip introduction and conclusion, make list of operations \(prompt)[/INST]"
                            ? "[INST]make manual from given information\n\(prompt)[/INST]"
                            : "[INST]make manual from given information\n\(prompt)[/INST]"
                    )
                    : "[INST]make manual from given information\n\(noClipsInput)[/INST]"
#endif
                var result = try await llamaState?.generateWithGrammar(
                    prompt: requestPrompt,
                    grammar: LlamaGrammar(grammarString)!)
                isGenerating = false
                self.llamaState = nil
                var steps: StepsJSONWithClips
                if withClips {
                    let jsonstring = result?.data(using: .utf8)
                    do {
                        steps = try JSONDecoder().decode(StepsJSONWithClips.self, from: jsonstring!)
                    } catch {
                        if await llamaState?.llamaContext?.isItForceStop == true {
                            throw GenerationError.interrupt
                        }
                        throw LlamaError.couldNotInitializeContext
                    }
                    
                    let newSteps = steps.steps.enumerated().map{(index, step) in
                        return GeneratedStepWithClip(step_name: step.step_name, step_description: step.step_description, step_short_description: step.step_short_description, start: step.start == 0 ? step.start : (step.start ?? 1) - 1, end: index+1 == steps.steps.count ? finishTime ?? nil : steps.steps[index+1].start ?? nil)
                        
                    }
                    steps.steps = newSteps
                    let stepsToJson = try JSONEncoder().encode(steps)
                    let stepsJsonString = String(data: stepsToJson, encoding: .utf8)
                    result = stepsJsonString
                }
                if !grammarString.contains("step_name") {
                    return result?.replacingOccurrences(of: "step_short_description", with: "step_name") ?? ""
                } else {
                    return result ?? ""
                }
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
                return res.replacingOccurrences(of: "<end>", with: "").replacingOccurrences(of: "<s>", with: "").replacingOccurrences(of: "</s>", with: "").removeSpecialCharacters().condensedWhitespace
            } catch {
                throw LlamaError.couldNotInitializeContext
            }
        } else {
            do {
//                let promptForGeneration = "<s>[INST]You are AI assistant, your name is Taqi. Answer questions. Use this helpful information \(String(describing: extraKnowledge)) to answer questions. Finish your answer with <end> tag.[/INST]</s>[INST]\(prompt)[/INST]"
                let promptForGeneration = "[INST]You are AI assistant, your name is Taqi. Answer questions. Use this helpful information \(String(describing: extraKnowledge)) to answer question \(prompt). Finish your answer with <end> tag.[/INST]"
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
                    let promptForGeneration = "[INST]You are AI assistant, your name is Taqi. Answer questions. Use this helpful information \(String(describing: extraKnowledge)) to answer question \(prompt). Finish your answer with <end> tag.[/INST]"
                    let result = try await llamaState?.generateRaw(prompt: promptForGeneration)
                    self.llamaState = nil
                    return result?.replacingOccurrences(of: "<end>", with: "").replacingOccurrences(of: "<s>", with: "").replacingOccurrences(of: "</s>", with: "").removeSpecialCharacters().condensedWhitespace ?? "no result"
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
