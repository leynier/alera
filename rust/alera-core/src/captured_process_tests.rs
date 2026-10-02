use super::*;

use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};

#[cfg(unix)]
fn command(script: &str) -> Command {
    crate::shell_command::shell_command(
        "sh",
        &["-c".to_string(), script.to_string()],
        None,
        None,
        true,
    )
}

#[cfg(unix)]
async fn run(script: &str, max_output_bytes: usize) -> Result<CapturedProcessOutput, String> {
    run_command(command(script), "sh", None, max_output_bytes, None).await
}

#[cfg(windows)]
fn windows_command(arguments: &[&str]) -> Command {
    let mut command = crate::child_process::windowless_async_command("cmd.exe");
    command.args(arguments);
    command
}

#[cfg(windows)]
#[tokio::test]
async fn captures_cmd_output_after_job_assignment_and_resume() {
    let result = run_command(
        windows_command(&["/D", "/C", "echo sentinel"]),
        "cmd.exe",
        None,
        4096,
        None,
    )
    .await
    .expect("cmd should complete after the suspended job is resumed");

    assert_eq!(result.exit_code, 0);
    assert!(result.stdout.to_ascii_lowercase().contains("sentinel"));
}

#[cfg(windows)]
#[tokio::test]
async fn output_overflow_and_timeout_return_after_job_cleanup() {
    let overflow = match run_command(
        windows_command(&["/D", "/C", "for /L %i in (1,1,100000) do @echo x"]),
        "cmd.exe",
        None,
        4096,
        None,
    )
    .await
    {
        Ok(_) => panic!("an unbounded cmd writer must hit the output limit"),
        Err(error) => error,
    };
    assert!(
        overflow.contains("combined process output limit"),
        "{overflow}"
    );

    let started = std::time::Instant::now();
    let timeout = match run_command(
        windows_command(&["/D", "/C", "ping 127.0.0.1 -n 6 >NUL"]),
        "cmd.exe",
        None,
        4096,
        Some(Duration::from_millis(50)),
    )
    .await
    {
        Ok(_) => panic!("a waiting cmd child must be terminated by the timeout"),
        Err(error) => error,
    };
    assert!(timeout.contains("timed out"), "{timeout}");
    assert!(started.elapsed() < Duration::from_secs(5));

    let follow_up = run_command(
        windows_command(&["/D", "/C", "echo after"]),
        "cmd.exe",
        None,
        4096,
        None,
    )
    .await
    .expect("the process jobs must be cleaned before returning");
    assert_eq!(follow_up.exit_code, 0);
    assert!(follow_up.stdout.to_ascii_lowercase().contains("after"));
}

#[cfg(unix)]
#[tokio::test]
async fn rejects_stdout_that_exceeds_the_combined_budget() {
    let error = run("head -c 65537 /dev/zero", 65536)
        .await
        .err()
        .expect("output must be bounded");

    assert!(error.contains("combined process output limit"), "{error}");
}

#[cfg(unix)]
#[tokio::test]
async fn rejects_stderr_that_exceeds_the_combined_budget() {
    let error = run("head -c 65537 /dev/zero >&2", 65536)
        .await
        .err()
        .expect("output must be bounded");

    assert!(error.contains("combined process output limit"), "{error}");
}

#[cfg(unix)]
#[tokio::test]
async fn enforces_one_budget_across_both_streams() {
    let error = run(
        "head -c 40000 /dev/zero; head -c 40000 /dev/zero >&2",
        65536,
    )
    .await
    .err()
    .expect("combined output must be bounded");

    assert!(error.contains("combined process output limit"), "{error}");
}

#[cfg(unix)]
#[tokio::test]
async fn kills_an_infinite_writer_after_output_overflow() {
    let error = run("yes x", 4096)
        .await
        .err()
        .expect("infinite output must be killed");

    assert!(error.contains("combined process output limit"), "{error}");
}

#[cfg(unix)]
#[tokio::test]
async fn preserves_nonzero_status_and_lossy_utf8_under_the_limit() {
    let result = run("printf '\\377\\376ok'; printf 'bad' >&2; exit 3", 1024)
        .await
        .expect("small output should succeed");

    assert_eq!(result.exit_code, 3);
    assert_eq!(result.stdout, "��ok");
    assert_eq!(result.stderr, "bad");
}

#[cfg(unix)]
#[tokio::test]
async fn a_larger_explicit_budget_preserves_a_legitimate_response() {
    let result = run("head -c 65536 /dev/zero", 65537)
        .await
        .expect("override should allow output");

    assert_eq!(result.stdout.len(), 65536);
}

#[cfg(unix)]
#[tokio::test]
async fn drains_a_multi_megabyte_tail_after_the_child_exits() {
    let result = run("head -c 4194304 /dev/zero", 4194305)
        .await
        .expect("the larger response should drain before the grace period");

    assert_eq!(result.stdout.len(), 4194304);
}

#[cfg(unix)]
#[tokio::test]
async fn times_out_and_reaps_a_process_with_open_pipes() {
    let error = run_command(
        command("sleep 10"),
        "sh",
        None,
        1024,
        Some(Duration::from_millis(25)),
    )
    .await
    .err()
    .expect("timeout must fail the run");

    assert!(error.contains("timed out"), "{error}");
}

#[cfg(unix)]
#[tokio::test]
async fn cancelling_capture_kills_the_process_tree() {
    let directory = tempfile::tempdir().expect("tempdir");
    let marker = directory.path().join("capture-cancelled-marker");
    let pid_marker = directory.path().join("capture-cancelled-pid");
    let marker_path = marker.to_string_lossy();
    let pid_marker_path = pid_marker.to_string_lossy();
    let script = format!(
        "printf $$ > '{pid_marker_path}'; printf started > '{marker_path}'; sleep 10; printf leaked > '{marker_path}'"
    );
    let task = tokio::spawn(run_command(command(&script), "sh", None, 1024, None));

    for _ in 0..100 {
        if marker.exists() && pid_marker.exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    assert_eq!(
        std::fs::read_to_string(&marker).expect("the process should start"),
        "started"
    );
    let pid = std::fs::read_to_string(&pid_marker)
        .expect("the child pid should be recorded")
        .trim()
        .parse::<libc::pid_t>()
        .expect("the child pid should be numeric");
    task.abort();
    let _ = task.await;

    let mut process_gone = false;
    for _ in 0..200 {
        if unsafe { libc::kill(pid, 0) } == -1 {
            process_gone = true;
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    assert!(process_gone, "the cancelled child remained alive");

    assert_eq!(
        std::fs::read_to_string(&marker).expect("the marker should remain"),
        "started"
    );
}

#[tokio::test]
async fn cancelling_a_reader_join_aborts_its_owned_task() {
    struct DropMarker(Arc<AtomicBool>);

    impl Drop for DropMarker {
        fn drop(&mut self) {
            self.0.store(true, Ordering::Release);
        }
    }

    let dropped = Arc::new(AtomicBool::new(false));
    let started = Arc::new(AtomicBool::new(false));
    let marker = Arc::clone(&dropped);
    let started_marker = Arc::clone(&started);
    let task = tokio::spawn(async move {
        let _marker = DropMarker(marker);
        started_marker.store(true, Ordering::Release);
        std::future::pending::<()>().await;
    });
    let joiner = tokio::spawn(async move {
        let mut owned = process_tasks::AbortOnDrop::new(task);
        let _ = owned.join().await;
    });

    for _ in 0..100 {
        if started.load(Ordering::Acquire) {
            break;
        }
        tokio::task::yield_now().await;
    }
    assert!(started.load(Ordering::Acquire), "reader task did not start");
    joiner.abort();
    let _ = joiner.await;
    for _ in 0..100 {
        if dropped.load(Ordering::Acquire) {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    assert!(
        dropped.load(Ordering::Acquire),
        "cancelling the join detached the reader task"
    );
}

#[tokio::test]
async fn reports_a_pipe_read_error() {
    let error = read_pipe(FailingReader, Arc::new(OutputBudget::new(1024)), "stdout")
        .await
        .expect_err("reader error must be visible");

    assert!(error.to_string().contains("failed reading stdout"));
}

struct FailingReader;

impl AsyncRead for FailingReader {
    fn poll_read(
        self: Pin<&mut Self>,
        _context: &mut std::task::Context<'_>,
        _buffer: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::task::Poll::Ready(Err(std::io::Error::other("test pipe failure")))
    }
}
