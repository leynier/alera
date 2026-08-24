use std::collections::BTreeMap;

use alera_core::child_process::windowless_command;
use serde_json::Value;

pub fn list_system_font_families() -> Vec<String> {
    let discovered = if cfg!(target_os = "macos") {
        list_macos_fonts()
    } else if cfg!(target_os = "windows") {
        list_windows_fonts()
    } else {
        list_linux_fonts()
    };
    merge_font_families(discovered, fallback_font_families())
}

fn list_macos_fonts() -> Vec<String> {
    let output = match windowless_command("system_profiler")
        .args(["SPFontsDataType", "-json"])
        .output()
    {
        Ok(output) if output.status.success() => output.stdout,
        _ => return Vec::new(),
    };
    let Ok(value) = serde_json::from_slice::<Value>(&output) else {
        return Vec::new();
    };
    value
        .get("SPFontsDataType")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .flat_map(|font| {
            font.get("typefaces")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
        })
        .filter_map(|typeface| typeface.get("family").and_then(Value::as_str))
        .map(str::to_string)
        .collect()
}

fn list_linux_fonts() -> Vec<String> {
    let output = match windowless_command("fc-list").args([":", "family"]).output() {
        Ok(output) if output.status.success() => output.stdout,
        _ => return Vec::new(),
    };
    String::from_utf8_lossy(&output)
        .lines()
        .flat_map(|line| line.split(','))
        .map(str::to_string)
        .collect()
}

fn list_windows_fonts() -> Vec<String> {
    const SCRIPT: &str = "Add-Type -AssemblyName System.Drawing; $fonts = New-Object System.Drawing.Text.InstalledFontCollection; $fonts.Families | ForEach-Object { $_.Name }";
    let output = match windowless_command("powershell.exe")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            SCRIPT,
        ])
        .output()
    {
        Ok(output) if output.status.success() => output.stdout,
        _ => return Vec::new(),
    };
    String::from_utf8_lossy(&output)
        .lines()
        .map(str::to_string)
        .collect()
}

fn fallback_font_families() -> &'static [&'static str] {
    if cfg!(target_os = "macos") {
        &[
            "SF Mono",
            "Menlo",
            "Monaco",
            "JetBrains Mono",
            "Fira Code",
            "monospace",
        ]
    } else if cfg!(target_os = "windows") {
        &[
            "Cascadia Mono",
            "Consolas",
            "Lucida Console",
            "JetBrains Mono",
            "Fira Code",
            "monospace",
        ]
    } else {
        &[
            "JetBrains Mono",
            "Fira Code",
            "DejaVu Sans Mono",
            "Liberation Mono",
            "Ubuntu Mono",
            "Noto Sans Mono",
            "monospace",
        ]
    }
}

fn merge_font_families(
    discovered: impl IntoIterator<Item = String>,
    fallback: &[&str],
) -> Vec<String> {
    let mut by_name = BTreeMap::<String, String>::new();
    for name in discovered
        .into_iter()
        .chain(fallback.iter().map(|name| (*name).to_string()))
    {
        let trimmed = name.trim();
        if trimmed.is_empty() || trimmed.starts_with('.') {
            continue;
        }
        by_name
            .entry(trimmed.to_lowercase())
            .or_insert_with(|| trimmed.to_string());
    }
    by_name.into_values().collect()
}

#[cfg(test)]
mod tests {
    use super::merge_font_families;

    #[test]
    fn font_families_are_trimmed_deduplicated_and_sorted() {
        let merged = merge_font_families(
            [
                " Zed Mono ".to_string(),
                "zed mono".to_string(),
                ".Hidden".to_string(),
            ],
            &["Fira Code"],
        );
        assert_eq!(merged, ["Fira Code", "Zed Mono"]);
    }
}
