import Foundation

enum Validation {
    static func privateIPv4(_ value: String) -> Bool {
        let fields = value.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 4 else { return false }
        let numbers = fields.compactMap { field -> Int? in
            guard !field.isEmpty, field.allSatisfy({ $0.isASCII && $0.isNumber }),
                  (field.count == 1 || !field.hasPrefix("0")), let n = Int(field), (0...255).contains(n) else { return nil }
            return n
        }
        guard numbers.count == 4 else { return false }
        return numbers[0] == 10 || (numbers[0] == 172 && (16...31).contains(numbers[1]))
            || (numbers[0] == 192 && numbers[1] == 168)
            || (numbers[0] == 100 && (64...127).contains(numbers[1]))
    }

    static func httpsBase(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw GuardianError.invalid("Use an HTTPS origin, for example https://guardian.home.example:8443, without a path, credentials or query.")
        }
        return url
    }

    static func domain(_ value: String) throws -> String {
        let domain = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard domain.count <= 253, labels.count >= 2, labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }), labels.last?.contains(where: { $0.isLetter }) == true else {
            throw GuardianError.invalid("Enter an ASCII domain such as example.com. Use punycode for international names; URLs, IPs and wildcards are not accepted.")
        }
        return domain
    }

    static func identifier(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.count <= 256,
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) else {
            throw GuardianError.invalid("The reported application identifier is invalid.")
        }
        return value
    }
}
