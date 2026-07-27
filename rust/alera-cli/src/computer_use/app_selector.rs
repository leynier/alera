use crate::computer_use::contract::AppInfo;
use crate::computer_use::error::{ComputerError, ComputerResult};

/// How an agent names the app it wants to drive.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AppSelector {
    /// `pid:1234`, or a bare number. Unambiguous, and the only way to separate
    /// two instances of the same application.
    Pid(u32),
    /// A bundle identifier or a display name. Which one it is only matters when
    /// matching, so the parser keeps the text as written.
    Query(String),
}

/// How well a candidate app matched, so the caller can prefer an exact hit over
/// a substring one instead of taking whichever app it happened to visit first.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum MatchQuality {
    NameContains,
    NameExact,
    BundleIdExact,
    Pid,
}

impl AppSelector {
    pub fn parse(raw: &str) -> ComputerResult<Self> {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            return Err(ComputerError::invalid_argument(
                "An app selector is required: pass a name, a bundle id, or pid:<number>.",
            ));
        }
        if let Some(rest) = trimmed.strip_prefix("pid:") {
            return parse_pid(rest);
        }
        // A bare number is a pid. No desktop app is named by digits alone, and
        // reading it as a name would silently scan every app for "1234".
        if trimmed.chars().all(|c| c.is_ascii_digit()) {
            return parse_pid(trimmed);
        }
        Ok(AppSelector::Query(trimmed.to_string()))
    }

    pub fn matches(&self, app: &AppInfo) -> Option<MatchQuality> {
        match self {
            AppSelector::Pid(pid) => (*pid == app.pid).then_some(MatchQuality::Pid),
            AppSelector::Query(query) => match_query(query, app),
        }
    }

    /// The selector as the agent wrote it, for error messages that echo the
    /// input rather than a normalized form the agent never typed.
    pub fn describe(&self) -> String {
        match self {
            AppSelector::Pid(pid) => format!("pid:{pid}"),
            AppSelector::Query(query) => query.clone(),
        }
    }
}

fn parse_pid(raw: &str) -> ComputerResult<AppSelector> {
    match raw.trim().parse::<u32>() {
        Ok(pid) if pid > 0 => Ok(AppSelector::Pid(pid)),
        _ => Err(ComputerError::invalid_argument(format!(
            "`{raw}` is not a process id. Use pid:<positive number>."
        ))),
    }
}

fn match_query(query: &str, app: &AppInfo) -> Option<MatchQuality> {
    let needle = query.to_lowercase();
    if let Some(bundle_id) = &app.bundle_id {
        if bundle_id.to_lowercase() == needle {
            return Some(MatchQuality::BundleIdExact);
        }
    }
    let name = app.name.to_lowercase();
    if name == needle {
        return Some(MatchQuality::NameExact);
    }
    if name.contains(&needle) {
        return Some(MatchQuality::NameContains);
    }
    None
}

/// Pick the best match, or report that nothing matched.
///
/// Ties on quality are resolved by lowest pid so repeated calls with the same
/// ambiguous selector keep landing on the same app.
pub fn resolve_app<'a>(selector: &AppSelector, apps: &'a [AppInfo]) -> ComputerResult<&'a AppInfo> {
    apps.iter()
        .filter_map(|app| selector.matches(app).map(|quality| (quality, app)))
        .min_by(|(left_quality, left), (right_quality, right)| {
            right_quality
                .cmp(left_quality)
                .then_with(|| left.pid.cmp(&right.pid))
        })
        .map(|(_, app)| app)
        .ok_or_else(|| {
            ComputerError::new(
                crate::computer_use::error::ComputerErrorCode::AppNotFound,
                format!("No running app matched `{}`.", selector.describe()),
            )
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app(name: &str, bundle_id: Option<&str>, pid: u32) -> AppInfo {
        AppInfo {
            name: name.to_string(),
            bundle_id: bundle_id.map(str::to_string),
            pid,
        }
    }

    #[test]
    fn a_prefixed_pid_is_parsed() {
        assert_eq!(
            AppSelector::parse("pid:1234").unwrap(),
            AppSelector::Pid(1234)
        );
    }

    #[test]
    fn a_bare_number_is_a_pid() {
        assert_eq!(AppSelector::parse("1234").unwrap(), AppSelector::Pid(1234));
    }

    #[test]
    fn a_name_or_bundle_id_stays_a_query() {
        assert_eq!(
            AppSelector::parse("  Spotify ").unwrap(),
            AppSelector::Query("Spotify".to_string())
        );
        assert_eq!(
            AppSelector::parse("com.spotify.client").unwrap(),
            AppSelector::Query("com.spotify.client".to_string())
        );
    }

    #[test]
    fn nonsense_pids_and_empty_selectors_are_rejected() {
        assert!(AppSelector::parse("").is_err());
        assert!(AppSelector::parse("   ").is_err());
        assert!(AppSelector::parse("pid:0").is_err());
        assert!(AppSelector::parse("pid:abc").is_err());
        assert!(AppSelector::parse("pid:-2").is_err());
    }

    #[test]
    fn matching_is_case_insensitive_across_names_and_bundle_ids() {
        let spotify = app("Spotify", Some("com.spotify.client"), 10);
        assert_eq!(
            AppSelector::parse("COM.SPOTIFY.CLIENT")
                .unwrap()
                .matches(&spotify),
            Some(MatchQuality::BundleIdExact)
        );
        assert_eq!(
            AppSelector::parse("spotify").unwrap().matches(&spotify),
            Some(MatchQuality::NameExact)
        );
        assert_eq!(
            AppSelector::parse("spot").unwrap().matches(&spotify),
            Some(MatchQuality::NameContains)
        );
        assert_eq!(AppSelector::parse("slack").unwrap().matches(&spotify), None);
    }

    /// A substring hit must never beat an app whose real name is the query, or
    /// `--app Code` would open "Visual Studio Code - Insiders" instead of Code.
    #[test]
    fn an_exact_name_wins_over_a_substring() {
        let apps = vec![
            app("Visual Studio Code - Insiders", None, 20),
            app("Code", None, 21),
        ];
        let selector = AppSelector::parse("Code").unwrap();
        assert_eq!(resolve_app(&selector, &apps).unwrap().pid, 21);
    }

    #[test]
    fn a_bundle_id_wins_over_a_name() {
        let apps = vec![
            app("com.example.editor", None, 30),
            app("Editor", Some("com.example.editor"), 31),
        ];
        let selector = AppSelector::parse("com.example.editor").unwrap();
        assert_eq!(resolve_app(&selector, &apps).unwrap().pid, 31);
    }

    /// Two windows of the same app must resolve the same way every call, or an
    /// agent's element indexes silently start describing the other instance.
    #[test]
    fn ties_resolve_to_the_lowest_pid() {
        let apps = vec![app("Terminal", None, 99), app("Terminal", None, 42)];
        let selector = AppSelector::parse("Terminal").unwrap();
        assert_eq!(resolve_app(&selector, &apps).unwrap().pid, 42);
    }

    #[test]
    fn resolving_nothing_reports_app_not_found_and_echoes_the_selector() {
        let apps = vec![app("Spotify", None, 10)];
        let selector = AppSelector::parse("Gmail").unwrap();
        let error = resolve_app(&selector, &apps).unwrap_err();
        assert_eq!(
            error.code,
            crate::computer_use::error::ComputerErrorCode::AppNotFound
        );
        assert!(error.message.contains("Gmail"));
    }

    #[test]
    fn a_pid_selector_matches_only_that_process() {
        let apps = vec![app("Terminal", None, 42), app("Terminal", None, 43)];
        let selector = AppSelector::parse("pid:43").unwrap();
        assert_eq!(resolve_app(&selector, &apps).unwrap().pid, 43);
    }
}
