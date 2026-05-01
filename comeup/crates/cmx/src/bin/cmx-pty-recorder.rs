#![cfg_attr(
    not(test),
    deny(
        clippy::expect_used,
        clippy::panic,
        clippy::todo,
        clippy::unimplemented,
        clippy::unwrap_used
    )
)]

use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::mpsc;
use std::time::Duration;

use anyhow::{Context, Result, anyhow, bail};
use portable_pty::{CommandBuilder, PtySize, native_pty_system};

fn main() -> Result<()> {
    let args = Args::parse(std::env::args().skip(1))?;
    let pty_system = native_pty_system();
    let pair = pty_system
        .openpty(PtySize {
            rows: args.rows,
            cols: args.cols,
            pixel_width: 0,
            pixel_height: 0,
        })
        .context("open cmx pty")?;

    let mut cmx_path = std::env::current_exe().context("resolve recorder path")?;
    cmx_path.set_file_name("cmx");
    let mut command = CommandBuilder::new(cmx_path);
    command.arg("--socket");
    command.arg(args.socket);
    command.arg("--cols");
    command.arg(args.cols.to_string());
    command.arg("--rows");
    command.arg(args.rows.to_string());

    let child = pair.slave.spawn_command(command).context("spawn cmx")?;
    let mut killer = child.clone_killer();
    drop(pair.slave);

    let mut reader = pair.master.try_clone_reader().context("clone pty reader")?;
    let _writer = pair.master.take_writer().context("take pty writer")?;
    let (done_tx, done_rx) = mpsc::channel::<Result<()>>();

    std::thread::spawn(move || {
        let mut stdout = std::io::stdout();
        let mut buf = [0; 8192];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => {
                    let _ = done_tx.send(Ok(()));
                    return;
                }
                Ok(n) => {
                    if let Err(err) = stdout.write_all(&buf[..n]).and_then(|()| stdout.flush()) {
                        let _ = done_tx.send(Err(err).context("write cmx pty output"));
                        return;
                    }
                }
                Err(err) => {
                    let _ = done_tx.send(Err(err).context("read cmx pty output"));
                    return;
                }
            }
        }
    });

    loop {
        match done_rx.recv_timeout(Duration::from_secs(1)) {
            Ok(result) => {
                let _ = killer.kill();
                return result;
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                let _ = killer.kill();
                return Err(anyhow!("cmx pty recorder stopped without a result"));
            }
        }
    }
}

struct Args {
    socket: PathBuf,
    cols: u16,
    rows: u16,
}

impl Args {
    fn parse(args: impl IntoIterator<Item = String>) -> Result<Self> {
        let mut socket = None;
        let mut cols = 80;
        let mut rows = 24;
        let mut iter = args.into_iter();
        while let Some(arg) = iter.next() {
            match arg.as_str() {
                "--socket" => socket = iter.next().map(PathBuf::from),
                "--cols" => {
                    cols = iter
                        .next()
                        .ok_or_else(|| anyhow!("--cols requires a value"))?
                        .parse::<u16>()?;
                }
                "--rows" => {
                    rows = iter
                        .next()
                        .ok_or_else(|| anyhow!("--rows requires a value"))?
                        .parse::<u16>()?;
                }
                "-h" | "--help" => {
                    println!("usage: cmx-pty-recorder --socket PATH [--cols N] [--rows N]");
                    std::process::exit(0);
                }
                _ => bail!("unknown argument: {arg}"),
            }
        }

        Ok(Self {
            socket: socket.ok_or_else(|| anyhow!("--socket is required"))?,
            cols,
            rows,
        })
    }
}
