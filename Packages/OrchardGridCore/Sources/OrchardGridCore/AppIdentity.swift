// MARK: - AppIdentity
//
// Single source of truth for product-identity strings shared by the
// menu-bar app, the `og` CLI, and anywhere else on-wire identifiers
// appear. Keeping these here means the OpenAPI spec, CLI display,
// HTTP request bodies, and server responses all reference one
// constant — changes require touching exactly one file.

public enum AppIdentity {
  /// Canonical model identifier sent in `chat/completions` requests
  /// and returned in responses. Matches Apple's internal engineering
  /// name for the on-device LLM that backs FoundationModels, rather
  /// than the OS-setting term "Apple Intelligence" (which also covers
  /// Writing Tools, Genmoji, etc. — none of which this API exposes).
  public static let modelName = "apple-foundationmodel"

  /// The command-line tool's executable name.
  public static let cliName = "og"
}
