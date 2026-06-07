@_exported import Koma

/// Compatibility marker for the deprecated `KomaMacros` module.
///
/// Import `Koma` directly instead. Macro declarations are now exported from
/// the primary module.
@available(*, deprecated, message: "Import Koma instead; macro declarations are exported from the Koma module.")
public enum KomaMacrosCompatibility {}
