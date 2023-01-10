#![allow(unused)]

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use base64ct::{Base64Url, Encoding};
use clap::{CommandFactory, Parser};
use crossterm::style::{Attribute, Color, Print, ResetColor, SetAttribute, SetForegroundColor};
use crossterm::{execute, Command};
use error_stack::{IntoReport, Report, Result, ResultExt};
use sha2::{Digest, Sha256};
use thiserror::Error;

#[derive(Debug, Parser)]
#[command(author, version, about, long_about = None)]
struct XiloCommand {
    #[arg(value_name = "FILES")]
    filenames: Vec<PathBuf>,

    /// Remove directory recursively.
    #[arg(short, long)]
    recursive: bool,
    /// Force to delete files/directories.
    #[arg(short, long)]
    force: bool,
    /// Empty the trashbin if FILES are empty. Otherwise, delete contents unrecoverably.
    #[arg(short, long)]
    permanent: bool,
}

#[derive(Debug, Error)]
enum XiloError {
    #[error("initializing xilo failed. Detail: {0}")]
    XiloInitFailed(Report<io::Error>),

    #[error("cannot find the cache directory path")]
    CannotFindCacheDirPath,

    #[error("removing the trashbin directory failed. Detail: {0}")]
    RippingTrashbinFailed(Report<io::Error>),

    #[error("cannot remove the file {filename}. Detail: {reason}")]
    RemoveFileFailed {
        filename: PathBuf,
        reason: Report<io::Error>,
    },

    #[error("cannot remove the file {filename} permanently. Detail: {reason}")]
    RemoveFilePermanentlyFailed {
        filename: PathBuf,
        reason: Report<io::Error>,
    },

    #[error("directory cannot removed without `-r` flag")]
    RemoveDirWithoutRecursiveFlag,

    #[error("cannot remove the directory {dirname}. Detail: {reason}")]
    RemoveDirFailed {
        dirname: PathBuf,
        reason: Report<io::Error>,
    },

    #[error("cannot remove the directory {dirname} permanently. Detail: {reason}")]
    RemoveDirPermanentlyFailed {
        dirname: PathBuf,
        reason: Report<io::Error>,
    },

    #[error("there is no file called {filename}")]
    FileNotFound { filename: PathBuf },

    #[error("Unexpected error occurs")]
    Unexpected,
}

fn main() -> Result<(), XiloError> {
    let XiloCommand {
        filenames,
        recursive,
        force,
        permanent,
    } = XiloCommand::parse();

    if !permanent && filenames.is_empty() {
        XiloCommand::command().print_long_help();
        return Ok(());
    }

    let trashbin_path = init_xilo(if filenames.is_empty() {
        permanent
    } else {
        false
    })?;

    if !filenames.is_empty() && !filenames.iter().any(|path| path.is_dir()) {
        execute!(
            io::stdout(),
            SetAttribute(Attribute::Bold),
            SetForegroundColor(Color::Magenta),
            Print("Note".to_string()),
            SetForegroundColor(Color::White),
            Print(": ".to_string()),
            Print("Recursive flag effects nothing while removing a file.\n".to_string()),
            ResetColor,
        )
        .into_report()
        .attach_printable_lazy(|| "cannot write a warning message in the console")
        .change_context(XiloError::Unexpected);
    }

    for filename in filenames {
        if filename.is_dir() {
            handle_directory(filename, &trashbin_path, recursive, force, permanent)?;
        } else {
            handle_file(filename, &trashbin_path, recursive, force, permanent)?;
        }
    }

    Ok(())
}

fn init_xilo(reset_trashbin: bool) -> Result<PathBuf, XiloError> {
    // TODO: implement config file that makes trashbin path changed.
    let trashbin_path = {
        let mut tmp = dirs::cache_dir().ok_or(XiloError::CannotFindCacheDirPath)?;
        tmp.push("xilo");
        tmp
    };

    if reset_trashbin {
        print!("Are you sure to empty trashbin? (y/N): ");
        io::stdout()
            .flush()
            .into_report()
            .change_context(XiloError::Unexpected)?;
        let mut buf = String::new();
        io::stdin()
            .read_line(&mut buf)
            .into_report()
            .change_context(XiloError::Unexpected)?;

        match buf.trim() {
            "y" | "Y" | "yes" | "Yes" | "YES" => {
                match fs::remove_dir_all(&trashbin_path).into_report() {
                    Ok(()) => {}
                    Err(mut err) => {
                        err = err.attach_printable(format!(
                            "cannot remove the directory {:?}.",
                            &trashbin_path
                        ));
                        return Err(Report::new(XiloError::RippingTrashbinFailed(err)));
                    }
                }
            }
            _ => {}
        }
    }

    if let Err(io::ErrorKind::NotFound) = fs::read_dir(&trashbin_path).map_err(|err| err.kind()) {
        match fs::create_dir(&trashbin_path).into_report() {
            Ok(()) => {}
            Err(mut err) => {
                err = err
                    .attach_printable(format!("cannot make the directory {:?}.", &trashbin_path));
                return Err(Report::new(XiloError::XiloInitFailed(err)));
            }
        }
    }

    Ok(trashbin_path)
}

fn handle_directory(
    dirname: PathBuf,
    trashbin_path: &Path,
    recursive: bool,
    force: bool,
    permanent: bool,
) -> Result<(), XiloError> {
    if !recursive {
        return Err(Report::new(XiloError::RemoveDirWithoutRecursiveFlag));
    }

    if permanent {
        print!("Are you sure to remove {:?} permanently? (y/N): ", dirname);
        io::stdout()
            .flush()
            .into_report()
            .change_context(XiloError::Unexpected)?;
        let mut buf = String::new();
        io::stdin()
            .read_line(&mut buf)
            .into_report()
            .change_context(XiloError::Unexpected)?;

        match buf.trim() {
            "y" | "Y" | "yes" | "Yes" | "YES" => {
                return match fs::remove_dir_all(&dirname).into_report() {
                    Ok(()) => Ok(()),
                    Err(reason) => Err(Report::new(XiloError::RemoveDirPermanentlyFailed {
                        dirname,
                        reason,
                    })),
                };
            }
            _ => return Ok(()),
        }
    }

    let new_dirname = {
        let mut hasher = Sha256::new();
        hasher.update(dirname.to_string_lossy().as_bytes());
        hasher.update(format!("{:?}", SystemTime::now()).as_bytes());
        let hash = hasher.finalize();
        let base64_hash = Base64Url::encode_string(&hash);

        let mut tmp = trashbin_path.to_path_buf();
        tmp.push(format!(
            "{}!{}",
            base64_hash,
            dirname.file_name().unwrap().to_string_lossy()
        ));
        tmp
    };

    if !force {
        print!("Are you sure to remove {:?}? (y/N): ", dirname);
        io::stdout()
            .flush()
            .into_report()
            .change_context(XiloError::Unexpected)?;
        let mut buf = String::new();
        io::stdin()
            .read_line(&mut buf)
            .into_report()
            .change_context(XiloError::Unexpected)?;

        match buf.trim() {
            "y" | "Y" | "yes" | "Yes" | "YES" => {}
            _ => return Ok(()),
        }
    }

    match fs::rename(&dirname, new_dirname).into_report() {
        Ok(()) => Ok(()),
        Err(reason) => Err(Report::new(XiloError::RemoveDirFailed { dirname, reason })),
    }
}

fn handle_file(
    filename: PathBuf,
    trashbin_path: &Path,
    _recursive: bool,
    force: bool,
    permanent: bool,
) -> Result<(), XiloError> {
    if permanent {
        print!("Are you sure to remove {:?} permanently? (y/N): ", filename);
        io::stdout()
            .flush()
            .into_report()
            .change_context(XiloError::Unexpected)?;
        let mut buf = String::new();
        io::stdin()
            .read_line(&mut buf)
            .into_report()
            .change_context(XiloError::Unexpected)?;

        match buf.trim() {
            "y" | "Y" | "yes" | "Yes" | "YES" => {
                return match fs::remove_file(&filename).into_report() {
                    Ok(()) => Ok(()),
                    Err(reason) => Err(Report::new(XiloError::RemoveFilePermanentlyFailed {
                        filename,
                        reason,
                    })),
                };
            }
            _ => return Ok(()),
        }
    }

    let new_filename = {
        let mut hasher = Sha256::new();
        hasher.update(filename.to_string_lossy().as_bytes());
        hasher.update(format!("{:?}", SystemTime::now()).as_bytes());
        let hash = hasher.finalize();
        let base64_hash = Base64Url::encode_string(&hash);

        let mut tmp = trashbin_path.to_path_buf();
        tmp.push(format!(
            "{}!{}",
            base64_hash,
            filename.file_name().unwrap().to_string_lossy()
        ));
        tmp
    };

    if !force {
        print!("Are you sure to remove {:?}? (y/N): ", filename);
        io::stdout()
            .flush()
            .into_report()
            .change_context(XiloError::Unexpected)?;
        let mut buf = String::new();
        io::stdin()
            .read_line(&mut buf)
            .into_report()
            .change_context(XiloError::Unexpected)?;

        match buf.trim() {
            "y" | "Y" | "yes" | "Yes" | "YES" => {}
            _ => return Ok(()),
        }
    }

    println!("{:?}", new_filename);

    match fs::rename(&filename, new_filename).into_report() {
        Ok(()) => Ok(()),
        Err(reason) => Err(Report::new(XiloError::RemoveFileFailed {
            filename,
            reason,
        })),
    }
}
