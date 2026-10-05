import Foundation

/// Language of the helper's own terminal prompts only; commands, IDs, `yes` and error codes never change.
enum ClientLanguage: String {
    case ko, en

    /// KISSMARK_LANGUAGE wins when it names a supported language; otherwise the first supported process language, else Korean.
    static func resolve(environment: [String: String], preferred: [String] = Locale.preferredLanguages) -> ClientLanguage {
        if let value = environment["KISSMARK_LANGUAGE"], let language = ClientLanguage(rawValue: value) { return language }
        for identifier in preferred {
            let code = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { String($0).lowercased() }
            if let code, let language = ClientLanguage(rawValue: code) { return language }
        }
        return .ko
    }

    func text(korean: String, english: String) -> String { self == .ko ? korean : english }
}
