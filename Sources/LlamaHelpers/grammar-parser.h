#ifdef __cplusplus
#pragma once
#include "llama.h"
#include <cstdint>
#include <string>
#include <map>
#include <vector>

namespace grammar_parser {
    struct parse_state {
        std::map<std::string, uint32_t>                 symbol_ids;
        std::vector<std::vector<llama_grammar_element>> rules;

        std::vector<const llama_grammar_element *> c_rules();
    };

    parse_state parse(const char * src);
    void print_grammar(FILE * file, const parse_state & state);
    llama_grammar * llama_grammar_init_from_content(const char * src);
}

#endif
