Usage example:
[Github Repo](https://github.com/Ivan0195/ml-package-text-to-structure)
```
let generator = await TextToStructure(grammar: path_to_grammar_file_or_grammar_as_string, modelPath: path_to_your_model, systemPrompt: system_message)
let result = try await generator.generate(prompt: text)
```
