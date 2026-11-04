use std::io::Write;
use std::thread;
use std::time::Duration;

fn main() {
    println!("stdout-ready");
    eprintln!("stderr-ready");
    std::io::stdout().flush().unwrap();
    std::io::stderr().flush().unwrap();
    loop {
        thread::sleep(Duration::from_secs(60));
    }
}
