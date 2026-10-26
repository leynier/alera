use alera_provider_protocol::{
    compare_skill_names, dollar_skill_mentions, leading_skill_mention,
    parse_skill_frontmatter_yaml, rewrite_skill_mentions, skill_frontmatter_block,
    skill_frontmatter_flag, skill_mentions, EventKind, ProviderEvent, ProviderKind, ProviderSkill,
    ProviderSkillsUpdate, MAX_PROVIDER_SKILLS,
};
use serde_json::json;

fn names(text: &str) -> Vec<String> {
    skill_mentions(text)
        .into_iter()
        .map(|mention| mention.name)
        .collect()
}

#[test]
fn mention_grammar_matches_t3_code() {
    assert_eq!(names("$review"), ["review"]);
    assert_eq!(names("use $review now"), ["review"]);
    assert_eq!(names("€review and £deploy"), ["review", "deploy"]);
    assert_eq!(names("$plugin:deploy-app_2 x"), ["plugin:deploy-app_2"]);
    assert_eq!(names("$a $b"), ["a", "b"]);
    assert_eq!(names("tab\t$x\n$y"), ["x", "y"]);
    // Amounts and mid-word sigils are text.
    for text in [
        "$25",
        "$2_000",
        "$5k",
        "$5K",
        "$1e6",
        "price$tag",
        "$-x",
        "$_x",
        "$9",
        "$",
    ] {
        assert!(names(text).is_empty(), "{text}");
    }
    // A name must end at whitespace or the end of the text.
    assert!(names("$review.").is_empty());
    assert!(names("($review)").is_empty());
    assert_eq!(names("$5kb"), ["5kb"]);
    assert_eq!(names("$1e6x"), ["1e6x"]);
    assert_eq!(names("$x1"), ["x1"]);
}

#[test]
fn mention_offsets_are_byte_offsets() {
    let mentions = skill_mentions("añ €review");
    assert_eq!(mentions.len(), 1);
    let mention = &mentions[0];
    assert_eq!(&"añ €review"[mention.start..mention.end], "€review");
    assert_eq!(&"añ €review"[mention.name_start..mention.end], "review");
}

#[test]
fn codex_writes_every_mention_with_a_dollar() {
    assert_eq!(dollar_skill_mentions("€review and $5"), "$review and $5");
    assert_eq!(dollar_skill_mentions("no mention"), "no mention");
}

#[test]
fn rewriting_keeps_unknown_mentions() {
    let rewritten =
        rewrite_skill_mentions("$known and $other", |name| (name == "known").then_some('/'));
    assert_eq!(rewritten, "/known and $other");
}

#[test]
fn leading_mention_needs_the_mention_first() {
    assert_eq!(
        leading_skill_mention("  $deploy ship it"),
        Some(("deploy".to_string(), " ship it"))
    );
    assert_eq!(
        leading_skill_mention("$deploy"),
        Some(("deploy".into(), ""))
    );
    assert_eq!(leading_skill_mention("please $deploy"), None);
    assert_eq!(leading_skill_mention("$25 $deploy"), None);
}

#[test]
fn skills_normalize_and_bound() {
    let skill = ProviderSkill::from_native(" $review ", "/s/SKILL.md", true)
        .unwrap()
        .with_description(Some("  "))
        .with_scope(Some("user"))
        .with_invocation(true, false);
    assert_eq!(skill.name, "review");
    assert_eq!(skill.description, None);
    assert_eq!(skill.user_invocation_only, Some(true));
    assert_eq!(skill.user_invocable, Some(false));
    assert!(!skill.is_user_invocable());
    assert!(ProviderSkill::from_native("two words", "/p", true).is_none());
    assert!(ProviderSkill::from_native("x", " ", true).is_none());

    let update = ProviderSkillsUpdate::new(
        (0..MAX_PROVIDER_SKILLS + 5)
            .map(|index| ProviderSkill::from_native(&format!("s{index}"), "/p", true).unwrap())
            .chain([ProviderSkill::from_native("s0", "/other", true).unwrap()]),
    );
    assert_eq!(update.skills.len(), MAX_PROVIDER_SKILLS);
    assert_eq!(update.skills[0].path, "/p");
}

#[test]
fn skills_event_validates_and_round_trips() {
    let skill = ProviderSkill::from_native("review", "/s/SKILL.md", true)
        .unwrap()
        .with_display_name(Some("Review"))
        .with_short_description(Some("Reviews"));
    let update = ProviderSkillsUpdate::new([skill]);
    assert_eq!(
        update.payload(),
        json!({"skills":[{"name":"review","path":"/s/SKILL.md","enabled":true,"displayName":"Review","shortDescription":"Reviews"}]})
    );
    let event = ProviderEvent::new(
        ProviderKind::Codex,
        "codex",
        "thread",
        EventKind::SessionSkillsUpdated,
        update.payload(),
        None,
    );
    event.validate().unwrap();
    assert_eq!(
        EventKind::SessionSkillsUpdated.as_str(),
        "session.skills.updated"
    );
    let invalid = ProviderEvent::new(
        ProviderKind::Codex,
        "codex",
        "thread",
        EventKind::SessionSkillsUpdated,
        json!({"skills":[{"name":"x","path":"","enabled":true}]}),
        None,
    );
    assert!(invalid.validate().is_err());
}

#[test]
fn frontmatter_block_follows_the_reference_pattern() {
    assert_eq!(
        skill_frontmatter_block("---\nname: x\n---\nbody"),
        Some("name: x")
    );
    assert_eq!(
        skill_frontmatter_block("---\r\nname: x\r\n---\r\n"),
        Some("name: x")
    );
    assert_eq!(
        skill_frontmatter_block("---\nname: x\n---"),
        Some("name: x")
    );
    assert_eq!(skill_frontmatter_block("---\n\n---\n"), Some(""));
    assert_eq!(
        skill_frontmatter_block("---\nname: x\n----\nmore\n---\n"),
        Some("name: x\n----\nmore")
    );
    assert_eq!(skill_frontmatter_block("# Title\n---\n"), None);
    assert_eq!(skill_frontmatter_block("---\nname: x\n"), None);
}

#[test]
fn frontmatter_yaml_reads_as_json() {
    let value = parse_skill_frontmatter_yaml(
        "name: x\ncount: 2\nflag: yes\nlist: [a, b]\nnested:\n  k: true",
    )
    .unwrap();
    assert_eq!(
        value,
        json!({"name":"x","count":2,"flag":"yes","list":["a","b"],"nested":{"k":true}})
    );
    assert_eq!(
        parse_skill_frontmatter_yaml("").unwrap(),
        serde_json::Value::Null
    );
    assert!(parse_skill_frontmatter_yaml("a: b: c").is_err());
    assert_eq!(skill_frontmatter_flag(value.get("flag"), false), Some(true));
    assert_eq!(skill_frontmatter_flag(Some(&json!("Y")), false), None);
    assert_eq!(skill_frontmatter_flag(Some(&json!("Y")), true), Some(true));
    assert_eq!(skill_frontmatter_flag(Some(&json!(0)), false), Some(false));
}

#[test]
fn skill_names_sort_like_locale_compare() {
    let mut names = vec!["b", "a:b", "A", "a", "a-b", "a_b", "ab", "2spec", "Ab"];
    names.sort_by(|left, right| compare_skill_names(left, right));
    assert_eq!(
        names,
        ["2spec", "a", "A", "a_b", "a-b", "a:b", "ab", "Ab", "b"]
    );
}
