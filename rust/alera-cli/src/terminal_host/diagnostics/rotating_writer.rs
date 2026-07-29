//! Size-bounded log file with a fixed number of backups.
//!
//! Rotation is by size rather than by date so the disk cost stays predictable
//! no matter how noisy a session gets. A host that streams terminal output for
//! a week and one that starts and crashes both stay inside the same ceiling.

use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::PathBuf;

pub const DEFAULT_MAX_BYTES: u64 = 5 * 1024 * 1024;
pub const DEFAULT_MAX_FILES: usize = 5;

pub struct RotatingFileWriter {
    directory: PathBuf,
    base_name: String,
    max_bytes: u64,
    max_files: usize,
    file: Option<File>,
    written: u64,
}

impl RotatingFileWriter {
    pub fn new(
        directory: impl Into<PathBuf>,
        base_name: impl Into<String>,
        max_bytes: u64,
        max_files: usize,
    ) -> Self {
        Self {
            directory: directory.into(),
            base_name: base_name.into(),
            max_bytes: max_bytes.max(1),
            max_files: max_files.max(1),
            file: None,
            written: 0,
        }
    }

    /// Path of the active file (`index` 0) or of a backup.
    pub fn path_for(&self, index: usize) -> PathBuf {
        let name = if index == 0 {
            format!("{}.log", self.base_name)
        } else {
            format!("{}.{index}.log", self.base_name)
        };
        self.directory.join(name)
    }

    fn ensure_open(&mut self) -> io::Result<()> {
        if self.file.is_some() {
            return Ok(());
        }
        fs::create_dir_all(&self.directory)?;
        let path = self.path_for(0);
        let file = OpenOptions::new().create(true).append(true).open(&path)?;
        self.written = file.metadata().map(|meta| meta.len()).unwrap_or(0);
        self.file = Some(file);
        Ok(())
    }

    fn rotate(&mut self) -> io::Result<()> {
        // Drop the handle first: Windows refuses to rename an open file.
        self.file = None;
        self.written = 0;

        let oldest = self.path_for(self.max_files - 1);
        if oldest.exists() {
            let _ = fs::remove_file(&oldest);
        }
        for index in (1..self.max_files.saturating_sub(1)).rev() {
            let from = self.path_for(index);
            if from.exists() {
                let _ = fs::rename(&from, self.path_for(index + 1));
            }
        }
        if self.max_files > 1 {
            let active = self.path_for(0);
            if active.exists() {
                let _ = fs::rename(&active, self.path_for(1));
            }
        } else {
            let _ = fs::remove_file(self.path_for(0));
        }
        self.ensure_open()
    }
}

impl Write for RotatingFileWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.ensure_open()?;
        // Rotating only when something is already written keeps a single record
        // larger than the cap from producing an endless run of empty files.
        if self.written > 0 && self.written.saturating_add(buf.len() as u64) > self.max_bytes {
            self.rotate()?;
        }
        let Some(file) = self.file.as_mut() else {
            return Err(io::Error::other("log file is not open"));
        };
        let written = file.write(buf)?;
        self.written = self.written.saturating_add(written as u64);
        Ok(written)
    }

    fn flush(&mut self) -> io::Result<()> {
        match self.file.as_mut() {
            Some(file) => file.flush(),
            None => Ok(()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn line_of(size: usize) -> Vec<u8> {
        let mut line = vec![b'x'; size - 1];
        line.push(b'\n');
        line
    }

    #[test]
    fn appends_to_a_single_file_while_under_the_cap() {
        let dir = tempfile::tempdir().unwrap();
        let mut writer = RotatingFileWriter::new(dir.path(), "runtime", 1024, 3);
        writer.write_all(&line_of(64)).unwrap();
        writer.write_all(&line_of(64)).unwrap();
        writer.flush().unwrap();

        assert_eq!(fs::metadata(writer.path_for(0)).unwrap().len(), 128);
        assert!(!writer.path_for(1).exists());
    }

    #[test]
    fn rotates_once_the_cap_is_exceeded() {
        let dir = tempfile::tempdir().unwrap();
        let mut writer = RotatingFileWriter::new(dir.path(), "runtime", 100, 3);
        writer.write_all(&line_of(80)).unwrap();
        writer.write_all(&line_of(80)).unwrap();
        writer.flush().unwrap();

        assert!(writer.path_for(1).exists());
        assert_eq!(fs::metadata(writer.path_for(0)).unwrap().len(), 80);
        assert_eq!(fs::metadata(writer.path_for(1)).unwrap().len(), 80);
    }

    #[test]
    fn keeps_at_most_max_files_and_discards_the_oldest() {
        let dir = tempfile::tempdir().unwrap();
        let mut writer = RotatingFileWriter::new(dir.path(), "runtime", 100, 3);
        for _ in 0..6 {
            writer.write_all(&line_of(80)).unwrap();
        }
        writer.flush().unwrap();

        assert!(writer.path_for(0).exists());
        assert!(writer.path_for(1).exists());
        assert!(writer.path_for(2).exists());
        assert!(!writer.path_for(3).exists());
    }

    #[test]
    fn a_record_larger_than_the_cap_still_gets_written() {
        let dir = tempfile::tempdir().unwrap();
        let mut writer = RotatingFileWriter::new(dir.path(), "runtime", 50, 3);
        writer.write_all(&line_of(200)).unwrap();
        writer.flush().unwrap();

        assert_eq!(fs::metadata(writer.path_for(0)).unwrap().len(), 200);
    }

    #[test]
    fn creates_the_directory_on_first_write() {
        let dir = tempfile::tempdir().unwrap();
        let nested = dir.path().join("logs");
        let mut writer = RotatingFileWriter::new(&nested, "runtime", 1024, 3);
        writer.write_all(b"first\n").unwrap();
        writer.flush().unwrap();

        assert!(nested.join("runtime.log").exists());
    }
}
