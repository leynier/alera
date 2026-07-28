use std::path::Path;

use super::super::contract::{EmulatorFailure, EmulatorResult};
use super::super::process;
use super::AndroidAttached;

#[derive(Debug, Eq, PartialEq)]
pub(super) enum ExactDeviceState {
    Gone,
    Running,
    Unverified,
}

pub(super) fn command(serial: &str) -> Vec<String> {
    vec!["-s".into(), serial.into(), "emu".into(), "kill".into()]
}

pub(super) fn devices_command() -> Vec<String> {
    vec!["devices".into()]
}

pub(super) fn identity_command(serial: &str) -> Vec<String> {
    vec![
        "-s".into(),
        serial.into(),
        "emu".into(),
        "avd".into(),
        "name".into(),
    ]
}

pub(super) async fn owned_device(adb: &Path, attached: &mut AndroidAttached) -> EmulatorResult<()> {
    if !attached.owned {
        return Ok(());
    }
    match exact_device_state(adb, attached).await {
        Ok(ExactDeviceState::Gone) => {
            let _ = stop_owned_process(attached).await;
            return Ok(());
        }
        Ok(ExactDeviceState::Running) => {}
        Ok(ExactDeviceState::Unverified) => {
            return stop_owned_process(attached)
                .await
                .then_some(())
                .ok_or_else(|| unverified_failure(attached));
        }
        Err(error) => {
            return stop_owned_process(attached)
                .await
                .then_some(())
                .ok_or(error);
        }
    }
    let result =
        process::output(adb, &command(&attached.serial), "Android emulator shutdown").await;
    let forced = stop_owned_process(attached).await;
    if result.is_ok() || forced {
        return Ok(());
    }
    if exact_device_state(adb, attached)
        .await
        .is_ok_and(|state| state == ExactDeviceState::Gone)
    {
        return Ok(());
    }
    result.map(drop)
}

async fn exact_device_state(
    adb: &Path,
    attached: &AndroidAttached,
) -> EmulatorResult<ExactDeviceState> {
    let devices = process::output(adb, &devices_command(), "Android shutdown verification").await?;
    match classify_devices(&devices.stdout, &attached.serial) {
        ExactDeviceState::Running => {
            let identity = process::output(
                adb,
                &identity_command(&attached.serial),
                "Android shutdown identity verification",
            )
            .await?;
            Ok(classify_identity(&identity.stdout, &attached.device_name))
        }
        state => Ok(state),
    }
}

async fn stop_owned_process(attached: &mut AndroidAttached) -> bool {
    match attached.process.as_mut() {
        Some(process) => process.kill().await.is_ok(),
        None => false,
    }
}

fn unverified_failure(attached: &AndroidAttached) -> EmulatorFailure {
    EmulatorFailure::new(
        "provider_incompatible",
        format!(
            "Could not verify Android virtual device `{}` before shutdown.",
            attached.device_name
        ),
        ["Wait for the AVD state to settle, then retry."],
    )
}

pub(super) fn classify_devices(output: &[u8], serial: &str) -> ExactDeviceState {
    let output = String::from_utf8_lossy(output);
    if !output
        .lines()
        .any(|line| line.trim().starts_with("List of devices attached"))
    {
        return ExactDeviceState::Unverified;
    }
    for line in output.lines() {
        let mut fields = line.split_whitespace();
        if fields.next() != Some(serial) {
            continue;
        }
        return if fields.next() == Some("device") {
            ExactDeviceState::Running
        } else {
            ExactDeviceState::Unverified
        };
    }
    ExactDeviceState::Gone
}

pub(super) fn classify_identity(output: &[u8], expected_name: &str) -> ExactDeviceState {
    let output = String::from_utf8_lossy(output);
    let lines: Vec<&str> = output
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect();
    let Some(name) = lines.first().copied() else {
        return ExactDeviceState::Unverified;
    };
    if name == "OK" || name.starts_with("KO") || !lines.iter().skip(1).any(|line| *line == "OK") {
        return ExactDeviceState::Unverified;
    }
    if name == expected_name {
        ExactDeviceState::Running
    } else {
        ExactDeviceState::Gone
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn commands_target_only_the_exact_serial() {
        assert_eq!(
            command("emulator-5556"),
            ["-s", "emulator-5556", "emu", "kill"]
        );
        assert_eq!(
            identity_command("emulator-5556"),
            ["-s", "emulator-5556", "emu", "avd", "name"]
        );
    }

    #[test]
    fn absent_exact_serial_completes_even_when_another_emulator_exists() {
        let output = b"List of devices attached\nemulator-5558\tdevice\n";

        assert_eq!(
            classify_devices(output, "emulator-5556"),
            ExactDeviceState::Gone
        );
    }

    #[test]
    fn offline_or_malformed_device_lists_never_hide_the_failure() {
        assert_eq!(
            classify_devices(
                b"List of devices attached\nemulator-5556\toffline\n",
                "emulator-5556",
            ),
            ExactDeviceState::Unverified
        );
        assert_eq!(
            classify_devices(b"unexpected output", "emulator-5556"),
            ExactDeviceState::Unverified
        );
    }

    #[test]
    fn exact_identity_must_match_both_serial_and_avd_name() {
        assert_eq!(
            classify_identity(b"Pixel_9\nOK\n", "Pixel_9"),
            ExactDeviceState::Running
        );
        assert_eq!(
            classify_identity(b"Pixel_8\nOK\n", "Pixel_9"),
            ExactDeviceState::Gone
        );
        assert_eq!(
            classify_identity(b"KO: emulator not running\n", "Pixel_9"),
            ExactDeviceState::Unverified
        );
    }
}
