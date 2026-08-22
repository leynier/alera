use anyhow::Result;
use sqlx::sqlite::SqliteRow;
use sqlx::Row;

use super::store::parse_timestamp;
use super::{MobileAccessSettings, MobileEndpointMode, MobileNetbirdEndpoint};

pub(super) fn mobile_access_settings_from_row(row: SqliteRow) -> Result<MobileAccessSettings> {
    Ok(MobileAccessSettings {
        enabled: row.try_get::<i64, _>("enabled")? == 1,
        remote_access_enabled: row.try_get::<i64, _>("remoteAccessEnabled")? == 1,
        bind_host: row.try_get("bindHost")?,
        port: row.try_get("port")?,
        endpoint_mode: MobileEndpointMode::from_db(
            row.try_get::<String, _>("endpointMode")?.as_str(),
        ),
        netbird_endpoint: MobileNetbirdEndpoint::from_db(
            row.try_get::<String, _>("netbirdEndpoint")?.as_str(),
        ),
        server_public_key_b64: row.try_get("serverPublicKeyB64")?,
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
    })
}
