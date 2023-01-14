use std::path::PathBuf;

use clap::Parser;

#[derive(Debug, Parser)]
#[command(author, version, about, long_about = None)]
pub struct XiloCommand {
    #[arg(value_name = "FILES")]
    pub filenames: Vec<PathBuf>,

    /// Remove directory recursively.
    #[arg(short, long)]
    pub recursive: bool,
    /// Force to delete files/directories.
    #[arg(short, long)]
    pub force: bool,
    /// Empty the trashbin if FILES are empty. Otherwise, delete contents unrecoverably.
    #[arg(short, long)]
    pub permanent: bool,
}
