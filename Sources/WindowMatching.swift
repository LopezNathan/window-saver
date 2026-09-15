import Foundation

struct WindowMatchCandidate: Equatable {
    let accessibilityIdentifier: String?
    let documentURL: String?
    let normalizedTitle: String
    let role: String
    let subrole: String
}

enum WindowMatchDecision: Equatable { case match(Int), unmatched, ambiguous }

/// Pure, conservative matching policy. It deliberately never guesses among two windows.
enum WindowMatcher {
    static func select(_ key: WindowKey, from candidates: [WindowMatchCandidate]) -> WindowMatchDecision {
        if let identifier = key.accessibilityIdentifier, !identifier.isEmpty {
            return unique(candidates.enumerated().filter { $0.element.accessibilityIdentifier == identifier }.map(\.offset))
        }
        if let documentURL = key.documentURL, !documentURL.isEmpty {
            return unique(candidates.enumerated().filter { $0.element.documentURL == documentURL }.map(\.offset))
        }
        let sameKind = candidates.enumerated().filter { $0.element.role == key.role && $0.element.subrole == key.subrole }
        let sameTitle = sameKind.filter { $0.element.normalizedTitle == key.normalizedTitle }.map(\.offset)
        if !sameTitle.isEmpty { return unique(sameTitle) }

        // Browser tabs routinely change AXTitle. A role-only fallback is safe only when
        // the application exposes precisely one compatible top-level window.
        return unique(sameKind.map(\.offset))
    }
    private static func unique(_ indices: [Int]) -> WindowMatchDecision {
        switch indices.count { case 0: .unmatched; case 1: .match(indices[0]); default: .ambiguous }
    }
}
