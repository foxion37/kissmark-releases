import Foundation

enum KissmarkAppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var display: String { "\(marketing) (\(build))" }
}

enum KissmarkVersionOrdering {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parts(lhs)
        let right = parts(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }

    private static func parts(_ version: String) -> [Int] {
        let trimmed = version.hasPrefix("v") || version.hasPrefix("V")
            ? String(version.dropFirst())
            : version
        return trimmed.split(separator: ".").map { component in
            Int(component.prefix(while: \.isNumber)) ?? 0
        }
    }
}

struct KissmarkGitHubRelease: Equatable, Decodable {
    let tagName: String
    let htmlURL: URL

    var marketingVersion: String {
        if tagName.hasPrefix("v") || tagName.hasPrefix("V") {
            return String(tagName.dropFirst())
        }
        return tagName
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

struct KissmarkUpdateCheck: Equatable {
    var currentMarketingVersion: String
    var latest: KissmarkGitHubRelease?

    var isUpdateAvailable: Bool {
        guard let latest else { return false }
        return KissmarkVersionOrdering.isNewer(latest.marketingVersion, than: currentMarketingVersion)
    }
}

enum KissmarkUpdateClient {
    /// Releases are published in the public `kissmark-releases` repository; the source
    /// repository is private, so its releases API would 404 for everyone else.
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/foxion37/kissmark-releases/releases/latest"
    )!

    static func evaluate(current: String, data: Data) throws -> KissmarkUpdateCheck {
        let latest = try JSONDecoder().decode(KissmarkGitHubRelease.self, from: data)
        return KissmarkUpdateCheck(currentMarketingVersion: current, latest: latest)
    }
}

enum KissmarkUpdateSettings {
    static let enabledKey = "kissmark-updates-enabled"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: enabledKey) == nil { return true }
        return defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledKey)
    }
}

@MainActor
@Observable
final class KissmarkUpdateController {
    private(set) var check: KissmarkUpdateCheck?
    private(set) var isChecking = false
    private(set) var errorMessage: String?
    var isEnabled: Bool {
        didSet { KissmarkUpdateSettings.setEnabled(isEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        isEnabled = KissmarkUpdateSettings.isEnabled(in: defaults)
    }

    func refresh() async {
        guard isEnabled else { return }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }
        do {
            var request = URLRequest(url: KissmarkUpdateClient.latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Kissmark", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                check = KissmarkUpdateCheck(
                    currentMarketingVersion: KissmarkAppVersion.marketing,
                    latest: nil
                )
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = String.kissmarkLocalized("업데이트를 확인하지 못했습니다.")
                return
            }
            check = try KissmarkUpdateClient.evaluate(
                current: KissmarkAppVersion.marketing,
                data: data
            )
        } catch {
            errorMessage = String.kissmarkLocalized("업데이트를 확인하지 못했습니다.")
        }
    }
}
