use std::fs::File;
use std::io;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::error::{self, XiloError};

#[derive(Debug, Serialize, Deserialize)]
pub struct XiloConfig {
    pub trashbin_path: Option<PathBuf>,
}

impl XiloConfig {
    pub fn new() -> error::Result<Option<Self>> {
        let mut xilo_config = dirs::config_dir().ok_or(XiloError::CannotFindConfigDirPath)?;
        xilo_config.push("xilo");
        xilo_config.push("xilo.json");

        match File::open(xilo_config).map_err(|err| err.kind()) {
            Ok(file) => Ok(Some(serde_json::from_reader(file)?)),
            Err(io::ErrorKind::NotFound) => Ok(None),
            Err(err) => Err(io::Error::from(err).into()),
        }
    }
}
