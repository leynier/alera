use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};

use git2::{Config, ConfigLevel, ErrorCode, Repository};
use notify::{RecommendedWatcher, RecursiveMode, Watcher};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::watcher_error;

#[derive(Default)]
pub(super) struct GitIgnoreSources {
    files: HashSet<PathBuf>,
    directories: HashSet<PathBuf>,
}

#[derive(Clone, Default)]
pub(in crate::terminal_host::server::terminal_pulse) struct GitConfigEnvironment {
    home: Option<PathBuf>,
    xdg_config_home: Option<PathBuf>,
    global_config: Option<PathBuf>,
    system_config: Option<PathBuf>,
    no_system_config: bool,
}

impl GitConfigEnvironment {
    pub(in crate::terminal_host::server::terminal_pulse) fn new(
        home: Option<PathBuf>,
        xdg_config_home: Option<PathBuf>,
        global_config: Option<PathBuf>,
        system_config: Option<PathBuf>,
        no_system_config: bool,
    ) -> Self {
        Self {
            home,
            xdg_config_home,
            global_config,
            system_config,
            no_system_config,
        }
    }

    #[cfg(test)]
    pub(super) fn from_process() -> Self {
        Self::new(
            dirs::home_dir(),
            std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from),
            std::env::var_os("GIT_CONFIG_GLOBAL").map(PathBuf::from),
            std::env::var_os("GIT_CONFIG_SYSTEM").map(PathBuf::from),
            std::env::var_os("GIT_CONFIG_NOSYSTEM").is_some_and(|value| value != "0"),
        )
    }

    fn home(&self) -> Option<&Path> {
        self.home.as_deref()
    }

    fn xdg_directory(&self) -> Option<PathBuf> {
        self.xdg_config_home
            .clone()
            .or_else(|| self.home().map(|home| home.join(".config")))
    }
}

impl GitIgnoreSources {
    pub(super) fn discover(
        repository: &Repository,
        environment: &GitConfigEnvironment,
    ) -> HostResult<Self> {
        let mut files = HashSet::new();
        files.insert(repository.path().join("config"));
        files.insert(repository.commondir().join("config"));
        files.insert(repository.path().join("config.worktree"));
        files.insert(repository.commondir().join("config.worktree"));
        if !environment.no_system_config {
            files.extend(
                environment
                    .system_config
                    .clone()
                    .or_else(|| Config::find_system().ok()),
            );
        }
        files.extend(
            environment
                .global_config
                .clone()
                .or_else(|| environment.home().map(|home| home.join(".gitconfig")))
                .or_else(|| Config::find_global().ok()),
        );
        if let Some(xdg) = environment.xdg_directory() {
            files.insert(xdg.join("git/config"));
            files.insert(xdg.join("git/ignore"));
        } else if let Ok(xdg) = Config::find_xdg() {
            files.insert(xdg);
        }
        let config = repository.config().map_err(git_source_error)?;
        match config.get_path("core.excludesFile") {
            Ok(path) => {
                files.insert(resolve_config_path(repository, path));
            }
            Err(error) if error.code() == ErrorCode::NotFound => {}
            Err(error) => return Err(git_source_error(error)),
        }
        let directories = files
            .iter()
            .filter_map(|path| path.parent())
            .filter(|path| path.is_dir())
            .map(Path::to_path_buf)
            .collect();
        Ok(Self { files, directories })
    }

    pub(super) fn contains(&self, path: &Path) -> bool {
        self.files.contains(path)
            || path
                .file_name()
                .and_then(|name| name.to_str())
                .and_then(|name| name.strip_suffix(".lock"))
                .is_some_and(|name| self.files.contains(&path.with_file_name(name)))
    }
}

pub(super) fn prepare_repository(
    repository: Repository,
    environment: &GitConfigEnvironment,
) -> HostResult<Repository> {
    let mut config = if environment.global_config.is_some()
        || environment.system_config.is_some()
        || environment.no_system_config
    {
        rebuild_repository_config(&repository, environment)?
    } else {
        repository.config().map_err(git_source_error)?
    };
    let xdg_config = environment
        .xdg_directory()
        .map(|directory| directory.join("git/config"));
    add_environment_config(&mut config, xdg_config.as_deref(), ConfigLevel::XDG)?;
    let global_config = environment
        .global_config
        .clone()
        .or_else(|| environment.home().map(|home| home.join(".gitconfig")));
    add_environment_config(&mut config, global_config.as_deref(), ConfigLevel::Global)?;
    repository.set_config(&config).map_err(git_source_error)?;

    let config = repository.config().map_err(git_source_error)?;
    let default_exclude = environment
        .xdg_directory()
        .map(|directory| directory.join("git/ignore"));
    let exclude = match config.get_path("core.excludesFile") {
        Ok(path) => Some(resolve_config_path(&repository, path)),
        Err(error) if error.code() == ErrorCode::NotFound => default_exclude,
        Err(error) => return Err(git_source_error(error)),
    };
    if let Some(exclude) = exclude.filter(|path| path.is_file()) {
        let rules = std::fs::read_to_string(&exclude).map_err(|error| {
            HostError::state(format!(
                "Terminal Pulse could not read Git ignore source {}: {error}",
                exclude.display()
            ))
        })?;
        repository
            .add_ignore_rule(&rules)
            .map_err(git_source_error)?;
    }
    Ok(repository)
}

fn rebuild_repository_config(
    repository: &Repository,
    environment: &GitConfigEnvironment,
) -> HostResult<Config> {
    let mut config = Config::new().map_err(git_source_error)?;
    if !environment.no_system_config {
        let system = environment
            .system_config
            .clone()
            .or_else(|| Config::find_system().ok());
        add_environment_config(&mut config, system.as_deref(), ConfigLevel::System)?;
    }
    let xdg = environment
        .xdg_directory()
        .map(|directory| directory.join("git/config"))
        .or_else(|| Config::find_xdg().ok());
    add_environment_config(&mut config, xdg.as_deref(), ConfigLevel::XDG)?;
    let global = environment
        .global_config
        .clone()
        .or_else(|| environment.home().map(|home| home.join(".gitconfig")))
        .or_else(|| Config::find_global().ok());
    add_environment_config(&mut config, global.as_deref(), ConfigLevel::Global)?;
    let local = repository.commondir().join("config");
    add_environment_config(&mut config, Some(&local), ConfigLevel::Local)?;
    let worktree = repository.path().join("config.worktree");
    add_environment_config(&mut config, Some(&worktree), ConfigLevel::Worktree)?;
    Ok(config)
}

pub(super) fn reopen_repository(
    repository: &Repository,
    environment: &GitConfigEnvironment,
) -> HostResult<Repository> {
    let repository_root = repository.workdir().unwrap_or_else(|| repository.path());
    let repository = Repository::open(repository_root).map_err(git_source_error)?;
    prepare_repository(repository, environment)
}

pub(super) fn refresh_git_ignore_source_watches(
    sources: &Arc<RwLock<GitIgnoreSources>>,
    watched: &mut HashSet<PathBuf>,
    workspace_watches: &HashSet<PathBuf>,
    watcher: &mut RecommendedWatcher,
    repository: &Repository,
    environment: &GitConfigEnvironment,
) -> HostResult<()> {
    let next = GitIgnoreSources::discover(repository, environment)?;
    let additions = next
        .directories
        .difference(watched)
        .cloned()
        .collect::<Vec<_>>();
    for directory in additions {
        if !workspace_watches.contains(&directory) {
            watcher
                .watch(&directory, RecursiveMode::NonRecursive)
                .map_err(watcher_error)?;
        }
        watched.insert(directory);
    }
    *sources
        .write()
        .map_err(|_| HostError::state("Terminal Pulse Git ignore source lock failed."))? = next;
    Ok(())
}

fn add_environment_config(
    config: &mut Config,
    path: Option<&Path>,
    level: ConfigLevel,
) -> HostResult<()> {
    let Some(path) = path.filter(|path| path.is_file()) else {
        return Ok(());
    };
    config.add_file(path, level, true).map_err(git_source_error)
}

fn resolve_config_path(repository: &Repository, path: PathBuf) -> PathBuf {
    if path.is_absolute() {
        return path;
    }
    repository
        .workdir()
        .map_or(path.clone(), |workdir| workdir.join(path))
}

fn git_source_error(error: git2::Error) -> HostError {
    HostError::state(format!(
        "Terminal Pulse could not inspect Git ignore sources: {error}"
    ))
}

#[cfg(test)]
#[path = "terminal_pulse_git_ignore_source_cases.rs"]
mod cases;
