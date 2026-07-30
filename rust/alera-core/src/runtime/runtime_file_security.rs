use std::fs::{self, OpenOptions};
use std::io;
use std::path::Path;

#[cfg(unix)]
use std::os::unix::fs::{OpenOptionsExt as _, PermissionsExt as _};

pub fn prepare_private_runtime_directory(path: &Path) -> io::Result<()> {
    fs::create_dir_all(path)?;
    set_private_directory_permissions(path)
}

pub fn create_private_runtime_file(path: &Path) -> io::Result<fs::File> {
    let mut options = OpenOptions::new();
    options.create(true).write(true).truncate(true);
    #[cfg(unix)]
    options.mode(0o600);
    let file = options.open(path)?;
    set_private_file_permissions(path)?;
    Ok(file)
}

pub fn open_private_runtime_file(path: &Path) -> io::Result<fs::File> {
    let mut options = OpenOptions::new();
    options.create(true).write(true);
    #[cfg(unix)]
    options.mode(0o600);
    let file = options.open(path)?;
    set_private_file_permissions(path)?;
    Ok(file)
}

pub fn harden_sqlite_files(database_path: &Path) -> io::Result<()> {
    set_private_file_permissions(database_path)?;
    for suffix in ["-wal", "-shm"] {
        let path = database_path.with_file_name(format!(
            "{}{suffix}",
            database_path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or_default()
        ));
        if path.exists() {
            set_private_file_permissions(&path)?;
        }
    }
    Ok(())
}

pub fn set_private_file_permissions(path: &Path) -> io::Result<()> {
    #[cfg(unix)]
    {
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    }
    #[cfg(not(unix))]
    {
        let _ = path;
    }
    Ok(())
}

fn set_private_directory_permissions(path: &Path) -> io::Result<()> {
    #[cfg(unix)]
    {
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    }
    #[cfg(not(unix))]
    {
        let _ = path;
    }
    Ok(())
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    #[test]
    fn runtime_directory_and_files_are_private() {
        let temp = tempfile::tempdir().unwrap();
        let runtime = temp.path().join("runtime");
        prepare_private_runtime_directory(&runtime).unwrap();
        let database = runtime.join("runtime.sqlite");
        create_private_runtime_file(&database).unwrap();
        fs::write(runtime.join("runtime.sqlite-wal"), b"wal").unwrap();
        fs::write(runtime.join("runtime.sqlite-shm"), b"shm").unwrap();
        harden_sqlite_files(&database).unwrap();

        assert_eq!(
            fs::metadata(&runtime).unwrap().permissions().mode() & 0o777,
            0o700
        );
        for name in ["runtime.sqlite", "runtime.sqlite-wal", "runtime.sqlite-shm"] {
            assert_eq!(
                fs::metadata(runtime.join(name))
                    .unwrap()
                    .permissions()
                    .mode()
                    & 0o777,
                0o600
            );
        }
    }

    #[test]
    fn opening_an_existing_runtime_file_preserves_its_contents() {
        let temp = tempfile::tempdir().unwrap();
        let database = temp.path().join("runtime.sqlite");
        fs::write(&database, b"existing database").unwrap();

        open_private_runtime_file(&database).unwrap();

        assert_eq!(fs::read(database).unwrap(), b"existing database");
    }
}
