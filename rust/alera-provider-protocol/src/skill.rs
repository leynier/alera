//! Skills a provider offers, in the shape of T3 Code's `ServerProviderSkill`.
//! A person invokes one by typing `$name` in the composer; each adapter turns
//! that mention into its provider's native form when it sends the prompt, so
//! clients only insert the text.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// More than any provider lists today; a runaway list stays bounded on the wire.
pub const MAX_PROVIDER_SKILLS: usize = 500;
const MAX_NAME_CHARS: usize = 128;
const MAX_PATH_CHARS: usize = 4096;
const MAX_DESCRIPTION_CHARS: usize = 1024;
const MAX_SHORT_TEXT_CHARS: usize = 200;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderSkill {
    /// What follows the sigil, such as `review` or `plugin:deploy`.
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    /// Where the provider loads the skill from: a `SKILL.md` path, or an
    /// opaque locator such as `acp://skill/name` when it has no file.
    pub path: String,
    /// `user`, `project`, `repo`, `system`, `agent`, or a provider's own word.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scope: Option<String>,
    pub enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub short_description: Option<String>,
    /// Claude `disable-model-invocation`: only a person can invoke it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub user_invocation_only: Option<bool>,
    /// Claude `user-invocable: false`: only the agent can invoke it, so
    /// composers hide it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub user_invocable: Option<bool>,
}

impl ProviderSkill {
    /// A skill from native fields, or `None` for a name that cannot be typed
    /// as one token or a missing path. A leading `$` is dropped and blank
    /// texts are treated as absent.
    pub fn from_native(name: &str, path: &str, enabled: bool) -> Option<Self> {
        let name = name.trim();
        let name = name.strip_prefix('$').unwrap_or(name);
        let path = path.trim();
        if name.is_empty()
            || name.chars().count() > MAX_NAME_CHARS
            || name.chars().any(char::is_whitespace)
            || path.is_empty()
            || path.chars().count() > MAX_PATH_CHARS
        {
            return None;
        }
        Some(Self {
            name: name.to_string(),
            description: None,
            path: path.to_string(),
            scope: None,
            enabled,
            display_name: None,
            short_description: None,
            user_invocation_only: None,
            user_invocable: None,
        })
    }

    pub fn with_description(mut self, description: Option<&str>) -> Self {
        self.description = bounded_text(description, MAX_DESCRIPTION_CHARS);
        self
    }

    pub fn with_scope(mut self, scope: Option<&str>) -> Self {
        self.scope = bounded_text(scope, MAX_SHORT_TEXT_CHARS);
        self
    }

    pub fn with_display_name(mut self, display_name: Option<&str>) -> Self {
        self.display_name = bounded_text(display_name, MAX_SHORT_TEXT_CHARS);
        self
    }

    pub fn with_short_description(mut self, short_description: Option<&str>) -> Self {
        self.short_description = bounded_text(short_description, MAX_DESCRIPTION_CHARS);
        self
    }

    /// Records only the restrictive value, as T3 Code does: `true` for
    /// `userInvocationOnly`, `false` for `userInvocable`.
    pub fn with_invocation(mut self, user_invocation_only: bool, user_invocable: bool) -> Self {
        self.user_invocation_only = user_invocation_only.then_some(true);
        self.user_invocable = (!user_invocable).then_some(false);
        self
    }

    /// Whether a person can pick it: enabled and not agent-only.
    pub fn is_user_invocable(&self) -> bool {
        self.enabled && self.user_invocable != Some(false)
    }
}

fn bounded_text(text: Option<&str>, limit: usize) -> Option<String> {
    let text = text?.trim();
    (!text.is_empty()).then(|| text.chars().take(limit).collect())
}

/// [`ProviderSkill`]s with one entry per exact name, the first winning, as
/// the native loaders give precedence to the first root that defines a name.
pub fn normalize_skills(skills: impl IntoIterator<Item = ProviderSkill>) -> Vec<ProviderSkill> {
    let mut normalized: Vec<ProviderSkill> = Vec::new();
    for skill in skills {
        if normalized
            .iter()
            .any(|existing| existing.name == skill.name)
        {
            continue;
        }
        if normalized.len() == MAX_PROVIDER_SKILLS {
            break;
        }
        normalized.push(skill);
    }
    normalized
}

/// The payload of `session.skills.updated`. Each update replaces the whole
/// list; an empty list means the provider offers none right now.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderSkillsUpdate {
    #[serde(default)]
    pub skills: Vec<ProviderSkill>,
}

impl ProviderSkillsUpdate {
    pub fn new(skills: impl IntoIterator<Item = ProviderSkill>) -> Self {
        Self {
            skills: normalize_skills(skills),
        }
    }

    pub fn payload(&self) -> Value {
        json!({ "skills": self.skills })
    }
}
