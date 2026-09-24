use super::{OutputArgs, RuntimeDirArgs};
use clap::{Args, Subcommand};

#[derive(Debug, Args)]
pub struct VoiceCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: VoiceAction,
}

#[derive(Debug, Subcommand)]
pub enum VoiceAction {
    /// Create or refresh the runtime home folder and AGENTS.md contract.
    Ensure,
    /// Show the home workspace, session, and pipeline.
    Status,
    /// Queue text for the human to hear.
    Speak(VoiceSpeakArgs),
}

#[derive(Debug, Args)]
pub struct VoiceSpeakArgs {
    #[arg(long)]
    pub text: String,
}
