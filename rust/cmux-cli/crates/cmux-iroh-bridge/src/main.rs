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

use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use clap::{Parser, ValueEnum};
use cmux_iroh_bridge::{
    BridgeNodeInfo, BridgeOptions, BridgePairingOptions, BridgeRelayMode, serve,
};

#[derive(Parser, Debug)]
#[command(name = "cmux-iroh-bridge", about = "Expose a cmx socket over iroh")]
struct Cli {
    #[arg(long, env = "CMX_SOCKET_PATH")]
    socket: PathBuf,
    #[arg(long, value_enum, default_value_t = RelayArg::Default)]
    relay: RelayArg,
    #[arg(long, env = "CMUX_PAIRING_ID")]
    pairing_id: Option<String>,
    #[arg(long, env = "CMUX_PAIRING_SECRET")]
    pairing_secret: Option<String>,
    #[arg(long, env = "CMUX_RIVET_ENDPOINT")]
    rivet_endpoint: Option<String>,
    #[arg(long, env = "CMUX_STACK_PROJECT_ID")]
    stack_project_id: Option<String>,
    #[arg(long, env = "CMUX_PAIRING_EXPIRES_AT_UNIX")]
    expires_at_unix: Option<u64>,
    #[arg(long, env = "CMUX_NODE_ID")]
    node_id: Option<String>,
    #[arg(long, env = "CMUX_NODE_NAME")]
    node_name: Option<String>,
    #[arg(long, env = "CMUX_NODE_SUBTITLE")]
    node_subtitle: Option<String>,
    #[arg(long, env = "CMUX_NODE_KIND")]
    node_kind: Option<String>,
    #[arg(long)]
    allow_insecure_direct: bool,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum RelayArg {
    Default,
    Disabled,
}

impl From<RelayArg> for BridgeRelayMode {
    fn from(value: RelayArg) -> Self {
        match value {
            RelayArg::Default => Self::Default,
            RelayArg::Disabled => Self::Disabled,
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    let cli = Cli::parse();
    let pairing = pairing_options(&cli)?;
    let node = node_info(&cli)?;
    serve(BridgeOptions {
        cmx_socket_path: cli.socket,
        relay_mode: cli.relay.into(),
        pairing,
        node,
    })
    .await
}

fn node_info(cli: &Cli) -> Result<Option<BridgeNodeInfo>> {
    let has_node = cli.node_id.is_some()
        || cli.node_name.is_some()
        || cli.node_subtitle.is_some()
        || cli.node_kind.is_some();
    if !has_node {
        return Ok(None);
    }

    let node = BridgeNodeInfo {
        id: cli.node_id.clone(),
        name: cli
            .node_name
            .clone()
            .context("missing --node-name / CMUX_NODE_NAME")?,
        subtitle: cli.node_subtitle.clone(),
        kind: cli.node_kind.clone(),
    };
    node.validate()?;
    Ok(Some(node))
}

fn pairing_options(cli: &Cli) -> Result<Option<BridgePairingOptions>> {
    let has_pairing = cli.pairing_id.is_some()
        || cli.pairing_secret.is_some()
        || cli.rivet_endpoint.is_some()
        || cli.stack_project_id.is_some()
        || cli.expires_at_unix.is_some();
    if !has_pairing {
        if cli.allow_insecure_direct {
            return Ok(None);
        }
        bail!(
            "pairing auth is required; provide CMUX_PAIRING_* and CMUX_RIVET_ENDPOINT/CMUX_STACK_PROJECT_ID or pass --allow-insecure-direct for local development"
        );
    }

    Ok(Some(BridgePairingOptions {
        pairing_id: cli
            .pairing_id
            .clone()
            .context("missing --pairing-id / CMUX_PAIRING_ID")?,
        secret: cli
            .pairing_secret
            .clone()
            .context("missing --pairing-secret / CMUX_PAIRING_SECRET")?,
        rivet_endpoint: cli
            .rivet_endpoint
            .clone()
            .context("missing --rivet-endpoint / CMUX_RIVET_ENDPOINT")?,
        stack_project_id: cli
            .stack_project_id
            .clone()
            .context("missing --stack-project-id / CMUX_STACK_PROJECT_ID")?,
        expires_at_unix: cli
            .expires_at_unix
            .context("missing --expires-at-unix / CMUX_PAIRING_EXPIRES_AT_UNIX")?,
    }))
}
