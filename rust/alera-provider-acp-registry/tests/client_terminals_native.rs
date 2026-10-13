use alera_provider_acp_registry::{
    ClientTerminalCommand, ClientTerminalSpawner, NativeClientTerminalSpawner,
    SpawnedClientTerminal,
};
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::time::Duration;
use tokio::io::AsyncReadExt;

fn command(mode: &str, additional: &[&str]) -> ClientTerminalCommand {
    ClientTerminalCommand {
        command: env!("CARGO_BIN_EXE_acp-terminal-fixture").into(),
        args: std::iter::once(mode.to_owned())
            .chain(additional.iter().map(|value| (*value).into()))
            .collect(),
        cwd: std::env::current_dir().unwrap(),
        env: BTreeMap::new(),
        shell: false,
    }
}

#[tokio::test]
async fn native_process_drains_both_pipes_and_reaps_exit() {
    let SpawnedClientTerminal {
        mut child,
        mut stdout,
        mut stderr,
    } = NativeClientTerminalSpawner
        .spawn(command("output", &[]))
        .await
        .unwrap();
    let stdout_task = tokio::spawn(async move {
        let mut bytes = Vec::new();
        stdout.read_to_end(&mut bytes).await.unwrap();
        bytes
    });
    let stderr_task = tokio::spawn(async move {
        let mut bytes = Vec::new();
        stderr.read_to_end(&mut bytes).await.unwrap();
        bytes
    });
    let status = tokio::time::timeout(Duration::from_secs(5), child.wait())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(status.exit_code, Some(7));
    assert_eq!(status.signal, None);
    assert!(String::from_utf8(stdout_task.await.unwrap())
        .unwrap()
        .ends_with("stdout tail 😀\n"));
    assert!(String::from_utf8(stderr_task.await.unwrap())
        .unwrap()
        .ends_with("stderr tail\n"));
}

#[tokio::test]
async fn native_kill_reaps_and_reports_platform_exit_status() {
    let mut terminal = NativeClientTerminalSpawner
        .spawn(command("linger", &[]))
        .await
        .unwrap();
    terminal.child.terminate();
    let status = tokio::time::timeout(Duration::from_secs(5), terminal.child.wait())
        .await
        .unwrap()
        .unwrap();
    #[cfg(unix)]
    assert_eq!(status.signal.as_deref(), Some("SIGKILL"));
    #[cfg(windows)]
    assert!(status.exit_code.is_some());
}

struct TemporaryPath(PathBuf);

impl Drop for TemporaryPath {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

#[tokio::test]
async fn native_drop_terminates_descendant_tree() {
    let path = TemporaryPath(std::env::temp_dir().join(format!(
            "alera-terminal-tree-{}-{}.txt",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        )));
    let terminal = NativeClientTerminalSpawner
        .spawn(command("tree", &[path.0.to_str().unwrap()]))
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(5), async {
        while !path.0.exists() {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .unwrap();
    drop(terminal);
    tokio::time::sleep(Duration::from_millis(100)).await;
    let stopped = std::fs::read(&path.0).unwrap();
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(
        std::fs::read(&path.0).unwrap(),
        stopped,
        "descendant must stop writing after its owner drops"
    );
}
