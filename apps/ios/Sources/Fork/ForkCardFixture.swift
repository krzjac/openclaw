import Foundation
import OpenClawKit

/// Fork: `--openclaw-ocard-fixture` seeds the screenshot chat with sample day-thread cards.
enum ForkCardFixture {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--openclaw-ocard-fixture")
    }

    static func seed() -> [(role: String, text: String)] {
        OpenClawOCardPreview.entries().map { (role: $0.role, text: $0.text) }
    }
}
