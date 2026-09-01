import Foundation

extension URL {
    /// Creates security-scoped bookmark data for App Sandbox persistence.
    func securityScopedBookmark(readOnly: Bool = true) throws -> Data {
        let options: BookmarkCreationOptions = readOnly
            ? [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
            : [.withSecurityScope]
        return try bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
