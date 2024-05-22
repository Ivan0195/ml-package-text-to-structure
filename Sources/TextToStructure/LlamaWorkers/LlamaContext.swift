import llama
import Foundation
import SwiftUI
import UIKit

enum LlamaError: LocalizedError {
    case couldNotInitializeContext
    case invalidModelUrl
    case invalidJSONScheme
    case emptyPrompt
    case outOfMemory
    case error(title: String?, message: String?)
    case tooLongText
    
    var errorDescription: String? {
        switch self {
        case .tooLongText:
            return "Your text is too long for generation"
        case .invalidJSONScheme:
            return "Invalid JSON Scheme"
        case .couldNotInitializeContext:
            return "Context initialization error"
        case .invalidModelUrl:
            return "Invalid provided model path"
        case .emptyPrompt:
            return "Prompt is empty or too short"
        case .outOfMemory:
            return "Process is running out of memory. Try to cancel another processes and try again"
        case .error(title: let title, message: let message):
            return message
        }
    }
}

extension String {

    func slice(from: String, to: String) -> String? {

        return (range(of: from)?.upperBound).flatMap { substringFrom in
            (range(of: to, range: substringFrom..<endIndex)?.lowerBound).map { substringTo in
                String(self[substringFrom..<substringTo])
            }
        }
    }
}

@available(iOS 13.0.0, *)

actor LlamaContext {
    private var model: OpaquePointer
    private var context: OpaquePointer
    private var batch: llama_batch
    private var tokens_list: [llama_token]
    private var temporary_invalid_cchars: [CChar]
    private var isItForceStop: Bool = false
    private var modelAnswer: String = ""
    @Binding var stream: String
    private var contextParams: llama_context_params
    
    var n_len: Int32
    var n_cur: Int32 = 0
    var n_decode: Int32 = 0
    var empty_strings: Int32 = 0
    
    init(modelPath: String, stream: Binding<String>? = nil, inputText: String) throws {
        self.tokens_list = []
        self.temporary_invalid_cchars = []
        self._stream = stream ?? Binding.constant("")
        
        var model_params = llama_model_default_params()
        let device = MTLCreateSystemDefaultDevice()
        let isSupportMetal3 = device?.supportsFamily(.metal3) ?? false
        if !isSupportMetal3 {
            model_params.n_gpu_layers = 0
        } else {
            if ProcessInfo().physicalMemory > 7598691840 {
                if MTLCreateSystemDefaultDevice()!.name.contains("M") {
                    model_params.n_gpu_layers = 999
                } else {
                    model_params.n_gpu_layers = 24
                }
            } else {
                model_params.n_gpu_layers = 20
            }
        }
        let model = llama_load_model_from_file(modelPath, model_params)
        
        let n_threads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        
        let utf8Count = inputText.utf8.count
        let n_tokens = utf8Count + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: n_tokens)
        let tokenCount = llama_tokenize(model, inputText, Int32(utf8Count), tokens, Int32(n_tokens), true, false)
        var swiftTokens: [llama_token] = []
        for i in 0..<tokenCount {
            swiftTokens.append(tokens[Int(i)])
        }
        tokens.deallocate()
        
        let maxInputLength = Double(swiftTokens.count) * 1.35 < 2048 ? Double(swiftTokens.count) + 700 : Double(swiftTokens.count) * 1.35
        
        guard maxInputLength <= 12288 else {
            print("Text is too long")
            throw LlamaError.tooLongText
        }
        
        var ctx_params = llama_context_default_params()
        ctx_params.seed = 1
        ctx_params.n_ctx = UInt32(maxInputLength)
        ctx_params.n_batch = UInt32(maxInputLength)
        ctx_params.rope_scaling_type = LLAMA_ROPE_SCALING_TYPE_MAX_VALUE
        ctx_params.n_threads       = UInt32(n_threads)
        ctx_params.n_threads_batch = UInt32(n_threads)
        self.batch = llama_batch_init(Int32(maxInputLength), 0, 1)
        self.n_len = Int32(maxInputLength)
        
        self.contextParams = ctx_params
        
        print(ctx_params)
        
        guard let model else {
            print("Could not load model at \(modelPath)")
            throw LlamaError.couldNotInitializeContext
        }
        self.model = model
        let context = llama_new_context_with_model(model, ctx_params)
        guard let context else {
            print("Could not load context!")
            throw LlamaError.couldNotInitializeContext
        }
        self.context = context
    }
    
    deinit {
        llama_batch_free(batch)
        if !isItForceStop {
            print("here")
            llama_free(context)
            llama_free_model(model)
        }
        llama_backend_free()
        self.isItForceStop = false
    }
    
    public func forceStop() {
        if self.isItForceStop {
            return
        }
        self.isItForceStop = true
        llama_free(self.context)
        llama_free_model(self.model)
    }
    
    func reset_context() throws {
        llama_free(self.context)
        let context = llama_new_context_with_model(self.model, self.contextParams)
        guard let context else {
            print("Could not load context!")
            throw LlamaError.couldNotInitializeContext
        }
        self.context = context
    }
    
    func completion_init(text: String) async {
        tokens_list = tokenize(text: text, add_bos: true)
        temporary_invalid_cchars = []
        llama_batch_clear(&batch)
        
        for i1 in 0..<tokens_list.count where !isItForceStop {
            let i = Int(i1)
            llama_batch_add(&batch, tokens_list[i], Int32(i), [0], false)
        }
        
        batch.logits[Int(batch.n_tokens) - 1] = 1 // true
        
        if !Task.isCancelled && llama_decode(context, batch) != 0 {
            print("llama_decode() failed")
        }
        if Task.isCancelled {return}
        print("llama decoded")
        n_cur = batch.n_tokens
        if stream != "" {
            stream = ""
        }
        print("Prompt decoding successful")
    }
    
    struct CompletionStatus: Sendable, Equatable, Hashable {
        var piece: String
        var state: State
        enum State: Sendable, Equatable, Hashable {
            case normal
            case eos
            case maxlength
        }
    }
    
    
    func completion_loop_with_grammar(grammar: LlamaGrammar) -> CompletionStatus {
        var new_token_id: llama_token = 0
        
        let n_vocab = llama_n_vocab(model)
        let logits = llama_get_logits_ith(context, batch.n_tokens - 1)
        
        var candidates = Array<llama_token_data>()
        candidates.reserveCapacity(Int(n_vocab))
        
        for token_id in 0..<n_vocab {
            candidates.append(llama_token_data(id: token_id, logit: logits![Int(token_id)], p: 0.0))
        }
        candidates.withUnsafeMutableBufferPointer() { buffer in
            var candidates_p = llama_token_data_array(data: buffer.baseAddress, size: buffer.count, sorted: false)
            llama_sample_grammar(context, &candidates_p, grammar.grammar)
            llama_sample_top_k(context, &candidates_p, 40, 2)
            llama_sample_top_p(context, &candidates_p, 0.95, 2)
            llama_sample_min_p(context, &candidates_p, 0.05, 2)
            llama_sample_temp(context, &candidates_p, 0.8)
            new_token_id = llama_sample_token(context, &candidates_p)
            llama_grammar_accept_token(context, grammar.grammar, new_token_id);
        }
        
        if new_token_id == llama_token_eos(context) {
            let new_token_str = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            return CompletionStatus(piece: new_token_str, state: .eos)
        } else if n_cur >= n_len || empty_strings >= 5 {
            let new_token_str = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            return CompletionStatus(piece: new_token_str, state: .maxlength)
        }
        
        let new_token_cchars = token_to_piece(token: new_token_id)
        temporary_invalid_cchars.append(contentsOf: new_token_cchars)
        let new_token_str: String
        if let string = String(validatingUTF8: temporary_invalid_cchars + [0]) {
            temporary_invalid_cchars.removeAll()
            new_token_str = string
        } else if (0 ..< temporary_invalid_cchars.count).contains(where: {$0 != 0 && String(validatingUTF8: Array(temporary_invalid_cchars.suffix($0)) + [0]) != nil}) {
            let string = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            new_token_str = string
        } else {
            new_token_str = ""
        }
        if new_token_str == "" {
            empty_strings = empty_strings + 1
        }
        if new_token_str == "<|endoftext|>" || new_token_str == "<|im_end|>" || new_token_str == "<|end|>" || new_token_str == "</s>" {
            empty_strings = 5
        }
        llama_batch_clear(&batch)
        llama_batch_add(&batch, new_token_id, n_cur, [0], true)
        n_decode += 1
        n_cur += 1
        modelAnswer += new_token_str
        var stepsArray = modelAnswer.components(separatedBy: "},")
        //стрим названия шагов
        stream = stepsArray.enumerated().reduce("", {acc, str in
            let endSkip = "\""
            let startSkip = str.element.contains("step_short_description") ? "{\"step_short_description\":\"" : "{\"step_name\":\""
            let description = str.element.slice(from: startSkip, to: endSkip) ?? ""
            return acc + "Step \(str.offset + 1): " + description + "\n"
        })
        //счетчик шагов
        //stream = String(stepsArray.count)
        // стрим исходного джейсона
        //stream = modelAnswer
        if llama_decode(context, batch) != 0 {
            print("failed to evaluate llama!")
        }
        
        return CompletionStatus(piece: new_token_str == "<|endoftext|>" ? "" : new_token_str, state: .normal)
    }
    
    func clear() {
        self.tokens_list.removeAll()
        self.temporary_invalid_cchars.removeAll()
        try? self.reset_context()
    }
    
    func llama_batch_clear(_ batch: inout llama_batch) {
        batch.n_tokens = 0
    }
    
    func llama_batch_add(_ batch: inout llama_batch, _ id: llama_token, _ pos: llama_pos, _ seq_ids: [llama_seq_id], _ logits: Bool) {
        batch.token   [Int(batch.n_tokens)] = id
        batch.pos     [Int(batch.n_tokens)] = pos
        batch.n_seq_id[Int(batch.n_tokens)] = Int32(seq_ids.count)
        for i in 0..<seq_ids.count {
            batch.seq_id[Int(batch.n_tokens)]![Int(i)] = seq_ids[i]
        }
        batch.logits  [Int(batch.n_tokens)] = logits ? 1 : 0
        
        batch.n_tokens += 1
    }
    
    private func tokenize(text: String, add_bos: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        let n_tokens = utf8Count + (add_bos ? 1 : 0)
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: n_tokens)
        let tokenCount = llama_tokenize(model, text, Int32(utf8Count), tokens, Int32(n_tokens), add_bos, false)
        
        var swiftTokens: [llama_token] = []
        for i in 0..<tokenCount {
            swiftTokens.append(tokens[Int(i)])
        }
        
        tokens.deallocate()
        return swiftTokens
    }
    
    /// - note: The result does not contain null-terminator
    private func token_to_piece(token: llama_token) -> [CChar] {
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 8)
                result.initialize(repeating: Int8(0), count: 8)
                defer {
                    result.deallocate()
                }
                let nTokens = llama_token_to_piece(model, token, result, 8, false)

                if nTokens < 0 {
                    let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: Int(-nTokens))
                    newResult.initialize(repeating: Int8(0), count: Int(-nTokens))
                    defer {
                        newResult.deallocate()
                    }
                    let nNewTokens = llama_token_to_piece(model, token, newResult, -nTokens, false)
                    let bufferPointer = UnsafeBufferPointer(start: newResult, count: Int(nNewTokens))
                    return Array(bufferPointer)
                } else {
                    let bufferPointer = UnsafeBufferPointer(start: result, count: Int(nTokens))
                    return Array(bufferPointer)
                }
    }
}
