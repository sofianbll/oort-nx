#if DEBUG
/// Offscreen probes only (apps/mac/Tests/CatalogAppChecks): what some views draw, as they draw it. Each is nil until a
/// probe sets it, and nothing in the app reads them; Release builds do not contain this type.
@MainActor enum OortProbeObserver {
    /// An action bar key: title, focused, enabled.
    static var actionKey: ((String, Bool, Bool) -> Void)?
    /// A status dot's text.
    static var statusText: ((String) -> Void)?
}
#endif
