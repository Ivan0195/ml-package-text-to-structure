import Foundation
import llama
import LlamaHelpers


final class LlamaGrammar {
    static var steps: LlamaGrammar? {
        Self(#"""
    root ::= Template
    Step ::= "{"   ws   "\"step_name\":"   ws   string   ","   ws   "\"step_description\":"   ws   string   "}"
    Steplist ::= "[]" | "["   ws   Step   (","   ws   Step)*   "]"
    Template ::= "{"   ws   "\"steps\":"   ws   Steplist   "}"
    Templatelist ::= "[]" | "["   ws   Template   (","   ws   Template)*   "]"
    string ::= "\""   ([^"]*)   "\""
    boolean ::= "true" | "false"
    ws ::= [ \t\n]*
    number ::= [0-9]+   "."?   [0-9]*
    stringlist ::= "["   ws   "]" | "["   ws   string   (","   ws   string)*   ws   "]"
    numberlist ::= "["   ws   "]" | "["   ws   string   (","   ws   number)*   ws   "]"
    """#)
    }
    var grammar: OpaquePointer

    init?(_ grammar: String) {
        self.grammar = grammar_parser.llama_grammar_init_from_content(grammar.cString(using: .utf8))
    }

    deinit {
        llama_grammar_free(self.grammar)
    }
}
