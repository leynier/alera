use super::{EmulatorFailure, EmulatorResult};

pub struct AndroidLogcatQuery<'a> {
    pub max_lines: u32,
    pub tags: &'a [String],
    pub level: Option<&'a str>,
    pub since_epoch: Option<&'a str>,
}

pub fn boot(avd_name: &str, port: u16) -> Vec<String> {
    vec![
        "-avd".into(),
        avd_name.into(),
        "-port".into(),
        port.to_string(),
        "-no-snapshot-save".into(),
        "-no-window".into(),
    ]
}

pub fn launch(
    serial: &str,
    bundle_id: &str,
    activity: Option<&str>,
) -> EmulatorResult<Vec<String>> {
    require_android_identifier(bundle_id, "Android application id")?;
    if let Some(activity) = activity {
        require_activity_identifier(activity)?;
        return Ok(vec![
            "-s".into(),
            serial.into(),
            "shell".into(),
            "am".into(),
            "start".into(),
            "-n".into(),
            format!("{bundle_id}/{activity}"),
        ]);
    }
    Ok(vec![
        "-s".into(),
        serial.into(),
        "shell".into(),
        "monkey".into(),
        "-p".into(),
        bundle_id.into(),
        "-c".into(),
        "android.intent.category.LAUNCHER".into(),
        "1".into(),
    ])
}

pub fn permission(
    serial: &str,
    operation: &str,
    bundle_id: &str,
    permission: &str,
) -> EmulatorResult<Vec<String>> {
    if !matches!(operation, "grant" | "revoke") {
        return Err(EmulatorFailure::invalid(
            "Permission operation must be grant or revoke.",
        ));
    }
    require_android_identifier(bundle_id, "Android application id")?;
    require_android_identifier(permission, "Android permission")?;
    Ok(vec![
        "-s".into(),
        serial.into(),
        "shell".into(),
        "pm".into(),
        operation.into(),
        bundle_id.into(),
        permission.into(),
    ])
}

pub fn logcat(serial: &str, query: &AndroidLogcatQuery<'_>) -> EmulatorResult<Vec<String>> {
    let priority = priority_letter(query.level)?;
    for tag in query.tags {
        require_log_tag(tag)?;
    }
    let mut args = vec![
        "-s".into(),
        serial.into(),
        "logcat".into(),
        "-d".into(),
        "-v".into(),
        "epoch".into(),
    ];
    if let Some(since) = query.since_epoch {
        args.extend(["-T".into(), since.into()]);
    } else if query.tags.is_empty() && query.level.is_none() {
        args.extend(["-t".into(), query.max_lines.clamp(1, 1000).to_string()]);
    }
    if query.tags.is_empty() {
        if let Some(priority) = priority {
            args.push(format!("*:{priority}"));
        }
    } else {
        let priority = priority.unwrap_or("V");
        args.extend(query.tags.iter().map(|tag| format!("{tag}:{priority}")));
        args.push("*:S".into());
    }
    Ok(args)
}

fn priority_letter(level: Option<&str>) -> EmulatorResult<Option<&'static str>> {
    level
        .map(|value| match value {
            "verbose" => Ok("V"),
            "debug" => Ok("D"),
            "info" => Ok("I"),
            "warn" => Ok("W"),
            "error" => Ok("E"),
            "fatal" => Ok("F"),
            _ => Err(EmulatorFailure::invalid("Unknown Android log level.")),
        })
        .transpose()
}

fn require_android_identifier(value: &str, label: &str) -> EmulatorResult<()> {
    if !value.is_empty()
        && value
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '.' | '_'))
    {
        return Ok(());
    }
    Err(EmulatorFailure::invalid(format!("{label} is invalid.")))
}

fn require_activity_identifier(value: &str) -> EmulatorResult<()> {
    if !value.is_empty()
        && value.chars().all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '.' | '_' | '$')
        })
    {
        return Ok(());
    }
    Err(EmulatorFailure::invalid(
        "Android activity name is invalid.",
    ))
}

fn require_log_tag(value: &str) -> EmulatorResult<()> {
    if !value.is_empty()
        && value.len() <= 128
        && value.chars().all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '.' | '_' | '-')
        })
    {
        return Ok(());
    }
    Err(EmulatorFailure::invalid("Android log tag is invalid."))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn owned_avds_start_headless_on_the_reserved_port() {
        assert_eq!(
            boot("Pixel_9", 5556),
            [
                "-avd",
                "Pixel_9",
                "-port",
                "5556",
                "-no-snapshot-save",
                "-no-window",
            ],
        );
    }

    #[test]
    fn explicit_activity_uses_am_start_without_shell_metacharacters() {
        assert_eq!(
            launch("emulator-5554", "dev.alera.app", Some(".MainActivity")).unwrap(),
            [
                "-s",
                "emulator-5554",
                "shell",
                "am",
                "start",
                "-n",
                "dev.alera.app/.MainActivity",
            ],
        );
        assert!(launch("emulator-5554", "dev.alera;rm", None).is_err());
    }

    #[test]
    fn filtered_logcat_scans_the_ring_and_applies_native_filters() {
        let tags = vec!["Alera".to_string()];
        let args = logcat(
            "emulator-5554",
            &AndroidLogcatQuery {
                max_lines: 20,
                tags: &tags,
                level: Some("warn"),
                since_epoch: Some("1785153600.000"),
            },
        )
        .unwrap();
        assert!(args.windows(2).any(|pair| pair == ["-T", "1785153600.000"]));
        assert!(args.contains(&"Alera:W".to_string()));
        assert!(args.contains(&"*:S".to_string()));
        assert!(!args.contains(&"-t".to_string()));
    }

    #[test]
    fn unfiltered_logcat_uses_an_exact_bounded_tail() {
        let args = logcat(
            "emulator-5554",
            &AndroidLogcatQuery {
                max_lines: 20,
                tags: &[],
                level: None,
                since_epoch: None,
            },
        )
        .unwrap();
        assert!(args.windows(2).any(|pair| pair == ["-t", "20"]));
    }
}
