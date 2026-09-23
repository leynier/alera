#[cfg(unix)]
mod platform {
    use anyhow::Result;
    use std::io::IsTerminal;

    pub(crate) struct TerminalStdioMode(Option<libc::termios>);

    impl TerminalStdioMode {
        pub(crate) fn enter() -> Result<Self> {
            if !std::io::stdin().is_terminal() {
                return Ok(Self(None));
            }
            let mut original = std::mem::MaybeUninit::uninit();
            // The descriptor is borrowed from stdin; the guard restores its settings.
            unsafe {
                if libc::tcgetattr(libc::STDIN_FILENO, original.as_mut_ptr()) != 0 {
                    return Err(std::io::Error::last_os_error().into());
                }
                let original = original.assume_init();
                let mut raw = original;
                libc::cfmakeraw(&mut raw);
                if libc::tcsetattr(libc::STDIN_FILENO, libc::TCSANOW, &raw) != 0 {
                    return Err(std::io::Error::last_os_error().into());
                }
                Ok(Self(Some(original)))
            }
        }
    }

    impl Drop for TerminalStdioMode {
        fn drop(&mut self) {
            if let Some(original) = &self.0 {
                unsafe { libc::tcsetattr(libc::STDIN_FILENO, libc::TCSANOW, original) };
            }
        }
    }

    pub(crate) fn dimensions() -> Option<(u16, u16)> {
        let mut size = std::mem::MaybeUninit::<libc::winsize>::uninit();
        unsafe {
            if libc::ioctl(libc::STDIN_FILENO, libc::TIOCGWINSZ, size.as_mut_ptr()) != 0 {
                return None;
            }
            let size = size.assume_init();
            (size.ws_col > 0 && size.ws_row > 0).then_some((size.ws_col, size.ws_row))
        }
    }
}

#[cfg(windows)]
mod platform {
    use anyhow::Result;
    use windows::Win32::{Foundation::HANDLE, System::Console::*};

    pub(crate) struct TerminalStdioMode(Vec<(HANDLE, CONSOLE_MODE)>);

    impl TerminalStdioMode {
        pub(crate) fn enter() -> Result<Self> {
            let mut guard = Self(Vec::new());
            unsafe {
                for (kind, input) in [(STD_INPUT_HANDLE, true), (STD_OUTPUT_HANDLE, false)] {
                    let handle = GetStdHandle(kind)?;
                    let mut original = CONSOLE_MODE::default();
                    if GetConsoleMode(handle, &mut original).is_err() {
                        continue;
                    }
                    let mode = if input {
                        (original
                            & !(ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT | ENABLE_PROCESSED_INPUT))
                            | ENABLE_VIRTUAL_TERMINAL_INPUT
                    } else {
                        original | ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN
                    };
                    SetConsoleMode(handle, mode)?;
                    guard.0.push((handle, original));
                }
            }
            Ok(guard)
        }
    }

    impl Drop for TerminalStdioMode {
        fn drop(&mut self) {
            for (handle, original) in &self.0 {
                unsafe {
                    let _ = SetConsoleMode(*handle, *original);
                }
            }
        }
    }

    pub(crate) fn dimensions() -> Option<(u16, u16)> {
        unsafe {
            let handle = GetStdHandle(STD_OUTPUT_HANDLE).ok()?;
            let mut info = CONSOLE_SCREEN_BUFFER_INFO::default();
            GetConsoleScreenBufferInfo(handle, &mut info).ok()?;
            let cols =
                u16::try_from(i32::from(info.srWindow.Right) - i32::from(info.srWindow.Left) + 1)
                    .ok()?;
            let rows =
                u16::try_from(i32::from(info.srWindow.Bottom) - i32::from(info.srWindow.Top) + 1)
                    .ok()?;
            (cols > 0 && rows > 0).then_some((cols, rows))
        }
    }
}

pub(crate) use platform::{dimensions, TerminalStdioMode};
