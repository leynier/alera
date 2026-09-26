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
}

#[derive(Debug, Args)]
pub struct WorkflowRecipeDocumentArgs {
    /// YAML text. Use --stdin for files or multiline input.
    #[arg(long, required_unless_present = "stdin", conflicts_with = "stdin")]
    pub document: Option<String>,
    #[arg(long)]
    pub stdin: bool,
}
