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
}

// MARK: - Type aliases

/// An authenticated session token. Using a named alias makes API surface
/// explicit and lets the compiler catch transposed token/code arguments.
typealias FraiseToken = String
