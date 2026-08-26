pub(super) fn ai_assist_failure_detail(stdout: &str, stderr: &str) -> Option<String> {
    let combined = format!("{stdout}\n{stderr}");
    let lines: Vec<&str> = combined
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect();
    for line in lines.iter().rev() {
        let Some(encoded) = line
            .strip_prefix("\"message\"")
            .and_then(|value| value.trim_start().strip_prefix(':'))
        else {
            continue;
        };
        let encoded = encoded.trim().trim_end_matches(',');
        if let Ok(message) = serde_json::from_str::<String>(encoded) {
            if !message.trim().is_empty() {
                return Some(cap_failure_detail(&message));
            }
        }
    }
    lines
        .iter()
        .copied()
        .rev()
        .find(|line| !matches!(*line, "{" | "}" | "[" | "]" | "}," | "]," | ","))
        .map(cap_failure_detail)
}

fn cap_failure_detail(detail: &str) -> String {
    const MAX_CHARS: usize = 1000;
    let trimmed = detail.trim();
    if trimmed.chars().count() <= MAX_CHARS {
        return trimmed.to_string();
    }
    format!(
        "{}...",
        trimmed
            .chars()
            .take(MAX_CHARS)
            .collect::<String>()
            .trim_end()
    )
}
