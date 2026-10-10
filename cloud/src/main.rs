use alera_cloud::{events, maintenance, migrations, router, AppConfig, AppState};
use anyhow::Context;
use sqlx::postgres::PgPoolOptions;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();
    let config = AppConfig::from_env()?;
    let bind = config.bind;
    let pool = PgPoolOptions::new()
        .max_connections(10)
        .acquire_timeout(config.http_timeout)
        .connect(&config.database_url)
        .await
        .context("connect to PostgreSQL")?;
    migrations::run_required(&pool).await?;
    let state = AppState::from_config(pool.clone(), config)?;
    let listener = tokio::net::TcpListener::bind(bind)
        .await
        .with_context(|| format!("bind {bind}"))?;
    let online_migrations_task = migrations::spawn_online(pool.clone());
    let maintenance_task = maintenance::spawn(pool.clone());
    let event_worker = state
        .config
        .events
        .worker_enabled
        .then(|| events::worker::spawn(state.clone()));
    tracing::info!(address = %bind, "Alera cloud backend listening");
    let serve_result = axum::serve(listener, router(state))
        .with_graceful_shutdown(shutdown_signal())
        .await
        .context("serve HTTP");
    online_migrations_task.abort();
    maintenance_task.abort();
    if let Some(worker) = event_worker {
        worker.abort();
    }
    pool.close().await;
    serve_result?;
    Ok(())
}

async fn shutdown_signal() {
    if let Err(error) = tokio::signal::ctrl_c().await {
        tracing::error!(error = %error, "failed to install shutdown signal handler");
    }
}
