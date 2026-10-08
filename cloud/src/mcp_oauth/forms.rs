/// Parsed `application/x-www-form-urlencoded` pairs that keep repeated names.
///
/// Serde form extractors collapse or reject repeated keys, but the consent form repeats
/// `runtime` and OAuth requires rejecting repeated single-valued parameters.
#[derive(Clone, Debug, Default)]
pub struct FormFields {
    pairs: Vec<(String, String)>,
}

#[derive(Debug, Eq, PartialEq)]
pub struct RepeatedField(pub String);

impl FormFields {
    pub fn parse(input: &[u8]) -> Self {
        Self {
            pairs: url::form_urlencoded::parse(input)
                .map(|(name, value)| (name.into_owned(), value.into_owned()))
                .collect(),
        }
    }

    pub fn parse_query(query: Option<&str>) -> Self {
        Self::parse(query.unwrap_or_default().as_bytes())
    }

    /// Returns the single non-empty value of `name`, refusing a repeated parameter.
    pub fn get(&self, name: &str) -> Result<Option<&str>, RepeatedField> {
        let mut values = self
            .pairs
            .iter()
            .filter(|(key, _)| key == name)
            .map(|(_, value)| value.as_str());
        let first = values.next();
        if values.next().is_some() {
            return Err(RepeatedField(name.to_owned()));
        }
        Ok(first.filter(|value| !value.is_empty()))
    }

    pub fn all(&self, name: &str) -> Vec<&str> {
        self.pairs
            .iter()
            .filter(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
            .collect()
    }

    pub fn flag(&self, name: &str) -> bool {
        self.pairs
            .iter()
            .any(|(key, value)| key == name && !value.is_empty())
    }
}

#[cfg(test)]
mod tests {
    use super::FormFields;

    #[test]
    fn parses_repeated_runtime_checkboxes() {
        let form = FormFields::parse(
            b"request=abc&consent_token=t%2B1&runtime=r1&runtime=r%202&execute=1&action=approve",
        );
        assert_eq!(form.get("request"), Ok(Some("abc")));
        assert_eq!(form.get("consent_token"), Ok(Some("t+1")));
        assert_eq!(form.all("runtime"), vec!["r1", "r 2"]);
        assert!(form.flag("execute"));
        assert!(!form.flag("all_runtimes"));
        assert!(form.get("runtime").is_err());
        assert_eq!(form.get("missing"), Ok(None));
    }

    #[test]
    fn treats_empty_values_as_missing() {
        let form = FormFields::parse_query(Some("state=&scope=mcp%3Aread"));
        assert_eq!(form.get("state"), Ok(None));
        assert_eq!(form.get("scope"), Ok(Some("mcp:read")));
    }
}
