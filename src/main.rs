mod command;
mod config;
mod error;
mod handler;

use std::io;

use clap::{CommandFactory, Parser};
use crossterm::{
    execute,
    style::{Attribute, Color, Print, ResetColor, SetAttribute, SetForegroundColor},
};

use handler::{HandleType, Initializer};

fn main() -> error::Result<()> {
    let command::XiloCommand {
        filenames,
        recursive,
        force,
        permanent,
    } = command::XiloCommand::parse();

    if !permanent && filenames.is_empty() {
        command::XiloCommand::command().print_long_help()?;
        return Ok(());
    }

    let config = config::XiloConfig::new()?;

    let initializer = Initializer::new(
        config,
        if filenames.is_empty() {
            permanent
        } else {
            false
        },
    )?
    .recursive(recursive)
    .force(force)
    .permanent(permanent);

    if !filenames.is_empty() && recursive && !filenames.iter().any(|path| path.is_dir()) {
        execute!(
            io::stdout(),
            SetAttribute(Attribute::Bold),
            SetForegroundColor(Color::Magenta),
            Print("Note".to_string()),
            SetForegroundColor(Color::White),
            Print(": ".to_string()),
            Print("Recursive flag effects nothing while removing a file.\n".to_string()),
            ResetColor,
        )?;
    }

    let mut handler;
    for name in filenames {
        if name.is_dir() {
            handler = initializer.make_handler(HandleType::Directory, name);
        } else {
            handler = initializer.make_handler(HandleType::File, name);
        }
        handler.execute()?;
    }

    Ok(())
}
