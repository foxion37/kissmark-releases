import Foundation

/// Edits only the selected JSON/JSONC member; comments and unrelated text survive.
struct JSONConfiguration {
    private struct Token { var range: Range<Int>; var text: String }
    private struct Member { var key: String; var start: Int; var value: Int; var end: Int; var comma: Int? }
    private var bytes: [UInt8]
    private var tokens: [Token] = []
    private(set) var object: [String: Any] = [:]
    init(_ data: Data) throws {
        guard data.count <= 8 << 20 else { throw ClientSetup.Failure.configMalformed }
        bytes = Array(data)
        var position = 0
        while position < bytes.count {
            let start = position, byte = bytes[position]
            if [9, 10, 13, 32].contains(byte) { position += 1; continue }
            if byte == 47, position + 1 < bytes.count {
                if bytes[position + 1] == 47 {
                    position += 2; while position < bytes.count && bytes[position] != 10 { position += 1 }; continue
                }
                if bytes[position + 1] == 42 {
                    position += 2
                    while position + 1 < bytes.count && !(bytes[position] == 42 && bytes[position + 1] == 47) { position += 1 }
                    guard position + 1 < bytes.count else { throw ClientSetup.Failure.configMalformed }
                    position += 2; continue
                }
            }
            if byte == 34 {
                position += 1
                while position < bytes.count && bytes[position] != 34 {
                    position += bytes[position] == 92 ? 2 : 1
                }
                guard position < bytes.count else { throw ClientSetup.Failure.configMalformed }; position += 1
            } else if [123, 125, 91, 93, 58, 44].contains(byte) { position += 1 }
            else {
                while position < bytes.count && ![9, 10, 13, 32, 123, 125, 91, 93, 58, 44, 47].contains(bytes[position]) { position += 1 }
                guard position > start else { throw ClientSetup.Failure.configMalformed }
            }
            guard let text = String(bytes: bytes[start..<position], encoding: .utf8) else { throw ClientSetup.Failure.configMalformed }
            tokens.append(Token(range: start..<position, text: text))
        }
        let normalized = tokens.enumerated().filter { index, token in
            !(token.text == "," && index + 1 < tokens.count && ["}", "]"].contains(tokens[index + 1].text))
        }.map { $0.element.text }.joined(separator: " ")
        guard let root = try? JSONSerialization.jsonObject(with: Data(normalized.utf8)) as? [String: Any] else { throw ClientSetup.Failure.configMalformed }
        object = root
        _ = try members(at: 0)
    }
    private func valueEnd(_ start: Int) throws -> Int {
        guard start < tokens.count else { throw ClientSetup.Failure.configMalformed }
        if !["{", "["].contains(tokens[start].text) { return start }
        var depth = 0
        for index in start..<tokens.count {
            if ["{", "["].contains(tokens[index].text) { depth += 1 }
            if ["}", "]"].contains(tokens[index].text) { depth -= 1; if depth == 0 { return index } }
        }
        throw ClientSetup.Failure.configMalformed
    }
    private func members(at start: Int) throws -> (values: [Member], end: Int) {
        guard start < tokens.count, tokens[start].text == "{" else { throw ClientSetup.Failure.configMalformed }
        var result: [Member] = [], keys = Set<String>(), index = start + 1
        while index < tokens.count && tokens[index].text != "}" {
            guard let key = try? JSONDecoder().decode(String.self, from: Data(tokens[index].text.utf8)),
                  keys.insert(key).inserted, index + 2 < tokens.count, tokens[index + 1].text == ":" else { throw ClientSetup.Failure.configMalformed }
            let end = try valueEnd(index + 2)
            let comma = end + 1 < tokens.count && tokens[end + 1].text == "," ? end + 1 : nil
            result.append(Member(key: key, start: index, value: index + 2, end: end, comma: comma))
            index = (comma ?? end) + 1
        }
        guard index < tokens.count else { throw ClientSetup.Failure.configMalformed }
        return (result, index)
    }
    func changing(path: [String], value: Any?) throws -> Data {
        guard !path.isEmpty else { throw ClientSetup.Failure.invalidRequest }
        var start = 0
        for (depth, key) in path.enumerated() {
            let scope = try members(at: start)
            if let index = scope.values.firstIndex(where: { $0.key == key }) {
                let member = scope.values[index]
                if depth + 1 < path.count { start = member.value; continue }
                var range = tokens[member.value].range.lowerBound..<tokens[member.end].range.upperBound
                let replacement: Data
                if let value {
                    replacement = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
                } else {
                    var lower = tokens[member.start].range.lowerBound
                    var upper = tokens[member.end].range.upperBound
                    if let comma = member.comma { upper = tokens[comma].range.upperBound }
                    else if index > 0, let comma = scope.values[index - 1].comma { lower = tokens[comma].range.lowerBound }
                    range = lower..<upper; replacement = Data()
                }
                return replacing(range, with: replacement)
            }
            guard var nested = value else { return Data(bytes) }
            for remaining in path.dropFirst(depth + 1).reversed() { nested = [remaining: nested] }
            let encodedKey = try JSONEncoder().encode(key)
            let encodedValue = try JSONSerialization.data(withJSONObject: nested, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
            let separator = scope.values.isEmpty || scope.values.last?.comma != nil ? "\n  " : ",\n  "
            var insertion = Data(separator.utf8); insertion.append(encodedKey); insertion.append(Data(": ".utf8)); insertion.append(encodedValue); insertion.append(0x0A)
            let position = tokens[scope.end].range.lowerBound
            return replacing(position..<position, with: insertion)
        }
        throw ClientSetup.Failure.configMalformed
    }
    private func replacing(_ range: Range<Int>, with data: Data) -> Data {
        var result = Data(bytes[..<range.lowerBound]); result.append(data); result.append(contentsOf: bytes[range.upperBound...]); return result
    }
}
