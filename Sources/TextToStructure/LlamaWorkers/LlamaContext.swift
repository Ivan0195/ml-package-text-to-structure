import llama
import Foundation
import UIKit

enum LlamaError: Error {
    case couldNotInitializeContext
}

actor LlamaContext {
    private var model: OpaquePointer
    private var context: OpaquePointer
    private var batch: llama_batch
    private var tokens_list: [llama_token]
    private var temporary_invalid_cchars: [CChar]
    
    var n_len: Int32 = 8192
    var n_cur: Int32 = 0
    var n_decode: Int32 = 0
    var empty_strings: Int32 = 0
    
    init(model: OpaquePointer, context: OpaquePointer) {
        self.model = model
        self.context = context
        self.tokens_list = []
        self.batch = llama_batch_init(8192, 0, 1)
        self.temporary_invalid_cchars = []
    }
    
    deinit {
        llama_batch_free(batch)
        llama_free(context)
        llama_free_model(model)
        llama_backend_free()
    }
    
    private static var ctx_params: llama_context_params {
        let n_threads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        print("Using \(n_threads) threads")
        var ctx_params = llama_context_default_params()
        ctx_params.seed = 1
        ctx_params.n_ctx = 8192
        ctx_params.n_batch = 8192
        ctx_params.rope_scaling_type = LLAMA_ROPE_SCALING_TYPE_MAX_VALUE
        ctx_params.n_threads       = UInt32(n_threads)
        ctx_params.n_threads_batch = UInt32(n_threads)
        return ctx_params
    }
    
    static func createContext(path: String) throws -> LlamaContext {
        llama_backend_init()
        let model_params = llama_model_default_params()
        let model = llama_load_model_from_file(path, model_params)
        guard let model else {
            print("Could not load model at \(path)")
            throw LlamaError.couldNotInitializeContext
        }
        
        let context = llama_new_context_with_model(model, ctx_params)
        guard let context else {
            print("Could not load context!")
            throw LlamaError.couldNotInitializeContext
        }
        return LlamaContext(model: model, context: context)
    }
    
    func reset_context() throws {
        llama_free(self.context)
        let context = llama_new_context_with_model(self.model, Self.ctx_params)
        guard let context else {
            print("Could not load context!")
            throw LlamaError.couldNotInitializeContext
        }
        self.context = context
    }
    
    func completion_init(text: String) {
        tokens_list = tokenize(text: text, add_bos: true)
        temporary_invalid_cchars = []
        llama_batch_clear(&batch)
        for i1 in 0..<tokens_list.count {
            let i = Int(i1)
            print(batch)
            llama_batch_add(&batch, tokens_list[i], Int32(i), [0], false)
        }
        batch.logits[Int(batch.n_tokens) - 1] = 1 // true
        
        if llama_decode(context, batch) != 0 {
            print("llama_decode() failed")
        }
        
        n_cur = batch.n_tokens
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
            print("\n")
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
            print("empty: \(empty_strings)")
            empty_strings = empty_strings + 1
        }
        if new_token_str == "<|endoftext|>" {
            print("empty: \(empty_strings)")
            empty_strings = 5
        }
        print("n_cur: \(n_cur)", new_token_str)
        
        llama_batch_clear(&batch)
        llama_batch_add(&batch, new_token_id, n_cur, [0], true)
        
        n_decode += 1
        
        n_cur += 1
        
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
        print(swiftTokens)
        return swiftTokens
    }
    
    /// - note: The result does not contain null-terminator
    private func token_to_piece(token: llama_token) -> [CChar] {
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 8)
        result.initialize(repeating: Int8(0), count: 8)
        defer {
            result.deallocate()
        }
        let nTokens = llama_token_to_piece(model, token, result, 8)
        
        if nTokens < 0 {
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: Int(-nTokens))
            newResult.initialize(repeating: Int8(0), count: Int(-nTokens))
            defer {
                newResult.deallocate()
            }
            let nNewTokens = llama_token_to_piece(model, token, newResult, -nTokens)
            let bufferPointer = UnsafeBufferPointer(start: newResult, count: Int(nNewTokens))
            return Array(bufferPointer)
        } else {
            let bufferPointer = UnsafeBufferPointer(start: result, count: Int(nTokens))
            return Array(bufferPointer)
        }
    }
}
