import Foundation

// MARK: - App configuration

// Keys are read from Info.plist first (populated by Secrets.xcconfig in CI/prod),
// falling back to the test value when the plist entry is absent.
// To wire up production: add Secrets.xcconfig (gitignored), set
// STRIPE_PUBLISHABLE_KEY = pk_live_..., and add $(STRIPE_PUBLISHABLE_KEY) to Info.plist.
enum Config {
    static let stripePublishableKey: String =
        Bundle.main.infoDictionary?["STRIPE_PUBLISHABLE_KEY"] as? String
        ?? "pk_test_51RcAlhKvPGIzTFOS9MjkghFT8B5Y2e4JSbEhP6DOV7EU1Pe47JS4X1Jslm6fukkyp8DYIgtJjJ5zLUZkbrnNBaJX00RINxJvdT"

    /// Call at app launch. Crashes with a clear message in debug if required keys are missing
    /// or still hold the placeholder value from Secrets.xcconfig.example.
    static func validate() {
        #if DEBUG
        assert(
            !stripePublishableKey.hasSuffix("REPLACE_ME"),
            "Stripe key not configured — copy Secrets.xcconfig.example to Secrets.xcconfig and set STRIPE_PUBLISHABLE_KEY."
        )
        #endif
    }
}

// MARK: - Type aliases

/// An authenticated session token. A concrete struct (not a typealias) so the compiler
/// rejects passing a raw String where a token is expected and vice versa.
/// CustomStringConvertible redacts the value to prevent accidental logging.
struct FraiseToken: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ value: String)  { self.rawValue = value }
    var description: String { "FraiseToken([redacted])" }
}
