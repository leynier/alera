use clap::{Args, Subcommand};

#[derive(Debug, Args)]
pub struct WorkflowRecipesArgs {
    #[command(subcommand)]
    pub action: WorkflowRecipesAction,
}

#[derive(Debug, Subcommand)]
pub enum WorkflowRecipesAction {
    /// List built-in and personal recipes, optionally including a source workspace.
    List {
        #[arg(long)]
        workspace: Option<String>,
    },
    /// Read one recipe by its explicit source JSON from the catalog.
    Show {
        #[arg(long)]
        source: String,
    },
    /// Validate a portable recipe without persisting or executing anything.
    Validate(WorkflowRecipeDocumentArgs),
    /// Create or update a personal recipe; updates require its current catalog revision.
    SavePersonal {
        #[command(flatten)]
        input: WorkflowRecipeDocumentArgs,
        #[arg(long)]
        expected_revision: Option<i64>,
    },
    /// Preview, or with --apply write, a recipe file into a workspace's project catalog.
    Export {
        #[command(flatten)]
        input: WorkflowRecipeDocumentArgs,
        #[arg(long)]
        workspace_id: String,
        /// File name inside the project's recipe directory.
        #[arg(long)]
        filename: String,
        /// Digest from the preview. Required with --apply.
        #[arg(long)]
        expected_digest: Option<String>,
        /// Write the previewed file. Without it the command only previews.
        #[arg(long, requires = "expected_digest")]
        apply: bool,
    },
}

#[derive(Debug, Args)]
pub struct WorkflowRecipeDocumentArgs {
    /// YAML text. Use --stdin for files or multiline input.
    #[arg(long, required_unless_present = "stdin", conflicts_with = "stdin")]
    pub document: Option<String>,
    #[arg(long)]
    pub stdin: bool,
}
