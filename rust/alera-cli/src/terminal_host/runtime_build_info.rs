use std::borrow::Cow;

pub(crate) const RUNTIME_SURFACE: &str = "runtime";

pub(crate) fn version() -> &'static str {
    option_env!("ALERA_BUILD_VERSION").unwrap_or(env!("CARGO_PKG_VERSION"))
}

pub(crate) fn build() -> Option<&'static str> {
    match option_env!("ALERA_BUILD_COMMIT") {
        Some(value) if !value.is_empty() && value != "unknown" => Some(value),
        _ => None,
    }
}

pub(crate) fn release() -> Cow<'static, str> {
    match build() {
        Some(build) => Cow::Owned(format!("alera-runtime@{}+{build}", version())),
        None => Cow::Owned(format!("alera-runtime@{}", version())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runtime_release_uses_the_effective_build_version() {
        let release = release();
        assert!(release.starts_with(&format!("alera-runtime@{}", version())));
        if let Some(build) = build() {
            assert!(release.ends_with(&format!("+{build}")));
        }
    }
}
