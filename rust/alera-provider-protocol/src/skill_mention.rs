//! The `$name` skill mention grammar T3 Code's composers and adapters share
//! (`SKILL_MENTION_PATTERN` in `packages/shared/src/composerInlineTokens.ts`):
//! a currency sigil at the start of the text or after whitespace, then a name
//! of ASCII letters, digits, `:`, `_` and `-` that starts with a letter or
//! digit, contains a letter and ends at whitespace or the end of the text.
//! Amounts such as `$25`, `$2_000`, `$5k` or `$1e6` are never mentions.
//!
//! Clients insert `$name`; adapters rewrite it here into what their provider
//! expands, so the same prompt invokes the same skill on every surface.

/// One mention in a text. Offsets are byte offsets into that text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillMention {
    /// Where the sigil starts.
    pub start: usize,
    /// Where the name starts, just after the sigil.
    pub name_start: usize,
    /// Just after the name.
    pub end: usize,
    pub name: String,
}

/// JavaScript's `\s`, which the reference grammar is written in: Unicode
/// white space plus the byte order mark, without the next-line control.
pub fn is_mention_space(character: char) -> bool {
    (character.is_whitespace() && character != '\u{85}') || character == '\u{feff}'
}

fn is_name_char(character: char) -> bool {
    character.is_ascii_alphanumeric() || matches!(character, ':' | '_' | '-')
}

/// Unicode general category `Sc`, which `\p{Sc}` matches.
pub fn is_currency_sigil(character: char) -> bool {
    matches!(
        character,
        '$' | '\u{a2}'..='\u{a5}'
            | '\u{58f}'
            | '\u{60b}'
            | '\u{7fe}'..='\u{7ff}'
            | '\u{9f2}'..='\u{9f3}'
            | '\u{9fb}'
            | '\u{af1}'
            | '\u{bf9}'
            | '\u{e3f}'
            | '\u{17db}'
            | '\u{20a0}'..='\u{20c0}'
            | '\u{a838}'
            | '\u{fdfc}'
            | '\u{fe69}'
            | '\u{ff04}'
            | '\u{ffe0}'..='\u{ffe1}'
            | '\u{ffe5}'..='\u{ffe6}'
            | '\u{11fdd}'..='\u{11fe0}'
            | '\u{1e2ff}'
            | '\u{1ecb0}'
    )
}

/// `[0-9][0-9_]*(?:[kKmMbBtT]|[eE][0-9]+)?`, the amounts a sigil may precede.
fn is_amount(run: &str) -> bool {
    let bytes = run.as_bytes();
    if !bytes.first().is_some_and(u8::is_ascii_digit) {
        return false;
    }
    let mut index = 1;
    while index < bytes.len() && (bytes[index].is_ascii_digit() || bytes[index] == b'_') {
        index += 1;
    }
    let rest = &bytes[index..];
    match rest {
        [] => true,
        [suffix] => b"kKmMbBtT".contains(suffix),
        [b'e' | b'E', exponent @ ..] => exponent.iter().all(u8::is_ascii_digit),
        _ => false,
    }
}

/// Every mention in [text], in order.
pub fn skill_mentions(text: &str) -> Vec<SkillMention> {
    let mut mentions = Vec::new();
    let mut previous: Option<char> = None;
    let mut characters = text.char_indices().peekable();
    while let Some((start, character)) = characters.next() {
        let at_boundary = previous.is_none_or(is_mention_space);
        previous = Some(character);
        if !at_boundary || !is_currency_sigil(character) {
            continue;
        }
        let name_start = start + character.len_utf8();
        let run_length = text[name_start..]
            .find(|candidate: char| !is_name_char(candidate))
            .unwrap_or(text.len() - name_start);
        let end = name_start + run_length;
        let run = &text[name_start..end];
        let terminated = text[end..].chars().next().is_none_or(is_mention_space);
        if run.is_empty()
            || !terminated
            || !run.as_bytes()[0].is_ascii_alphanumeric()
            || !run.bytes().any(|byte| byte.is_ascii_alphabetic())
            || is_amount(run)
        {
            continue;
        }
        mentions.push(SkillMention {
            start,
            name_start,
            end,
            name: run.to_string(),
        });
        // The name is ASCII, so skipping it keeps `previous` exact.
        while characters.peek().is_some_and(|(index, _)| *index < end) {
            previous = characters.next().map(|(_, character)| character);
        }
    }
    mentions
}

/// [text] with each mention for which [replace] answers a prefix written as
/// that prefix and the name. Text outside the mentions is unchanged.
pub fn rewrite_skill_mentions(text: &str, mut replace: impl FnMut(&str) -> Option<char>) -> String {
    let mut rewritten = String::with_capacity(text.len());
    let mut cursor = 0;
    for mention in skill_mentions(text) {
        let Some(prefix) = replace(&mention.name) else {
            continue;
        };
        rewritten.push_str(&text[cursor..mention.start]);
        rewritten.push(prefix);
        rewritten.push_str(&mention.name);
        cursor = mention.end;
    }
    rewritten.push_str(&text[cursor..]);
    rewritten
}

/// Codex only parses `$name`, while composers accept any currency sigil
/// (`€review`), so every mention is written with `$` (T3 Code's
/// `codexSkillMentionText`).
pub fn dollar_skill_mentions(text: &str) -> String {
    rewrite_skill_mentions(text, |_| Some('$'))
}

/// The mention that opens [text] after optional white space, with the text
/// after it, such as `deploy` and ` ship it` for `$deploy ship it`.
pub fn leading_skill_mention(text: &str) -> Option<(String, &str)> {
    let first = text.find(|character: char| !is_mention_space(character))?;
    let mention = skill_mentions(text)
        .into_iter()
        .next()
        .filter(|mention| mention.start == first)?;
    Some((mention.name, &text[mention.end..]))
}
