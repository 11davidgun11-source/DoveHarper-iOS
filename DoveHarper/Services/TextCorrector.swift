import Foundation

class TextCorrector {
    private var rules: [String: String]

    init(rules: [String: String] = [
        "explicit content": "Explicit Content",
        "nsfw": "NSFW",
        "mature content": "Mature Content",
        "18+": "18+"
    ]) {
        self.rules = rules
    }

    func updateRules(_ newRules: [String: String]) {
        self.rules = newRules
    }

    func correct(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in rules {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .caseInsensitive
            )
        }
        return result
    }

    func addRule(pattern: String, replacement: String) {
        rules[pattern.lowercased()] = replacement
    }

    func removeRule(pattern: String) {
        rules.removeValue(forKey: pattern.lowercased())
    }

    func getAllRules() -> [String: String] {
        rules
    }
}
