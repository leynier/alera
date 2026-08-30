use std::sync::atomic::{AtomicBool, Ordering};

use super::*;
use crate::terminal_host::resources::seal_shell_process;

static STOP_REQUESTED: AtomicBool = AtomicBool::new(false);

extern "C" fn request_stop(_: libc::c_int) {
    STOP_REQUESTED.store(true, Ordering::Relaxed);
}

#[test]
#[allow(clippy::disallowed_methods, clippy::zombie_processes)]
fn shutdown_child() {
    let Ok(mode) = std::env::var("ALERA_WORKSPACE_SHUTDOWN_TEST_MODE") else {
        return;
    };
    let root =
        std::path::PathBuf::from(std::env::var("ALERA_WORKSPACE_SHUTDOWN_TEST_ROOT").unwrap());
    unsafe {
        libc::signal(libc::SIGHUP, libc::SIG_IGN);
        libc::signal(
            libc::SIGTERM,
            request_stop as *const () as libc::sighandler_t,
        );
    }
    std::fs::write(root.join("ready"), std::process::id().to_string()).unwrap();
    while mode == "ignore" || !STOP_REQUESTED.load(Ordering::Relaxed) {
        std::thread::sleep(Duration::from_millis(10));
    }
    if mode == "fork" {
        // Deliberately orphan a helper after the shutdown snapshot. Its root
        // shell stays unreaped in the parent test until the guard completes.
        let _child = std::process::Command::new("sh")
            .args(["-c", "trap '' HUP TERM; sleep 1; : > \"$1\"", "helper"])
            .arg(root.join("cleanup"))
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .unwrap();
        return;
    }
    std::thread::sleep(Duration::from_millis(200));
    std::fs::write(root.join("cleanup"), b"finished").unwrap();
}

#[tokio::test]
async fn recycled_identity_is_never_followed_or_signalled() {
    let mut identity = seal_shell_process(std::process::id()).unwrap();
    identity.start_time += 1;
    let processes = capture_tree(&process_table(), vec![identity]);
    assert!(processes.is_empty());
    ShutdownGuard {
        processes,
        ..Default::default()
    }
    .wait()
    .await
    .unwrap();
    let mut guard = ShutdownGuard {
        anchors: vec![identity],
        ..Default::default()
    };
    assert!(
        guard.wait().await.is_err(),
        "a lost anchor must fail closed"
    );
}

#[allow(clippy::disallowed_methods)]
async fn exercise_shutdown(mode: &str) -> (bool, Duration) {
    use std::os::unix::process::CommandExt;
    let root = tempfile::tempdir().unwrap();
    let mut command = std::process::Command::new("sh");
    unsafe {
        command.pre_exec(|| {
            if libc::setsid() < 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let mut shell = command.args(["-c", "\"$1\" --exact terminal_host::session::workspace_shutdown::platform::tests::shutdown_child --nocapture & wait", "shutdown-test"])
        .arg(std::env::current_exe().unwrap())
        .env("ALERA_WORKSPACE_SHUTDOWN_TEST_MODE", mode)
        .env("ALERA_WORKSPACE_SHUTDOWN_TEST_ROOT", root.path())
        .spawn().unwrap();
    let identity = seal_shell_process(shell.id()).unwrap();
    tokio::time::timeout(Duration::from_secs(5), async {
        while !root.path().join("ready").exists() {
            tokio::time::sleep(POLL_INTERVAL).await;
        }
    })
    .await
    .unwrap();
    let mut guard = ShutdownGuard {
        processes: capture_tree(&process_table(), vec![identity]),
        anchors: vec![identity],
        ..Default::default()
    };
    assert!(guard.processes.len() >= 2);
    let identities = guard.processes.clone();
    super::super::super::shell_tree_termination::kill_shell_tree(Some(identity), || {
        let _ = shell.kill();
    })
    .await;
    let start = tokio::time::Instant::now();
    let result = guard.wait().await;
    let elapsed = start.elapsed();
    // Never leave a fixture running even if an assertion fails.
    for identity in &identities {
        if let Some(process) = process_table().process(Pid::from_u32(identity.pid)) {
            if process.start_time() == identity.start_time {
                process.kill_with(Signal::Kill);
            }
        }
    }
    let _ = shell.wait();
    result.unwrap();
    assert!(capture_tree(&process_table(), identities).is_empty());
    (root.path().join("cleanup").exists(), elapsed)
}

#[tokio::test]
async fn waits_for_graceful_cleanup_after_shell_exit() {
    let (cleaned, _) = exercise_shutdown("slow").await;
    assert!(
        cleaned,
        "returned before the descendant finished its shutdown handler"
    );
}

#[tokio::test]
async fn escalates_when_a_descendant_ignores_term() {
    let (cleaned, elapsed) = exercise_shutdown("ignore").await;
    assert!(!cleaned);
    assert!(elapsed >= GRACE_PERIOD);
    assert!(elapsed < GRACE_PERIOD + KILL_PERIOD + SWEEP_DEADLINE);
}

#[tokio::test]
async fn waits_for_a_helper_forked_during_shutdown_and_reparented() {
    let (cleaned, _) = exercise_shutdown("fork").await;
    assert!(
        cleaned,
        "returned while the orphaned shutdown helper was still running"
    );
}
