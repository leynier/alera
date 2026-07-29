use super::{IdArgs, OutputArgs, RuntimeDirArgs};
use clap::{Args, Subcommand};

#[derive(Debug, Args)]
pub struct MobileCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: MobileAction,
}

#[derive(Debug, Subcommand)]
pub enum MobileAction {
    /// Show mobile access settings, devices, and active pairing offers.
    Status,
    /// Enable the mobile gateway settings.
    Enable(MobileEnableArgs),
    /// Disable the mobile gateway settings.
    Disable,
    /// Create a short-lived pairing offer.
    Pairing(MobilePairingCommand),
    /// List, rename, revoke, or delete paired devices.
    Devices(MobileDevicesCommand),
}

#[derive(Debug, Args)]
pub struct MobileEnableArgs {
    #[arg(long = "bind-host")]
    pub bind_host: Option<String>,
    #[arg(long)]
    pub port: Option<i64>,
    /// Bind the gateway to this machine's Tailscale tailnet IP.
    #[arg(long, conflicts_with = "bind_host")]
    pub tailscale: bool,
}

#[derive(Debug, Args)]
pub struct MobilePairingCommand {
    #[command(subcommand)]
    pub action: MobilePairingAction,
}

#[derive(Debug, Subcommand)]
pub enum MobilePairingAction {
    /// Create a short-lived pairing offer for QR or manual entry.
    Create(MobilePairingCreateArgs),
    /// Claim a pairing offer and create a revocable device record.
    Claim(MobilePairingClaimArgs),
    /// Cancel an active pairing offer.
    Cancel(IdArgs),
}

#[derive(Debug, Args)]
pub struct MobilePairingCreateArgs {
    #[arg(long)]
    pub endpoint: Option<String>,
    #[arg(long = "device-name")]
    pub device_name: Option<String>,
    #[arg(long = "expires-minutes")]
    pub expires_minutes: Option<i64>,
}

#[derive(Debug, Args)]
pub struct MobilePairingClaimArgs {
    #[arg(long = "pairing-id")]
    pub pairing_id: String,
    #[arg(long = "pairing-secret")]
    pub pairing_secret: String,
    #[arg(long = "device-name")]
    pub device_name: Option<String>,
    #[arg(long = "public-key-b64")]
    pub public_key_b64: Option<String>,
}

#[derive(Debug, Args)]
pub struct MobileDevicesCommand {
    #[command(subcommand)]
    pub action: MobileDevicesAction,
}

#[derive(Debug, Subcommand)]
pub enum MobileDevicesAction {
    /// List paired mobile devices.
    List(MobileDeviceListArgs),
    /// Rename a paired mobile device.
    Rename(MobileDeviceRenameArgs),
    /// Revoke a paired mobile device.
    Revoke(IdArgs),
    /// Permanently delete a revoked mobile device record.
    Delete(IdArgs),
}

#[derive(Debug, Args)]
pub struct MobileDeviceRenameArgs {
    #[arg(long)]
    pub id: String,
    #[arg(long)]
    pub name: String,
}

#[derive(Debug, Args)]
pub struct MobileDeviceListArgs {
    #[arg(long = "include-revoked")]
    pub include_revoked: bool,
}
