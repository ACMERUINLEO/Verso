import Foundation
import Testing
import VersoBundleFormat
import VersoDomain

@Suite("OKF bundle format")
struct OKFBundleFormatTests {
    @Test("Export is deterministic and import preserves identity and unknown frontmatter")
    func deterministicRoundTrip() throws {
        let concept = OKFConceptDocument(
            conceptID: KnowledgeConceptID(
                rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
            ),
            revisionID: KnowledgeConceptRevisionID(
                rawValue: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
            ),
            exportPath: "concepts/example.md",
            type: "concept",
            title: "Example",
            description: "A stable example",
            resourceURI: nil,
            tags: ["phase0", "knowledge"],
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            unknownFrontmatter: ["extension-key": "preserved"],
            markdownBody: "See [another](another.md).\r\n"
        )
        let arguments = (
            BundleID(rawValue: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!),
            BundleVersionID(rawValue: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!)
        )

        let first = try OKFBundleFormat.export(
            bundleID: arguments.0,
            bundleVersionID: arguments.1,
            semanticVersion: "1.0.0",
            manifestVersion: 1,
            okfVersion: "0.1",
            title: "Test bundle",
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            concepts: [concept]
        )
        let second = try OKFBundleFormat.export(
            bundleID: arguments.0,
            bundleVersionID: arguments.1,
            semanticVersion: "1.0.0",
            manifestVersion: 1,
            okfVersion: "0.1",
            title: "Test bundle",
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            concepts: [concept]
        )

        #expect(first == second)
        #expect(OKFBundleFormat.validate(files: first.files).isValid)
        let imported = try OKFBundleFormat.importArtifact(files: first.files)
        let importedConcepts = try OKFBundleFormat.concepts(from: imported)
        #expect(importedConcepts.count == 1)
        #expect(importedConcepts[0].conceptID == concept.conceptID)
        #expect(importedConcepts[0].revisionID == concept.revisionID)
        #expect(imported.manifest.members[0].path == concept.exportPath)
        #expect(!concept.exportPath.contains(concept.conceptID.rawValue.uuidString))
        #expect(importedConcepts[0].unknownFrontmatter["extension-key"] == "preserved")
        #expect(importedConcepts[0].markdownBody == "See [another](another.md).")
    }

    @Test("Concept type is required by validation")
    func requiredType() throws {
        let artifact = try OKFBundleFormat.export(
            bundleID: BundleID(),
            bundleVersionID: BundleVersionID(),
            semanticVersion: "1.0.0",
            manifestVersion: 1,
            okfVersion: "0.1",
            title: "Missing type",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            concepts: [
                OKFConceptDocument(
                    conceptID: KnowledgeConceptID(),
                    revisionID: KnowledgeConceptRevisionID(),
                    exportPath: "concepts/missing-type.md",
                    type: "",
                    title: "Missing type",
                    description: "Validation must fail.",
                    resourceURI: nil,
                    tags: [],
                    modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    markdownBody: "Body"
                )
            ]
        )

        let report = OKFBundleFormat.validate(files: artifact.files)
        #expect(!report.isValid)
        #expect(report.issues.contains {
            $0.message.contains("Required frontmatter key 'type'")
        })
    }

    @Test("Internal links are rewritten without changing external links")
    func linkRewrite() {
        let result = OKFBundleFormat.rewriteInternalLinks(
            in: "[Local](old.md) [Anchor](old.md#part) [Web](https://example.com)",
            pathMapping: ["old.md": "concepts/new.md"]
        )
        #expect(
            result
                == "[Local](concepts/new.md) [Anchor](concepts/new.md#part) [Web](https://example.com)"
        )
    }

    @Test("Digest mismatch and unsafe paths are rejected")
    func rejectsInvalidArtifacts() throws {
        #expect(throws: OKFBundleFormatError.self) {
            _ = try OKFBundleFormat.export(
                bundleID: BundleID(),
                bundleVersionID: BundleVersionID(),
                semanticVersion: "1.0.0",
                manifestVersion: 1,
                okfVersion: "0.1",
                title: "Unsafe",
                createdAt: .now,
                concepts: [
                    OKFConceptDocument(
                        conceptID: KnowledgeConceptID(),
                        revisionID: KnowledgeConceptRevisionID(),
                        exportPath: "../secret.md",
                        type: "concept",
                        title: "Unsafe",
                        description: "Unsafe",
                        resourceURI: nil,
                        tags: [],
                        modifiedAt: .now,
                        markdownBody: "No"
                    )
                ]
            )
        }
    }
}
