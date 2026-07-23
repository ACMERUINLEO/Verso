import CryptoKit
import Foundation
import VersoDomain

public struct OKFConceptDocument: Codable, Equatable, Sendable {
    public let conceptID: KnowledgeConceptID
    public let revisionID: KnowledgeConceptRevisionID
    public let exportPath: String
    public let type: String
    public let title: String
    public let description: String
    public let resourceURI: String?
    public let tags: [String]
    public let modifiedAt: Date
    public let sourceRecordIDs: [SourceRecordID]
    public let referenceIDs: [ReferenceID]
    public let unknownFrontmatter: [String: String]
    public let markdownBody: String

    public init(
        conceptID: KnowledgeConceptID,
        revisionID: KnowledgeConceptRevisionID,
        exportPath: String,
        type: String,
        title: String,
        description: String,
        resourceURI: String?,
        tags: [String],
        modifiedAt: Date,
        sourceRecordIDs: [SourceRecordID] = [],
        referenceIDs: [ReferenceID] = [],
        unknownFrontmatter: [String: String] = [:],
        markdownBody: String
    ) {
        self.conceptID = conceptID
        self.revisionID = revisionID
        self.exportPath = exportPath
        self.type = type
        self.title = title
        self.description = description
        self.resourceURI = resourceURI
        self.tags = tags
        self.modifiedAt = modifiedAt
        self.sourceRecordIDs = sourceRecordIDs
        self.referenceIDs = referenceIDs
        self.unknownFrontmatter = unknownFrontmatter
        self.markdownBody = markdownBody
    }
}

public struct OKFBundleManifest: Codable, Equatable, Sendable {
    public struct Member: Codable, Equatable, Sendable {
        public let conceptID: KnowledgeConceptID
        public let revisionID: KnowledgeConceptRevisionID
        public let path: String

        public init(
            conceptID: KnowledgeConceptID,
            revisionID: KnowledgeConceptRevisionID,
            path: String
        ) {
            self.conceptID = conceptID
            self.revisionID = revisionID
            self.path = path
        }
    }

    public let manifestVersion: Int
    public let okfVersion: String
    public let bundleID: BundleID
    public let bundleVersionID: BundleVersionID
    public let semanticVersion: String
    public let title: String
    public let createdAt: Date
    public let contentDigest: String
    public let members: [Member]

    public init(
        manifestVersion: Int,
        okfVersion: String,
        bundleID: BundleID,
        bundleVersionID: BundleVersionID,
        semanticVersion: String,
        title: String,
        createdAt: Date,
        contentDigest: String,
        members: [Member]
    ) {
        self.manifestVersion = manifestVersion
        self.okfVersion = okfVersion
        self.bundleID = bundleID
        self.bundleVersionID = bundleVersionID
        self.semanticVersion = semanticVersion
        self.title = title
        self.createdAt = createdAt
        self.contentDigest = contentDigest
        self.members = members
    }
}

public struct OKFArtifact: Equatable, Sendable {
    public let manifest: OKFBundleManifest
    public let files: [String: Data]

    public init(manifest: OKFBundleManifest, files: [String: Data]) {
        self.manifest = manifest
        self.files = files
    }
}

public enum OKFValidationSeverity: String, Codable, Sendable {
    case warning
    case error
}

public struct OKFValidationIssue: Codable, Equatable, Sendable {
    public let path: String?
    public let severity: OKFValidationSeverity
    public let message: String

    public init(
        path: String?,
        severity: OKFValidationSeverity,
        message: String
    ) {
        self.path = path
        self.severity = severity
        self.message = message
    }
}

public struct OKFValidationReport: Codable, Equatable, Sendable {
    public let issues: [OKFValidationIssue]

    public var isValid: Bool {
        !issues.contains { $0.severity == .error }
    }

    public init(issues: [OKFValidationIssue]) {
        self.issues = issues
    }
}

public enum OKFBundleFormatError: Error, Equatable, Sendable {
    case invalidExportPath(String)
    case duplicateExportPath(String)
    case invalidUTF8(String)
    case missingManifest
    case invalidManifest
    case invalidFrontmatter(String)
    case digestMismatch(expected: String, actual: String)
}

public enum OKFBundleFormat {
    private static let manifestPath = "expert-manifest.json"
    private static let reservedKeys: Set<String> = [
        "verso-concept-id",
        "verso-revision-id",
        "verso-source-ids",
        "verso-reference-ids",
        "type",
        "title",
        "description",
        "resource",
        "tags",
        "modified"
    ]

    public static func export(
        bundleID: BundleID,
        bundleVersionID: BundleVersionID,
        semanticVersion: String,
        manifestVersion: Int,
        okfVersion: String,
        title: String,
        createdAt: Date,
        concepts: [OKFConceptDocument]
    ) throws -> OKFArtifact {
        let sortedConcepts = concepts.sorted {
            normalizedExportPath($0.exportPath) < normalizedExportPath($1.exportPath)
        }
        var files: [String: Data] = [:]
        var members: [OKFBundleManifest.Member] = []

        for concept in sortedConcepts {
            let relativePath = try validatedExportPath(concept.exportPath)
            let artifactPath = "okf/\(relativePath)"
            guard files[artifactPath] == nil else {
                throw OKFBundleFormatError.duplicateExportPath(relativePath)
            }
            files[artifactPath] = Data(render(concept).utf8)
            members.append(
                .init(
                    conceptID: concept.conceptID,
                    revisionID: concept.revisionID,
                    path: relativePath
                )
            )
        }

        files["okf/index.md"] = Data(renderIndex(title: title, members: members).utf8)
        files["okf/log.md"] = Data(renderLog(createdAt: createdAt, count: members.count).utf8)
        files["assets/manifest.json"] = Data(#"{"assets":[],"version":1}"#.utf8)
        files["reports/validation.json"] = Data(
            #"{"issues":[],"status":"valid","version":1}"#.utf8
        )
        files["reports/benchmark.json"] = Data(
            #"{"status":"not-run","version":1}"#.utf8
        )
        let digest = contentDigest(for: files)
        let manifest = OKFBundleManifest(
            manifestVersion: manifestVersion,
            okfVersion: okfVersion,
            bundleID: bundleID,
            bundleVersionID: bundleVersionID,
            semanticVersion: semanticVersion,
            title: title,
            createdAt: createdAt,
            contentDigest: digest,
            members: members
        )
        files[manifestPath] = try encodedManifest(manifest)
        return OKFArtifact(manifest: manifest, files: files)
    }

    public static func importArtifact(files: [String: Data]) throws -> OKFArtifact {
        guard let manifestData = files[manifestPath] else {
            throw OKFBundleFormatError.missingManifest
        }
        let manifest: OKFBundleManifest
        do {
            manifest = try decoder.decode(OKFBundleManifest.self, from: manifestData)
        } catch {
            throw OKFBundleFormatError.invalidManifest
        }
        let expected = contentDigest(for: files)
        guard manifest.contentDigest == expected else {
            throw OKFBundleFormatError.digestMismatch(
                expected: manifest.contentDigest,
                actual: expected
            )
        }
        return OKFArtifact(manifest: manifest, files: files)
    }

    public static func concepts(from artifact: OKFArtifact) throws -> [OKFConceptDocument] {
        try artifact.manifest.members.map { member in
            let path = "okf/\(member.path)"
            guard let data = artifact.files[path],
                  let text = String(data: data, encoding: .utf8) else {
                throw OKFBundleFormatError.invalidUTF8(path)
            }
            let parsed = try parseFrontmatter(text, path: path)
            guard let type = parsed.values["type"],
                  let title = parsed.values["title"],
                  let description = parsed.values["description"],
                  let modifiedText = parsed.values["modified"],
                  let modifiedAt = timestampFormatter.date(from: modifiedText) else {
                throw OKFBundleFormatError.invalidFrontmatter(path)
            }
            let conceptID = parsed.values["verso-concept-id"]
                .flatMap(UUID.init(uuidString:))
                .map(KnowledgeConceptID.init(rawValue:)) ?? member.conceptID
            let revisionID = parsed.values["verso-revision-id"]
                .flatMap(UUID.init(uuidString:))
                .map(KnowledgeConceptRevisionID.init(rawValue:)) ?? member.revisionID
            let unknown = parsed.values.filter { !reservedKeys.contains($0.key) }
            return OKFConceptDocument(
                conceptID: conceptID,
                revisionID: revisionID,
                exportPath: member.path,
                type: type,
                title: title,
                description: description,
                resourceURI: parsed.values["resource"],
                tags: parseTags(parsed.values["tags"]),
                modifiedAt: modifiedAt,
                sourceRecordIDs: parseUUIDList(
                    parsed.values["verso-source-ids"]
                ).map(SourceRecordID.init(rawValue:)),
                referenceIDs: parseUUIDList(
                    parsed.values["verso-reference-ids"]
                ).map(ReferenceID.init(rawValue:)),
                unknownFrontmatter: unknown,
                markdownBody: parsed.body
            )
        }
    }

    public static func validate(files: [String: Data]) -> OKFValidationReport {
        var issues: [OKFValidationIssue] = []
        let artifact: OKFArtifact
        do {
            artifact = try importArtifact(files: files)
        } catch {
            return OKFValidationReport(
                issues: [
                    OKFValidationIssue(
                        path: manifestPath,
                        severity: .error,
                        message: String(describing: error)
                    )
                ]
            )
        }

        var seen: Set<String> = []
        for member in artifact.manifest.members {
            do {
                let path = try validatedExportPath(member.path)
                if !seen.insert(path).inserted {
                    issues.append(
                        .init(
                            path: path,
                            severity: .error,
                            message: "Duplicate member path."
                        )
                    )
                }
                guard let data = files["okf/\(path)"],
                      let text = String(data: data, encoding: .utf8) else {
                    issues.append(
                        .init(
                            path: path,
                            severity: .error,
                            message: "Member file is missing or not UTF-8."
                        )
                    )
                    continue
                }
                let parsed = try parseFrontmatter(text, path: path)
                for key in ["type", "title", "description", "modified"]
                where parsed.values[key]?.isEmpty != false {
                    issues.append(
                        .init(
                            path: path,
                            severity: .error,
                            message: "Required frontmatter key '\(key)' is missing."
                        )
                    )
                }
            } catch {
                issues.append(
                    .init(
                        path: member.path,
                        severity: .error,
                        message: String(describing: error)
                    )
                )
            }
        }
        return OKFValidationReport(issues: issues)
    }

    public static func rewriteInternalLinks(
        in markdown: String,
        pathMapping: [String: String]
    ) -> String {
        pathMapping
            .sorted { $0.key.count > $1.key.count }
            .reduce(normalizeNewlines(markdown)) { result, item in
                result
                    .replacingOccurrences(of: "](\(item.key))", with: "](\(item.value))")
                    .replacingOccurrences(
                        of: "](\(item.key)#",
                        with: "](\(item.value)#"
                    )
            }
    }

    public static func contentDigest(for files: [String: Data]) -> String {
        var hasher = SHA256()
        for path in files.keys
            .filter({ $0 != manifestPath })
            .sorted() {
            hasher.update(data: Data(path.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: files[path] ?? Data())
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func render(_ concept: OKFConceptDocument) -> String {
        var lines = [
            "---",
            "verso-concept-id: \(quote(concept.conceptID.rawValue.uuidString.lowercased()))",
            "verso-revision-id: \(quote(concept.revisionID.rawValue.uuidString.lowercased()))",
            "type: \(quote(concept.type))",
            "title: \(quote(concept.title))",
            "description: \(quote(concept.description))"
        ]
        if let resourceURI = concept.resourceURI {
            lines.append("resource: \(quote(resourceURI))")
        }
        lines.append("tags: \(renderTags(concept.tags))")
        lines.append(
            "verso-source-ids: \(renderUUIDList(concept.sourceRecordIDs.map(\.rawValue)))"
        )
        lines.append(
            "verso-reference-ids: \(renderUUIDList(concept.referenceIDs.map(\.rawValue)))"
        )
        lines.append("modified: \(quote(timestampFormatter.string(from: concept.modifiedAt)))")
        for key in concept.unknownFrontmatter.keys
            .filter({ !reservedKeys.contains($0) })
            .sorted() {
            lines.append("\(key): \(quote(concept.unknownFrontmatter[key] ?? ""))")
        }
        lines.append("---")
        lines.append("")
        lines.append(normalizeNewlines(concept.markdownBody).trimmingCharacters(in: .newlines))
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderIndex(
        title: String,
        members: [OKFBundleManifest.Member]
    ) -> String {
        var lines = ["# \(title)", ""]
        lines += members.map { "- [\($0.path)](\($0.path))" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderLog(createdAt: Date, count: Int) -> String {
        """
        # Export log

        - Created: \(timestampFormatter.string(from: createdAt))
        - Members: \(count)

        """
    }

    private static func validatedExportPath(_ path: String) throws -> String {
        let normalized = normalizedExportPath(path)
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.contains("\0"),
              !normalized.split(separator: "/").contains(".."),
              normalized.hasSuffix(".md"),
              normalized != "index.md",
              normalized != "log.md" else {
            throw OKFBundleFormatError.invalidExportPath(path)
        }
        return normalized
    }

    private static func normalizedExportPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
    }

    private static func parseFrontmatter(
        _ text: String,
        path: String
    ) throws -> (values: [String: String], body: String) {
        let normalized = normalizeNewlines(text)
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first == "---",
              let closing = lines.dropFirst().firstIndex(of: "---") else {
            throw OKFBundleFormatError.invalidFrontmatter(path)
        }
        var values: [String: String] = [:]
        for line in lines[1..<closing] {
            guard let colon = line.firstIndex(of: ":") else {
                throw OKFBundleFormatError.invalidFrontmatter(path)
            }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let raw = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                throw OKFBundleFormatError.invalidFrontmatter(path)
            }
            values[key] = unquote(raw)
        }
        let bodyStart = lines.index(after: closing)
        var body = lines[bodyStart...].joined(separator: "\n")
        body = body.trimmingCharacters(in: .newlines)
        return (values, body)
    }

    private static func renderTags(_ tags: [String]) -> String {
        "[" + tags.sorted().map(quote).joined(separator: ", ") + "]"
    }

    private static func parseTags(_ value: String?) -> [String] {
        guard let value,
              value.hasPrefix("["),
              value.hasSuffix("]") else {
            return []
        }
        return value.dropFirst().dropLast().split(separator: ",").map {
            unquote(String($0).trimmingCharacters(in: .whitespaces))
        }
    }

    private static func renderUUIDList(_ values: [UUID]) -> String {
        "[" + values
            .map { $0.uuidString.lowercased() }
            .sorted()
            .map(quote)
            .joined(separator: ", ") + "]"
    }

    private static func parseUUIDList(_ value: String?) -> [UUID] {
        parseTags(value)
            .compactMap(UUID.init(uuidString:))
            .sorted { $0.uuidString < $1.uuidString }
    }

    private static func quote(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private static func unquote(_ value: String) -> String {
        guard value.hasPrefix("\""),
              value.hasSuffix("\""),
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else {
            return value
        }
        return decoded
    }

    private static func normalizeNewlines(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func encodedManifest(_ manifest: OKFBundleManifest) throws -> Data {
        try encoder.encode(manifest)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var timestampFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
