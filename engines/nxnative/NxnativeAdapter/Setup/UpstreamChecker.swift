import Foundation
import OortLibrary

struct UpstreamStatus: Codable, Equatable {
    public var repository: String
    public var status: String
    public var baseCommit: String
    public var upstreamCommit: String
    public var aheadBy: Int
    public var behindBy: Int
    public var totalCommits: Int
    public var commits: [UpstreamReview.Commit]
    public var compareURL: URL
    public var checkedAt: Date

    public var isUpToDate: Bool { aheadBy == 0 && behindBy == 0 }
    public var newCommitsCount: Int { max(aheadBy, totalCommits) }

    var review: UpstreamReview {
        .init(ReviewedRevision(UUID()), targetSHA: upstreamCommit, newCommitsCount: newCommitsCount,
              commits: commits,
              isUpToDate: isUpToDate)
    }

    public init(repository: String, status: String, baseCommit: String,
                upstreamCommit: String, aheadBy: Int, behindBy: Int,
                totalCommits: Int, commits: [UpstreamReview.Commit],
                compareURL: URL, checkedAt: Date) {
        self.repository = repository
        self.status = status
        self.baseCommit = baseCommit
        self.upstreamCommit = upstreamCommit
        self.aheadBy = aheadBy
        self.behindBy = behindBy
        self.totalCommits = totalCommits
        self.commits = commits
        self.compareURL = compareURL
        self.checkedAt = checkedAt
    }
}

public enum UpstreamCheckerError: Error, Equatable, LocalizedError {
    case invalidBase
    case invalidURL
    case http(Int, String?)
    case rateLimited(Date?)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .invalidBase:
            return L10n.text("The engine commit is not a valid hash.")
        case .invalidURL:
            return L10n.text("Could not build the GitHub API URL.")
        case .http(let status, let message):
            return L10n.format("GitHub returned status %@%@", [String(describing: status), String(describing: message.map { ": \($0)" } ?? ".")])
        case .rateLimited(let reset):
            if let reset {
                return L10n.format("GitHub API rate limit reached. Try again after %@.", [String(describing: reset.formatted(date: .abbreviated, time: .shortened))])
            }
            return L10n.text("GitHub API rate limit reached. Try again later.")
        case .decoding:
            return L10n.text("GitHub returned a response this app could not read.")
        }
    }
}

public protocol UpstreamHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionUpstreamClient: UpstreamHTTPClient, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

final class UpstreamChecker {
    public static let repository = "seedds/nxnative"
    public static let branch = "main"

    private let client: UpstreamHTTPClient

    public init(client: UpstreamHTTPClient = URLSessionUpstreamClient()) {
        self.client = client
    }

    func review(from base: String, persist: Bool) async throws(Refusal) -> UpstreamReview {
        do {
            let snapshot = try await check(from: base)
            if persist, let data = try? JSONEncoder().encode(snapshot) {
                AppData.preferences.set(data, forKey: Self.cacheKey)
            }
            return snapshot.review
        } catch let error as UpstreamCheckerError {
            switch error {
            case .invalidBase: throw .upstream(.invalidBase)
            case .invalidURL: throw .upstream(.invalidURL)
            case .decoding: throw .upstream(.decoding)
            case .rateLimited(let date): throw .upstream(.rateLimited(reset: date))
            case .http(let code, let message): throw .upstream(.http(code: code, message: message))
            }
        } catch is CancellationError {
            throw .cancelled
        } catch {
            if let urlError = error as? URLError {
                let text = URLError(urlError.code).localizedDescription
                throw .upstream(.connection(message: "Network error: \(text)"))
            }
            throw .upstream(.connection(message: L10n.text("unknown error")))
        }
    }

    static let cacheKey = "NXLibrary_UpstreamStatus"

    static func cachedReview(from base: String) -> UpstreamReview? {
        guard let data = AppData.preferences.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(UpstreamStatus.self, from: data),
              cached.baseCommit == base else { return nil }
        return cached.review
    }

    static func compareURL(from base: String) -> URL? {
        guard !base.isEmpty, base.allSatisfy(\.isHexDigit) else { return nil }
        return URL(string: "https://github.com/\(repository)/compare/\(base)...\(branch)")
    }

    private static func safeMessage(_ message: String?) -> String? {
        // Server text can carry arbitrary paths or credentials, even without a recognisable prefix.
        switch message {
        case "Not Found": return "Not Found"
        case "Bad credentials": return "Bad credentials"
        case "Forbidden": return "Forbidden"
        default: return nil
        }
    }

    public func check(from baseCommit: String) async throws -> UpstreamStatus {
        let base = baseCommit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, base.allSatisfy({ $0.isHexDigit }) else {
            throw UpstreamCheckerError.invalidBase
        }
        guard let apiURL = URL(
            string: "https://api.github.com/repos/\(Self.repository)/compare/\(base)...\(Self.branch)"
        ) else {
            throw UpstreamCheckerError.invalidURL
        }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(AppIdentity.userAgent(), forHTTPHeaderField: "User-Agent")

        let (data, http) = try await client.data(for: request)
        let message = (try? JSONDecoder().decode(APIError.self, from: data))?.message

        if http.statusCode == 403 || http.statusCode == 429,
           http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
            let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset")
                .flatMap(Double.init)
                .map { Date(timeIntervalSince1970: $0) }
            throw UpstreamCheckerError.rateLimited(reset)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpstreamCheckerError.http(http.statusCode, Self.safeMessage(message))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(ComparePayload.self, from: data) else {
            throw UpstreamCheckerError.decoding
        }

        let ahead = payload.aheadBy ?? 0
        let behind = payload.behindBy ?? 0
        let rawCommits = payload.commits ?? []
        let commits = rawCommits.reversed().prefix(100).map { item in
            let message = item.commit?.message ?? ""
            let subject = message.components(separatedBy: "\n").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return UpstreamReview.Commit(
                sha: item.sha,
                subject: subject.isEmpty ? "(no message)" : subject,
                author: item.commit?.author?.name ?? "unknown",
                date: item.commit?.author?.date ?? ""
            )
        }
        let upstream = rawCommits.last?.sha ?? payload.baseCommit?.sha ?? base
        guard let compareURL = Self.compareURL(from: base) else {
            throw UpstreamCheckerError.invalidURL
        }

        return UpstreamStatus(
            repository: Self.repository,
            status: payload.status ?? "unknown",
            baseCommit: payload.baseCommit?.sha ?? base,
            upstreamCommit: upstream,
            aheadBy: ahead,
            behindBy: behind,
            totalCommits: max(payload.totalCommits ?? ahead, ahead),
            commits: Array(commits),
            compareURL: compareURL,
            checkedAt: Date()
        )
    }
}

private struct ComparePayload: Decodable {
    let status: String?
    let aheadBy: Int?
    let behindBy: Int?
    let totalCommits: Int?
    let baseCommit: CommitRef?
    let commits: [CommitPayload]?
}

private struct CommitRef: Decodable {
    let sha: String
}

private struct CommitPayload: Decodable {
    let sha: String
    let commit: CommitDetail?
}

private struct CommitDetail: Decodable {
    let author: CommitAuthor?
    let message: String?
}

private struct CommitAuthor: Decodable {
    let name: String?
    let date: String?
}

private struct APIError: Decodable {
    let message: String?
}
