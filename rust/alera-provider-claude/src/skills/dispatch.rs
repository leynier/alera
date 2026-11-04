//! Turning `$name` skill mentions into what Claude Code expands (T3 Code's
//! `ClaudeSkillDispatch`). Claude expands one skill per message, and only
//! when `/name` starts the last text block; everything after the name,
//! including newlines or a second `/x`, becomes its arguments.
//! https://github.com/anthropics/claude-code/issues/87113

use super::paths::{js_trim, js_trim_end};
use alera_provider_protocol::{skill_mentions, ProviderSkill};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClaudeSkillDispatch {
    /// The whole prompt with mentions as `/name`, or `None` when the mention
    /// opens it.
    pub leading_text: Option<String>,
    /// `/name` plus the trailing text, ready to be the message's last text block.
    pub command_text: String,
    pub skill_name: String,
}

/// The skills a person can invoke, keyed by name, as T3 Code filters them
/// before every send.
pub fn user_invocable_skills(
    skills: impl IntoIterator<Item = ProviderSkill>,
) -> HashMap<String, ProviderSkill> {
    skills
        .into_iter()
        .filter(ProviderSkill::is_user_invocable)
        .map(|skill| (skill.name.clone(), skill))
        .collect()
}

/// How [prompt] invokes one of [skills], or `None` when it mentions none.
pub fn plan_claude_skill_dispatch(
    prompt: &str,
    skills: &HashMap<String, ProviderSkill>,
) -> Option<ClaudeSkillDispatch> {
    let mentions: Vec<_> = skill_mentions(prompt)
        .into_iter()
        .filter_map(|mention| Some((skills.get(&mention.name)?, mention)))
        .collect();
    let (_, last) = mentions.last()?;
    // Only the final skill gets native expansion. Earlier user-only skills need
    // a fallback to their raw file because Claude's Skill tool refuses them.
    let mut annotated = HashSet::from([last.name.as_str()]);
    let mut inline = String::with_capacity(prompt.len());
    let mut cursor = 0;
    for (skill, mention) in &mentions {
        inline.push_str(&prompt[cursor..mention.start]);
        inline.push('/');
        inline.push_str(&mention.name);
        if skill.user_invocation_only == Some(true) && annotated.insert(mention.name.as_str()) {
            inline.push_str(" [The user invoked this skill. Follow the instructions at: ");
            inline.push_str(&skill.path);
            inline.push(']');
        }
        cursor = mention.end;
    }
    inline.push_str(&prompt[cursor..]);
    let leading_text =
        (!js_trim(&prompt[..last.start]).is_empty()).then(|| js_trim_end(&inline).to_string());
    let command_text = format!("/{}{}", last.name, &prompt[last.end..]);
    Some(ClaudeSkillDispatch {
        leading_text,
        command_text: js_trim_end(&command_text).to_string(),
        skill_name: last.name.clone(),
    })
}

/// The `message.content` of a Claude user message, as T3 Code's
/// `makeClaudeUserMessage` and `makeClaudeUserMessageWithAttachments` build
/// it. [media] is `None` for a message without attachments, else the image
/// and document blocks they produced. With a dispatch the content is
/// `[leading?, ...media, command]`, since media must precede the command
/// block for the skill to expand. Text alone without one stays a string.
pub fn claude_user_message_content(
    text: &str,
    media: Option<Vec<Value>>,
    skills: &HashMap<String, ProviderSkill>,
) -> Value {
    let dispatch = plan_claude_skill_dispatch(text, skills);
    let Some(media) = media else {
        return match dispatch {
            None => Value::String(text.to_string()),
            Some(dispatch) => Value::Array(
                dispatch
                    .leading_text
                    .iter()
                    .chain([&dispatch.command_text])
                    .map(|text| text_block(text))
                    .collect(),
            ),
        };
    };
    let mut content = Vec::with_capacity(media.len() + 2);
    if let Some(leading) = dispatch
        .as_ref()
        .and_then(|dispatch| dispatch.leading_text.as_deref())
    {
        content.push(text_block(leading));
    }
    content.extend(media);
    match &dispatch {
        Some(dispatch) => content.push(text_block(&dispatch.command_text)),
        None if !text.is_empty() => content.push(text_block(text)),
        None => {}
    }
    Value::Array(content)
}

fn text_block(text: &str) -> Value {
    json!({"type": "text", "text": text})
}
