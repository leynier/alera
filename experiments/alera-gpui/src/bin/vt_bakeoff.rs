use std::ffi::c_void;
use std::hint::black_box;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};

use alacritty_terminal::event::{Event, EventListener};
use alacritty_terminal::term::test::TermSize;
use alacritty_terminal::term::{Config, Term};
use alacritty_terminal::vte::ansi;
use anyhow::{bail, Context as _, Result};
use libloading::Library;

const CORPUS_BYTES: usize = 2_560_000;
const ITERATIONS: usize = 30;
const COLUMNS: usize = 120;
const ROWS: usize = 40;

#[derive(Clone)]
struct NoopListener;

impl EventListener for NoopListener {
    fn send_event(&self, _: Event) {}
}

type GhosttyTerminal = *mut c_void;
type GhosttyNew = unsafe extern "C" fn(*const c_void, *mut GhosttyTerminal, u16, u16) -> i32;
type GhosttyFree = unsafe extern "C" fn(GhosttyTerminal);
type GhosttyWrite = unsafe extern "C" fn(GhosttyTerminal, *const u8, usize);

struct GhosttyApi {
    _library: Library,
    new: GhosttyNew,
    free: GhosttyFree,
    write: GhosttyWrite,
}

impl GhosttyApi {
    fn load(path: &Path) -> Result<Self> {
        // The library stays owned by this value, so copied function pointers cannot outlive it.
        let library = unsafe { Library::new(path) }
            .with_context(|| format!("failed to load {}", path.display()))?;
        let new = unsafe {
            *library
                .get::<GhosttyNew>(b"ghostty_terminal_new\0")
                .context("missing ghostty_terminal_new")?
        };
        let free = unsafe {
            *library
                .get::<GhosttyFree>(b"ghostty_terminal_free\0")
                .context("missing ghostty_terminal_free")?
        };
        let write = unsafe {
            *library
                .get::<GhosttyWrite>(b"ghostty_terminal_vt_write\0")
                .context("missing ghostty_terminal_vt_write")?
        };
        Ok(Self {
            _library: library,
            new,
            free,
            write,
        })
    }

    fn parse_once(&self, bytes: &[u8]) -> Result<()> {
        let mut terminal = std::ptr::null_mut();
        // These calls use the stable C API with a live library and a byte slice valid for the call.
        let result =
            unsafe { (self.new)(std::ptr::null(), &mut terminal, COLUMNS as u16, ROWS as u16) };
        if result != 0 || terminal.is_null() {
            bail!("ghostty_terminal_new failed with result {result}");
        }
        unsafe {
            (self.write)(terminal, bytes.as_ptr(), bytes.len());
            (self.free)(terminal);
        }
        Ok(())
    }
}

fn main() -> Result<()> {
    let corpus = make_corpus();
    let ghostty_path = ghostty_library_path();
    let ghostty = Arc::new(GhosttyApi::load(&ghostty_path)?);

    alacritty_parse(&corpus);
    ghostty.parse_once(&corpus)?;

    let alacritty = measure(|| {
        alacritty_parse(black_box(&corpus));
        Ok(())
    })?;
    let ghostty_result = measure(|| ghostty.parse_once(black_box(&corpus)))?;

    println!("corpus_bytes={CORPUS_BYTES}");
    print_result("alacritty_terminal", &alacritty);
    print_result("libghostty_vt", &ghostty_result);
    Ok(())
}

fn alacritty_parse(bytes: &[u8]) {
    let mut terminal = Term::new(
        Config::default(),
        &TermSize::new(COLUMNS, ROWS),
        NoopListener,
    );
    let mut parser: ansi::Processor<ansi::StdSyncHandler> = ansi::Processor::new();
    parser.advance(&mut terminal, bytes);
    black_box(terminal.renderable_content());
}

fn measure(mut operation: impl FnMut() -> Result<()>) -> Result<Vec<Duration>> {
    let mut durations = Vec::with_capacity(ITERATIONS);
    for _ in 0..ITERATIONS {
        let started = Instant::now();
        operation()?;
        durations.push(started.elapsed());
    }
    durations.sort_unstable();
    Ok(durations)
}

fn print_result(name: &str, durations: &[Duration]) {
    let median = durations[durations.len() / 2];
    let p95 = durations[(durations.len() * 95 / 100).min(durations.len() - 1)];
    let throughput = CORPUS_BYTES as f64 / median.as_secs_f64() / 1_000_000.0;
    println!(
        "{name}: median_ms={:.3} p95_ms={:.3} median_mb_s={throughput:.2}",
        median.as_secs_f64() * 1_000.0,
        p95.as_secs_f64() * 1_000.0,
    );
}

fn make_corpus() -> Vec<u8> {
    const FRAME: &[u8] = b"\x1b[2J\x1b[H\x1b[38;2;121;167;255mAlera\x1b[0m runtime\n\
        \x1b[1;32mPASS\x1b[0m cargo test --workspace\n\
        \x1b[33mwarning:\x1b[0m deterministic terminal corpus\n\
        progress [##########] 100%\rprogress [###########] 100%\n\
        \x1b]0;Alera GPUI VT Bakeoff\x07\x1b[?25l\x1b[?25h";
    let mut corpus = Vec::with_capacity(CORPUS_BYTES);
    while corpus.len() < CORPUS_BYTES {
        let remaining = CORPUS_BYTES - corpus.len();
        corpus.extend_from_slice(&FRAME[..remaining.min(FRAME.len())]);
    }
    corpus
}

fn ghostty_library_path() -> PathBuf {
    std::env::var_os("ALERA_GHOSTTY_VT_LIBRARY")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../third_party/dart_terminal/.prebuilt/linux-x64/libghostty-vt.so")
        })
}
