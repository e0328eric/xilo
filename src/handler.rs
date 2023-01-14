use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use base64ct::{Base64Url, Encoding};
use sha2::{Digest, Sha256};

use crate::config::XiloConfig;
use crate::error::{self, XiloError};

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum HandleType {
    File,
    Directory,
}

pub struct Initializer {
    trashbin_path: PathBuf,
    recursive: bool,
    force: bool,
    permanent: bool,
}

impl Initializer {
    pub fn new(config: Option<XiloConfig>, reset_trashbin: bool) -> error::Result<Self> {
        let default_trashbin_path = {
            let mut tmp = dirs::cache_dir().ok_or(XiloError::CannotFindCacheDirPath)?;
            tmp.push("xilo");
            tmp
        };

        let trashbin_path = if let Some(config) = config {
            if let Some(path) = config.trashbin_path {
                if cfg!(unix) {
                    expand_tilde(path).ok_or(XiloError::CannotFindTrashbinPath)?
                } else {
                    path
                }
            } else {
                default_trashbin_path
            }
        } else {
            default_trashbin_path
        };

        if reset_trashbin {
            print!("Are you sure to empty trashbin? (y/N): ");
            io::stdout().flush()?;
            let mut buf = String::new();
            io::stdin().read_line(&mut buf)?;

            match buf.trim() {
                "y" | "Y" | "yes" | "Yes" | "YES" => {
                    let dir_iter = fs::read_dir(&trashbin_path)?;
                    for entry in dir_iter {
                        let path = entry?.path();
                        if path.is_dir() {
                            fs::remove_dir_all(path)
                                .map_err(|err| XiloError::RippingTrashbinFailed(err))?;
                        } else {
                            fs::remove_file(path)
                                .map_err(|err| XiloError::RippingTrashbinFailed(err))?;
                        }
                    }
                }
                _ => {}
            }
        }

        if let Err(io::ErrorKind::NotFound) = fs::read_dir(&trashbin_path).map_err(|err| err.kind())
        {
            match fs::create_dir(&trashbin_path) {
                Ok(()) => {}
                Err(err) => {
                    return Err(XiloError::XiloInitFailed(err).into());
                }
            }
        }

        Ok(Self {
            trashbin_path,
            recursive: false,
            force: false,
            permanent: false,
        })
    }

    #[inline]
    pub fn recursive(mut self, val: bool) -> Self {
        self.recursive = val;
        self
    }

    #[inline]
    pub fn force(mut self, val: bool) -> Self {
        self.force = val;
        self
    }

    #[inline]
    pub fn permanent(mut self, val: bool) -> Self {
        self.permanent = val;
        self
    }

    pub fn make_handler(&self, handle_type: HandleType, name: PathBuf) -> Handler<'_> {
        Handler {
            handle_type,
            name,
            trashbin_path: &self.trashbin_path,
            recursive: self.recursive,
            force: self.force,
            permanent: self.permanent,
        }
    }
}

pub struct Handler<'p> {
    handle_type: HandleType,
    name: PathBuf,
    trashbin_path: &'p Path,
    recursive: bool,
    force: bool,
    permanent: bool,
}

impl<'p> Handler<'p> {
    pub fn execute(&self) -> error::Result<()> {
        use HandleType::*;

        if self.handle_type == Directory && !self.recursive {
            return Err(XiloError::RemoveDirWithoutRecursiveFlag.into());
        }

        if self.permanent {
            print!(
                "Are you sure to remove {:?} permanently? (y/N): ",
                self.name
            );
            io::stdout().flush()?;
            let mut buf = String::new();
            io::stdin().read_line(&mut buf)?;

            return match buf.trim() {
                "y" | "Y" | "yes" | "Yes" | "YES" => match self.handle_type {
                    File => fs::remove_file(&self.name).map_err(|reason| {
                        (XiloError::RemoveFilePermanentlyFailed {
                            filename: self.name.clone(),
                            reason,
                        })
                        .into()
                    }),
                    Directory => fs::remove_dir_all(&self.name).map_err(|reason| {
                        (XiloError::RemoveDirPermanentlyFailed {
                            dirname: self.name.clone(),
                            reason,
                        })
                        .into()
                    }),
                },
                _ => Ok(()),
            };
        }

        let new_name = {
            let mut hasher = Sha256::new();
            hasher.update(self.name.to_string_lossy().as_bytes());
            hasher.update(format!("{:?}", SystemTime::now()).as_bytes());
            let hash = hasher.finalize();
            let base64_hash = Base64Url::encode_string(&hash);

            let mut tmp = self.trashbin_path.to_path_buf();
            tmp.push(format!(
                "{}!{}",
                base64_hash,
                self.name.file_name().unwrap().to_string_lossy()
            ));
            tmp
        };

        if !self.force {
            print!("Are you sure to remove {:?}? (y/N): ", self.name);
            io::stdout().flush()?;
            let mut buf = String::new();
            io::stdin().read_line(&mut buf)?;

            match buf.trim() {
                "y" | "Y" | "yes" | "Yes" | "YES" => {}
                _ => return Ok(()),
            }
        }

        fs::rename(&self.name, new_name).map_err(|reason| {
            match self.handle_type {
                File => XiloError::RemoveFileFailed {
                    filename: self.name.clone(),
                    reason,
                },
                Directory => XiloError::RemoveDirFailed {
                    dirname: self.name.clone(),
                    reason,
                },
            }
            .into()
        })
    }
}

// Code stolen from https://stackoverflow.com/questions/54267608/expand-tilde-in-rust-path-idiomatically
#[cfg(unix)]
fn expand_tilde<P: AsRef<Path>>(path_user_input: P) -> Option<PathBuf> {
    let p = path_user_input.as_ref();
    if !p.starts_with("~") {
        return Some(p.to_path_buf());
    }
    if p == Path::new("~") {
        return dirs::home_dir();
    }
    dirs::home_dir().map(|mut h| {
        if h == Path::new("/") {
            // Corner case: `h` root directory;
            // don't prepend extra `/`, just drop the tilde.
            p.strip_prefix("~").unwrap().to_path_buf()
        } else {
            h.push(p.strip_prefix("~/").unwrap());
            h
        }
    })
}
