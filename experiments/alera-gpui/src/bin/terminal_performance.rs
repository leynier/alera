#[allow(dead_code)]
#[path = "../terminal.rs"]
mod terminal;
#[path = "../terminal_palette.rs"]
mod terminal_palette;

use std::sync::Arc;
use std::time::{Duration, Instant};

use gpui::{
    div, prelude::*, px, rgb, size, App, Application, Bounds, Context, Render, Task, Timer, Window,
    WindowBounds, WindowOptions,
};
use terminal::{KeyModifiers, TerminalEmulator};

const DURATION: Duration = Duration::from_secs(8);
const FRAME_INTERVAL: Duration = Duration::from_millis(33);
const SNAPSHOT_BYTES: usize = 2_560_000;
const RESTORE_RUNS: usize = 6;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Mode {
    Stream,
    Idle,
    Restore,
}

impl Mode {
    fn from_environment() -> Self {
        match std::env::var("ALERA_GPUI_BENCH_MODE").as_deref() {
            Ok("idle") => Self::Idle,
            Ok("restore") => Self::Restore,
            _ => Self::Stream,
        }
    }
}

struct TerminalBenchmark {
    mode: Mode,
    emulator: TerminalEmulator,
    line: String,
    snapshot: Arc<Vec<u8>>,
    started_at: Instant,
    cpu_before: f64,
    render_count: usize,
    write_count: usize,
    restore_phase: usize,
    restore_samples: Vec<Duration>,
    _task: Option<Task<()>>,
}

impl TerminalBenchmark {
    fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let benchmark = Self {
            mode: Mode::from_environment(),
            emulator: TerminalEmulator::new(100, 30),
            line: benchmark_line(),
            snapshot: Arc::new(build_snapshot()),
            started_at: Instant::now(),
            cpu_before: process_cpu_seconds(),
            render_count: 0,
            write_count: 0,
            restore_phase: 0,
            restore_samples: Vec::new(),
            _task: None,
        };
        cx.on_next_frame(window, |this, window, cx| match this.mode {
            Mode::Stream => this.start_stream(cx),
            Mode::Idle => this.start_idle(cx),
            Mode::Restore => this.start_restore(window, cx),
        });
        benchmark
    }

    fn start_stream(&mut self, cx: &mut Context<Self>) {
        self.started_at = Instant::now();
        self.cpu_before = process_cpu_seconds();
        self._task = Some(cx.spawn(async move |this, cx| loop {
            Timer::after(FRAME_INTERVAL).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let finished = this
                .update(cx, |this, cx| {
                    for _ in 0..4 {
                        this.emulator
                            .write(format!("{} {}\r\n", this.write_count, this.line).as_bytes());
                        this.write_count += 1;
                    }
                    let finished = this.started_at.elapsed() >= DURATION;
                    if finished {
                        this.print_stream_report();
                        cx.quit();
                    } else {
                        cx.notify();
                    }
                    finished
                })
                .unwrap_or(true);
            if finished {
                return;
            }
        }));
    }

    fn start_idle(&mut self, cx: &mut Context<Self>) {
        self.started_at = Instant::now();
        self.cpu_before = process_cpu_seconds();
        self._task = Some(cx.spawn(async move |this, cx| {
            Timer::after(DURATION).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                this.print_idle_report();
                cx.quit();
            });
        }));
    }

    fn start_restore(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.restore_phase == RESTORE_RUNS {
            self.print_restore_report();
            cx.quit();
            return;
        }
        self.emulator = TerminalEmulator::new(100, 30);
        let started = Instant::now();
        self.emulator.write(&self.snapshot);
        assert!(
            self.emulator.visible_text().contains("RESTORE-END"),
            "restore marker was lost before rendering"
        );
        cx.notify();
        cx.on_next_frame(window, move |this, window, cx| {
            this.restore_samples.push(started.elapsed());
            this.restore_phase += 1;
            this.start_restore(window, cx);
        });
    }

    fn print_stream_report(&self) {
        let elapsed = self.started_at.elapsed().as_secs_f64();
        let cpu = process_cpu_seconds() - self.cpu_before;
        println!("\n=== GPUI terminal stream ===");
        println!(
            "  {:.1} writes/s, {:.1} rendered frames/s over {:.2} s",
            self.write_count as f64 / elapsed,
            self.render_count.saturating_sub(1) as f64 / elapsed,
            elapsed
        );
        println!("  cpu {:.1}% of a core", cpu * 100.0 / elapsed);
        println!("  key encode p95 {:.3} µs", input_latency_p95_micros());
    }

    fn print_idle_report(&self) {
        let elapsed = self.started_at.elapsed().as_secs_f64();
        let cpu = process_cpu_seconds() - self.cpu_before;
        println!("\n=== GPUI terminal idle ===");
        println!(
            "  {} total rendered frames over {:.2} s",
            self.render_count, elapsed
        );
        println!("  cpu {:.2}% of a core", cpu * 100.0 / elapsed);
    }

    fn print_restore_report(&self) {
        let mut samples = self
            .restore_samples
            .iter()
            .skip(1)
            .map(Duration::as_secs_f64)
            .map(|seconds| seconds * 1000.0)
            .collect::<Vec<_>>();
        samples.sort_by(f64::total_cmp);
        let median = samples[samples.len() / 2];
        let p95 =
            samples[((samples.len() as f64 * 0.95).ceil() as usize - 1).min(samples.len() - 1)];
        println!("\n=== GPUI terminal restore ===");
        println!(
            "  {} bytes, {} measured runs, median {:.2} ms, p95 {:.2} ms",
            self.snapshot.len(),
            samples.len(),
            median,
            p95
        );
        println!("  samples {:?}", samples);
        println!("  key encode p95 {:.3} µs", input_latency_p95_micros());
    }
}

impl Render for TerminalBenchmark {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        self.render_count += 1;
        let lines = self
            .emulator
            .visible_lines()
            .into_iter()
            .map(|line| div().h(px(19.0)).line_height(px(19.0)).child(line.text))
            .collect::<Vec<_>>();
        div()
            .size_full()
            .overflow_hidden()
            .bg(rgb(0x0f1115))
            .text_color(rgb(0xe7e9ee))
            .font_family("JetBrains Mono")
            .text_size(px(13.0))
            .p_3()
            .child(div().flex().flex_col().children(lines))
    }
}

fn benchmark_line() -> String {
    (0..200)
        .map(|index| char::from(33 + ((index * 37 + 7) % 90) as u8))
        .collect()
}

fn build_snapshot() -> Vec<u8> {
    const TOKEN: &str = "\x1b[32mOK\x1b[0m";
    let body = TOKEN.repeat(21);
    let mut payload = Vec::with_capacity(SNAPSHOT_BYTES);
    for index in 0..10_000 {
        let suffix = if index == 9_999 {
            "RESTORE-END".to_string()
        } else {
            format!("ROW-{index:05}")
        };
        let row = format!("{body}{suffix:.<23}\r\n");
        payload.extend_from_slice(row.as_bytes());
    }
    assert_eq!(payload.len(), SNAPSHOT_BYTES);
    payload
}

fn process_cpu_seconds() -> f64 {
    let Ok(stat) = std::fs::read_to_string("/proc/self/stat") else {
        return 0.0;
    };
    let Some((_, fields)) = stat.rsplit_once(") ") else {
        return 0.0;
    };
    let fields = fields.split_whitespace().collect::<Vec<_>>();
    let user = fields.get(11).and_then(|value| value.parse::<u64>().ok());
    let system = fields.get(12).and_then(|value| value.parse::<u64>().ok());
    user.zip(system)
        .map(|(user, system)| (user + system) as f64 / 100.0)
        .unwrap_or(0.0)
}

fn input_latency_p95_micros() -> f64 {
    let terminal = TerminalEmulator::new(100, 30);
    let mut samples = (0..20_000)
        .map(|_| {
            let started = Instant::now();
            let bytes = terminal.encode_key("a", Some("a"), KeyModifiers::default());
            std::hint::black_box(bytes);
            started.elapsed().as_nanos()
        })
        .collect::<Vec<_>>();
    samples.sort_unstable();
    samples[(samples.len() * 95 / 100).min(samples.len() - 1)] as f64 / 1000.0
}

fn main() {
    Application::new().run(|cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(1100.0), px(720.0)), cx);
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                ..WindowOptions::default()
            },
            |window, cx| cx.new(|cx| TerminalBenchmark::new(window, cx)),
        )
        .expect("failed to open benchmark window");
    });
}
