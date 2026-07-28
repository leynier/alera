use alera_cloud::{maintenance, router, AppConfig, AppState};
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
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .context("apply PostgreSQL migrations")?;
    maintenance::run_once(&pool)
        .await
        .context("run startup cleanup")?;
    let maintenance_task = maintenance::spawn(pool.clone());
    let state = AppState::from_config(pool.clone(), config)?;
    let listener = tokio::net::TcpListener::bind(bind)
        .await
        .with_context(|| format!("bind {bind}"))?;
    tracing::info!(address = %bind, "Alera cloud backend listening");
    axum::serve(listener, router(state))
        .with_graceful_shutdown(shutdown_signal())
        .await
        .context("serve HTTP")?;
    maintenance_task.abort();
    pool.close().await;
    Ok(())
}

async fn shutdown_signal() {
    if let Err(error) = tokio::signal::ctrl_c().await {
        tracing::error!(error = %error, "failed to install shutdown signal handler");
    }
}
