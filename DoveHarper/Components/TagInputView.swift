import SwiftUI

struct TagInputView: View {
    @Binding var tags: [String]
    var placeholder: String = "Add tag..."
    var autocorrectRules: [String: String] = [:]

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tags.isEmpty {
                FlowTagLayout(items: tags) { item in
                    tags.removeAll { $0 == item }
                }
            }

            HStack(spacing: 6) {
                TextField(placeholder, text: $inputText)
                    .focused($isInputFocused)
                    .onSubmit {
                        addTag()
                    }
                if !inputText.isEmpty {
                    Button {
                        addTag()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func addTag() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let corrected = applyAutocorrect(trimmed)
        if !tags.contains(corrected) {
            tags.append(corrected)
        }
        inputText = ""
        isInputFocused = true
    }

    private func applyAutocorrect(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in autocorrectRules {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .caseInsensitive)
        }
        return result
    }
}

struct PriceInputView: View {
    @Binding var priceLabel: String
    @Binding var isFree: Bool

    var body: some View {
        if !isFree {
            HStack(spacing: 4) {
                Text("$")
                    .foregroundStyle(.secondary)
                TextField("0.00", text: priceDisplayBinding)
                    .keyboardType(.decimalPad)
            }
        }
    }

    private var priceDisplayBinding: Binding<String> {
        Binding(
            get: {
                priceLabel.replacingOccurrences(of: "$", with: "")
            },
            set: { newValue in
                let filtered = newValue.filter { "0123456789.".contains($0) }
                let parts = filtered.split(separator: ".", maxSplits: 1)
                if parts.count > 1 {
                    let intPart = parts[0]
                    let decPart = String(parts[1]).prefix(2)
                    priceLabel = "$\(intPart).\(decPart)"
                } else if filtered.isEmpty {
                    priceLabel = ""
                } else {
                    priceLabel = "$\(filtered)"
                }
            }
        )
    }
}
