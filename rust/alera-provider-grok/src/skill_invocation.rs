//! Grok expands only a leading `/name`, while composers insert `$name` from the
//! `grok inspect` catalog. The catalog is asked again on each such prompt so
//! other `$` text is left alone.

use crate::skills::discover_skills;
use crate::GrokProviderConfig;
use alera_provider_protocol::leading_skill_mention;

/// [text] with a leading `$name` written as `/name` when the catalog for
/// [config] lists that skill as enabled. Any failure leaves [text] unchanged.
pub async fn rewrite_leading_skill_mention(text: String, config: &GrokProviderConfig) -> String {
    let Some((name, rest)) = leading_skill_mention(&text) else {
        return text;
    };
    let known = discover_skills(config).await.is_ok_and(|skills| {
        skills
            .iter()
            .any(|skill| skill.enabled && skill.name == name)
    });
    if known {
        format!("/{name}{rest}")
    } else {
        text
    }
}
