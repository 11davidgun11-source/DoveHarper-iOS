import SwiftUI

struct FlowLayout: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.15))
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct FlowTagLayout: View {
    let items: [String]
    let onRemove: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 4) {
                    Text(item)
                        .font(.subheadline)
                        .lineLimit(1)
                    Button {
                        onRemove(item)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.blue.opacity(0.2))
                .cornerRadius(16)
            }
        }
    }
}
