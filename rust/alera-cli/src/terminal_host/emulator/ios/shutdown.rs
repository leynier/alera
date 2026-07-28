use super::ListedDevice;

pub(super) fn command(udid: &str) -> Vec<String> {
    vec!["simctl".into(), "shutdown".into(), udid.into()]
}

pub(super) fn failure_is_complete(devices: &[ListedDevice], expected_udid: &str) -> bool {
    devices
        .iter()
        .find(|device| device.udid == expected_udid)
        .is_none_or(|device| device.state == "Shutdown")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn device(udid: &str, state: &str) -> ListedDevice {
        ListedDevice {
            name: "iPhone".into(),
            udid: udid.into(),
            state: state.into(),
            runtime: "iOS".into(),
            available: true,
        }
    }

    #[test]
    fn shutdown_command_targets_only_the_exact_udid() {
        assert_eq!(command("AAAA-BBBB"), ["simctl", "shutdown", "AAAA-BBBB"]);
    }

    #[test]
    fn absent_or_shutdown_exact_udid_completes_failed_shutdown() {
        assert!(failure_is_complete(
            &[device("OTHER", "Booted")],
            "AAAA-BBBB"
        ));
        assert!(failure_is_complete(
            &[device("AAAA-BBBB", "Shutdown")],
            "AAAA-BBBB"
        ));
    }

    #[test]
    fn booted_or_transitioning_exact_udid_preserves_the_failure() {
        assert!(!failure_is_complete(
            &[device("AAAA-BBBB", "Booted")],
            "AAAA-BBBB"
        ));
        assert!(!failure_is_complete(
            &[device("AAAA-BBBB", "Shutting Down")],
            "AAAA-BBBB"
        ));
    }
}
