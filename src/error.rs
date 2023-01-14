use std::io;
use std::path::PathBuf;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum XiloError {
    #[error("{0}")]
    IOErr(#[from] io::Error),

    #[error("initializing xilo failed. Detail: {0}")]
    XiloInitFailed(io::Error),

    #[error("cannot find the cache directory path")]
    CannotFindCacheDirPath,

    #[error("cannot find the config directory path")]
    CannotFindConfigDirPath,

    #[error("cannot find the trashbin path")]
    CannotFindTrashbinPath,

    #[error("removing the trashbin directory failed. Detail: {0}")]
    RippingTrashbinFailed(io::Error),

    #[error("cannot remove the file {filename}. Detail: {reason}")]
    RemoveFileFailed {
        filename: PathBuf,
        reason: io::Error,
    },

    #[error("cannot remove the file {filename} permanently. Detail: {reason}")]
    RemoveFilePermanentlyFailed {
        filename: PathBuf,
        reason: io::Error,
    },

    #[error("directory cannot removed without `-r` flag")]
    RemoveDirWithoutRecursiveFlag,

    #[error("cannot remove the directory {dirname}. Detail: {reason}")]
    RemoveDirFailed { dirname: PathBuf, reason: io::Error },

    #[error("cannot remove the directory {dirname} permanently. Detail: {reason}")]
    RemoveDirPermanentlyFailed { dirname: PathBuf, reason: io::Error },
}

pub type Result<T> = anyhow::Result<T>;
