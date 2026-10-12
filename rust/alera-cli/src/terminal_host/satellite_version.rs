//! How a satellite's runtime version compares with the hub's, which decides
//! whether the hub offers Update Runtime for a host.
//!
//! Versions are compared on their numeric components only (`1.4`, `v1.4.2`,
//! `1.4.2-rc.1+abc`), without a semver dependency. Only a satellite that is
//! strictly older than a parseable hub version counts as outdated, so a
//! development hub (whose version is the crate's `0.1.0`) never offers to
//! downgrade a host running a release.

/// The satellite's version relative to the hub's.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SatelliteVersionRelation {
    Older,
    Same,
    Newer,
    Unknown,
}

struct ParsedVersion<'a> {
    numbers: Vec<u64>,
    pre_release: Option<&'a str>,
}

fn parse(version: &str) -> Option<ParsedVersion<'_>> {
    let trimmed = version.trim();
    let trimmed = trimmed
        .strip_prefix('v')
        .or_else(|| trimmed.strip_prefix('V'))
        .unwrap_or(trimmed);
    let without_build = trimmed.split('+').next().unwrap_or_default();
    let (core, pre_release) = match without_build.split_once('-') {
        Some((core, suffix)) => (core, Some(suffix).filter(|suffix| !suffix.is_empty())),
        None => (without_build, None),
    };
    if core.is_empty() {
        return None;
    }
    let numbers = core
        .split('.')
        .map(|part| part.parse::<u64>().ok())
        .collect::<Option<Vec<_>>>()?;
    Some(ParsedVersion {
        numbers,
        pre_release,
    })
}

/// Compares `satellite` with `hub`. A version that does not parse on either
/// side is `Unknown`, and so are two different pre-release suffixes on the
/// same numbers, because their order is not knowable without semver rules.
pub(crate) fn relation(hub: &str, satellite: &str) -> SatelliteVersionRelation {
    let (Some(hub), Some(satellite)) = (parse(hub), parse(satellite)) else {
        return SatelliteVersionRelation::Unknown;
    };
    let width = hub.numbers.len().max(satellite.numbers.len());
    for index in 0..width {
        let hub_part = hub.numbers.get(index).copied().unwrap_or(0);
        let satellite_part = satellite.numbers.get(index).copied().unwrap_or(0);
        match satellite_part.cmp(&hub_part) {
            std::cmp::Ordering::Less => return SatelliteVersionRelation::Older,
            std::cmp::Ordering::Greater => return SatelliteVersionRelation::Newer,
            std::cmp::Ordering::Equal => {}
        }
    }
    match (hub.pre_release, satellite.pre_release) {
        (None, None) => SatelliteVersionRelation::Same,
        // A pre-release precedes the release with the same numbers.
        (None, Some(_)) => SatelliteVersionRelation::Older,
        (Some(_), None) => SatelliteVersionRelation::Newer,
        (Some(hub), Some(satellite)) if hub == satellite => SatelliteVersionRelation::Same,
        (Some(_), Some(_)) => SatelliteVersionRelation::Unknown,
    }
}

/// Whether the hub offers to update a satellite reporting `satellite`.
pub(crate) fn runtime_update_available(hub: &str, satellite: Option<&str>) -> bool {
    satellite.is_some_and(|satellite| relation(hub, satellite) == SatelliteVersionRelation::Older)
}

#[cfg(test)]
mod tests {
    use super::SatelliteVersionRelation::{Newer, Older, Same, Unknown};
    use super::*;

    #[test]
    fn compares_numeric_components() {
        assert_eq!(relation("1.4.2", "1.4.1"), Older);
        assert_eq!(relation("1.4.2", "1.4.2"), Same);
        assert_eq!(relation("1.4.2", "1.10.0"), Newer);
        assert_eq!(relation("1.10.0", "1.9.9"), Older);
        assert_eq!(relation("2.0", "1.99.99"), Older);
        assert_eq!(relation("1.4", "1.4.0"), Same);
        assert_eq!(relation("1.4.0.1", "1.4"), Older);
    }

    #[test]
    fn tolerates_prefixes_suffixes_and_build_metadata() {
        assert_eq!(relation("v1.4.2", "1.4.2"), Same);
        assert_eq!(relation("1.4.2", "V1.4.1"), Older);
        assert_eq!(relation("1.4.2+abc123", "1.4.2+def456"), Same);
        assert_eq!(relation("1.4.2", "1.4.2-rc.1"), Older);
        assert_eq!(relation("1.4.2-rc.1", "1.4.2"), Newer);
        assert_eq!(relation("1.4.2-rc.1", "1.4.2-rc.1"), Same);
        assert_eq!(relation("1.4.2-rc.2", "1.4.2-rc.1"), Unknown);
        assert_eq!(relation("1.5.0-rc.1", "1.4.9"), Older);
        assert_eq!(relation(" 1.4.2 ", "1.4.2\n"), Same);
    }

    #[test]
    fn anything_that_does_not_parse_is_unknown() {
        assert_eq!(relation("dev", "1.4.2"), Unknown);
        assert_eq!(relation("1.4.2", "local"), Unknown);
        assert_eq!(relation("", "1.4.2"), Unknown);
        assert_eq!(relation("1.4.x", "1.4.2"), Unknown);
        assert_eq!(relation("1..2", "1.4.2"), Unknown);
        assert_eq!(relation("v", "1.4.2"), Unknown);
    }

    #[test]
    fn only_an_older_satellite_offers_an_update() {
        assert!(runtime_update_available("1.5.0", Some("1.4.2")));
        assert!(!runtime_update_available("1.5.0", Some("1.5.0")));
        assert!(!runtime_update_available("1.5.0", None));
        assert!(!runtime_update_available("not-a-version", Some("1.4.2")));
        // A development hub reports the crate version and never offers a
        // downgrade to a host on a release.
        assert!(!runtime_update_available("0.1.0", Some("1.4.2")));
        // A release hub offers the update to a host still on a dev build.
        assert!(runtime_update_available("1.4.2", Some("0.1.0")));
    }
}
