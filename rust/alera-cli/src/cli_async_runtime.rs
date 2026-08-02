use std::io;

use tokio::runtime::{Builder, Runtime};

use crate::cli::Command;

const MAX_HOST_WORKER_THREADS: usize = 4;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum RuntimeProfile {
    Cli,
    Host,
}

pub fn build(command: &Command) -> io::Result<Runtime> {
    match profile(command) {
        RuntimeProfile::Cli => Builder::new_current_thread().enable_all().build(),
        RuntimeProfile::Host => Builder::new_multi_thread()
            .worker_threads(host_worker_threads())
            .enable_all()
            .build(),
    }
}

fn profile(command: &Command) -> RuntimeProfile {
    match command {
        Command::RuntimeHost(_) | Command::TerminalHost(_) => RuntimeProfile::Host,
        _ => RuntimeProfile::Cli,
    }
}

fn host_worker_threads() -> usize {
    std::thread::available_parallelism()
        .map(usize::from)
        .unwrap_or(1)
        .min(MAX_HOST_WORKER_THREADS)
}

#[cfg(test)]
mod tests {
    use clap::Parser;

    use super::*;
    use crate::cli::Cli;

    fn command(args: &[&str]) -> Command {
        Cli::try_parse_from(args).unwrap().command
    }

    #[test]
    fn ordinary_cli_commands_use_one_async_worker() {
        let runtime = build(&command(&["alera", "version"])).unwrap();

        assert_eq!(runtime.metrics().num_workers(), 1);
    }

    #[test]
    fn runtime_host_workers_are_bounded_by_machine_parallelism() {
        let runtime = build(&command(&[
            "alera",
            "runtime-host",
            "--runtime-dir",
            "/runtime",
            "--control-file",
            "/runtime/host.json",
            "--token",
            "test-token",
        ]))
        .unwrap();

        assert_eq!(runtime.metrics().num_workers(), host_worker_threads());
        assert!(runtime.metrics().num_workers() <= MAX_HOST_WORKER_THREADS);
    }

    #[test]
    fn runtime_proxy_stays_on_the_lightweight_cli_runtime() {
        let runtime = build(&command(&["alera", "runtime-proxy"])).unwrap();

        assert_eq!(runtime.metrics().num_workers(), 1);
    }
}
