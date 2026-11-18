import MlisbKit
import SwiftUI

enum InspectorTab: String { case contents, problems }

/// The inspector: the table of contents, or the lint problems of the open document.
struct InspectorView: View {
    let document: Document
    let jump: (Heading) -> Void
    @AppStorage("inspectorTab") private var tab = InspectorTab.contents
    @State private var issues: [LintIssue] = []
    @State private var computed = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Contents").tag(InspectorTab.contents)
                Text(issues.isEmpty ? "Problems" : "Problems (\(issues.count))").tag(InspectorTab.problems)
            }
            .pickerStyle(.segmented).labelsHidden().padding(8)
            if tab == .contents {
                OutlineView(headings: Outline.headings(in: document.text), jump: jump)
            } else if issues.isEmpty {
                ContentUnavailableView("No problems found", systemImage: "checkmark.circle")
            } else {
                List(issues, id: \.range.location) { issue in
                    Button {
                        LineRequests.shared.pending = LineRequest(file: document.url, range: issue.range)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: Self.icon(issue.kind)).foregroundStyle(.orange)
                            Text(issue.message).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(issue.line)").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task(id: document.text) {
            if computed { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            let (text, url) = (document.text, document.url)
            issues = await Task.detached { DocumentLint.issues(in: text, fileURL: Self.lintURL(url)) }.value
            computed = true
        }
    }

    /// A file opened on its own gives the sandbox no access to its neighbours, so link checks would misfire.
    nonisolated static func lintURL(_ url: URL) -> URL? {
        (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) == nil ? nil : url
    }

    private static func icon(_ kind: LintIssue.Kind) -> String {
        switch kind {
        case .duplicateAnchor: "number"
        case .skippedHeadingLevel: "textformat.size"
        case .undefinedReference: "questionmark.circle"
        case .unclosedFence: "curlybraces"
        case .brokenAnchor: "link"
        case .brokenLink: "doc.badge.ellipsis"
        case .tableColumnMismatch: "tablecells"
        }
    }
}
