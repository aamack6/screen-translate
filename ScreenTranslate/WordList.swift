import SwiftUI

/// The user's own fixed translations, such as names an engine keeps getting wrong
/// (イーブイ → Eevee). A text that is exactly a word on the list gets its translation; a text that
/// contains one has it swapped in before translating, so the engine keeps it as is.
struct WordListEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var original: String
    var translation: String
}

enum WordList {
    private static let key = "wordList"

    static var entries: [WordListEntry] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([WordListEntry].self, from: data)) ?? []
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
            // Remembered translations may have been made without the new words.
            TranslationCache.clearAll()
        }
    }

    /// The translation when the whole text is a word on the list.
    static func exactMatch(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.first { $0.original == trimmed }?.translation
    }

    /// The text with every listed word replaced by its translation, longest words first so
    /// "リーフィアex" wins over "リーフィア".
    static func substitute(in text: String) -> String {
        var result = text
        for entry in entries.sorted(by: { $0.original.count > $1.original.count }) where !entry.original.isEmpty {
            result = result.replacingOccurrences(of: entry.original, with: entry.translation)
        }
        return result
    }
}

struct WordListView: View {
    @State private var entries = WordList.entries
    @State private var original = ""
    @State private var translation = ""

    var body: some View {
        Form {
            Section {
                TextField("Original, such as イーブイ", text: $original)
                    .autocorrectionDisabled()
                TextField("Translation, such as Eevee", text: $translation)
                    .autocorrectionDisabled()
                Button("Add") {
                    entries.insert(WordListEntry(
                        original: original.trimmingCharacters(in: .whitespacesAndNewlines),
                        translation: translation.trimmingCharacters(in: .whitespacesAndNewlines)
                    ), at: 0)
                    original = ""
                    translation = ""
                }
                .disabled(original.trimmingCharacters(in: .whitespaces).isEmpty || translation.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("Names, brands and terms the translation keeps getting wrong. They're used with every engine, in screenshots, live mode, the camera and the browser.")
            }

            if !entries.isEmpty {
                Section("Your words") {
                    ForEach(entries) { entry in
                        LabeledContent(entry.original, value: entry.translation)
                    }
                    .onDelete { entries.remove(atOffsets: $0) }
                }
            }
        }
        .navigationTitle("My word list")
        .onChange(of: entries) { WordList.entries = entries }
    }
}
