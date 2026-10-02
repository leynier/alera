use std::io::{self, Write};

use serde::Serialize;

/// Stop counting at the budget without allocating a complete encoded copy.
pub(crate) fn serialized_bytes<T: Serialize>(value: &T, budget: usize) -> usize {
    let mut writer = BudgetWriter { budget, bytes: 0 };
    match serde_json::to_writer(&mut writer, value) {
        Ok(()) => writer.bytes.saturating_add(1),
        Err(_) => budget.saturating_add(1),
    }
}

struct BudgetWriter {
    budget: usize,
    bytes: usize,
}

impl Write for BudgetWriter {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        let remaining = self.budget.saturating_sub(self.bytes);
        if bytes.len() > remaining {
            self.bytes = self.budget;
            return Err(io::Error::new(
                io::ErrorKind::WriteZero,
                "serialized payload exceeds its admission budget",
            ));
        }
        self.bytes += bytes.len();
        Ok(bytes.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}
