use alera_core::child_process::windowless_command;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::Stdio;
use std::thread;
use std::time::Duration;

fn main() {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    match args.first().map(String::as_str) {
        Some("control") => {
            let mut stdout = io::stdout().lock();
            stdout.write_all(&[0; 4096]).unwrap();
            stdout.write_all("😀tail\n".as_bytes()).unwrap();
            stdout.flush().unwrap();
        }
        Some("output") => {
            let stderr = thread::spawn(|| {
                let mut stderr = io::stderr().lock();
                stderr.write_all(&vec![b'e'; 256 * 1024]).unwrap();
                stderr.write_all(b"stderr tail\n").unwrap();
            });
            let mut stdout = io::stdout().lock();
            stdout.write_all(&vec![b'o'; 256 * 1024]).unwrap();
            stdout.write_all("stdout tail 😀\n".as_bytes()).unwrap();
            stderr.join().unwrap();
            std::process::exit(7);
        }
        Some("linger") => {
            println!("pid={}", std::process::id());
            io::stdout().flush().unwrap();
            thread::sleep(Duration::from_secs(60));
        }
        Some("tree") => {
            let executable = std::env::current_exe().unwrap();
            let mut descendant = windowless_command(executable);
            descendant
                .args(["heartbeat", &args[1]])
                .stdin(Stdio::null());
            let mut child = descendant.spawn().unwrap();
            println!("tree ready");
            io::stdout().flush().unwrap();
            let _ = child.wait();
        }
        Some("heartbeat") => {
            let path = PathBuf::from(&args[1]);
            loop {
                std::fs::write(&path, format!("{:?}", std::time::Instant::now())).unwrap();
                thread::sleep(Duration::from_millis(20));
            }
        }
        _ => std::process::exit(2),
    }
}
