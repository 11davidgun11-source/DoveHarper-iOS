import SwiftUI

struct PublishGateView: View {
    let book: BookEntity
    let coverImage: UIImage?
    let manuscriptText: String
    let onPublish: () -> Void
    let onCancel: () -> Void

    private var errors: [String] {
        var list: [String] = []
        if book.title.isEmpty { list.append("Title is missing") }
        if book.slug.isEmpty { list.append("Slug is missing") }
        return list
    }

    private var warnings: [String] {
        var list: [String] = []
        if coverImage == nil { list.append("No cover image selected") }
        if manuscriptText.isEmpty { list.append("No manuscript imported") }
        if book.shortDescription.isEmpty { list.append("No short description") }
        if book.tropes.isEmpty { list.append("No tropes added") }
        if book.descriptionText.isEmpty { list.append("No description") }
        if !book.isFree && book.priceLabel.isEmpty { list.append("No price set") }
        return list
    }

    private var hasIssues: Bool { !errors.isEmpty || !warnings.isEmpty }
    private var canPublish: Bool { errors.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !errors.isEmpty {
                    Section {
                        ForEach(errors, id: \.self) { error in
                            HStack(spacing: 10) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        HStack {
                            Text("Cannot publish")
                                .font(.headline)
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                }

                if !warnings.isEmpty {
                    Section {
                        ForEach(warnings, id: \.self) { warning in
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(warning)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        HStack {
                            Text("Warnings")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Spacer()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, errors.isEmpty ? 20 : 16)
                }

                if errors.isEmpty && warnings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("Everything looks good")
                            .font(.title3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer()

                VStack(spacing: 12) {
                    if canPublish {
                        Button {
                            onPublish()
                        } label: {
                            Text(warnings.isEmpty ? "Publish" : "Publish Anyway")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationTitle("Review Before Publishing")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
