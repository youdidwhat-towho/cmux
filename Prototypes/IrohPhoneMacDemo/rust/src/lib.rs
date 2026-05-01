use std::{
    ffi::{CStr, CString},
    os::raw::c_char,
    time::{Instant, SystemTime, UNIX_EPOCH},
};

use anyhow::{Context, Result};
use iroh::{
    Endpoint,
    endpoint::{Connection, RecvStream, SendStream, presets},
    protocol::{AcceptError, ProtocolHandler, Router},
};
use iroh_tickets::{Ticket, endpoint::EndpointTicket};
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;

pub const ALPN: &[u8] = b"cmux/iroh-phone-mac-demo/0";
const MAX_MESSAGE_BYTES: usize = 64 * 1024;

#[derive(Debug, Clone)]
pub enum MacEvent {
    Connected { remote_id: String },
    Request { remote_id: String, message: String },
    Response { remote_id: String, bytes: usize },
    Error { message: String },
}

pub struct MacServer {
    pub ticket: String,
    pub events: mpsc::UnboundedReceiver<MacEvent>,
    router: Router,
}

impl MacServer {
    pub async fn shutdown(self) -> Result<()> {
        self.router.shutdown().await?;
        Ok(())
    }
}

#[derive(Debug, Clone)]
struct DemoProtocol {
    events: mpsc::UnboundedSender<MacEvent>,
}

impl ProtocolHandler for DemoProtocol {
    async fn accept(&self, connection: Connection) -> Result<(), AcceptError> {
        let events = self.events.clone();
        handle_connection(connection, events).await
    }
}

pub async fn start_mac_server() -> Result<MacServer> {
    let (events_tx, events_rx) = mpsc::unbounded_channel();
    let endpoint = Endpoint::bind(presets::N0).await?;
    endpoint.online().await;

    let ticket = EndpointTicket::new(endpoint.addr()).to_string();
    let router = Router::builder(endpoint)
        .accept(ALPN, DemoProtocol { events: events_tx })
        .spawn();

    Ok(MacServer {
        ticket,
        events: events_rx,
        router,
    })
}

async fn handle_connection(
    connection: Connection,
    events: mpsc::UnboundedSender<MacEvent>,
) -> Result<(), AcceptError> {
    let remote_id = connection.remote_id().to_string();
    send_event(
        &events,
        MacEvent::Connected {
            remote_id: remote_id.clone(),
        },
    );

    let (mut send, mut recv): (SendStream, RecvStream) = connection.accept_bi().await?;
    let request_bytes = recv
        .read_to_end(MAX_MESSAGE_BYTES)
        .await
        .map_err(AcceptError::from_err)?;
    let message = String::from_utf8_lossy(&request_bytes).to_string();
    send_event(
        &events,
        MacEvent::Request {
            remote_id: remote_id.clone(),
            message: message.clone(),
        },
    );

    let response = WireResponse {
        reply: format!("MacBook received: {message}"),
        mac_received: message,
        remote_id: remote_id.clone(),
        received_at_unix_ms: unix_ms(),
    };
    let payload = serde_json::to_vec(&response).map_err(AcceptError::from_err)?;
    send.write_all(&payload)
        .await
        .map_err(AcceptError::from_err)?;
    send.finish().map_err(AcceptError::from_err)?;
    send_event(
        &events,
        MacEvent::Response {
            remote_id,
            bytes: payload.len(),
        },
    );

    connection.closed().await;
    Ok(())
}

fn send_event(events: &mpsc::UnboundedSender<MacEvent>, event: MacEvent) {
    let _ = events.send(event);
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WireResponse {
    pub reply: String,
    pub mac_received: String,
    pub remote_id: String,
    pub received_at_unix_ms: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct PingSummary {
    pub rtt_ms: u64,
    pub response: WireResponse,
}

pub async fn ping_ticket(ticket: &str, message: &str) -> Result<PingSummary> {
    let ticket = <EndpointTicket as Ticket>::deserialize(ticket.trim())
        .map_err(|error| anyhow::anyhow!("failed to parse iroh ticket: {error}"))?;
    let endpoint = Endpoint::bind(presets::N0).await?;
    let start = Instant::now();
    let connection = endpoint
        .connect(ticket.endpoint_addr().clone(), ALPN)
        .await?;
    let (mut send, mut recv): (SendStream, RecvStream) = connection.open_bi().await?;

    send.write_all(message.as_bytes()).await?;
    send.finish()?;

    let response_bytes = recv.read_to_end(MAX_MESSAGE_BYTES).await?;
    let response: WireResponse =
        serde_json::from_slice(&response_bytes).context("mac returned invalid demo response")?;

    connection.close(0u32.into(), b"done");
    endpoint.close().await;

    Ok(PingSummary {
        rtt_ms: start.elapsed().as_millis().try_into().unwrap_or(u64::MAX),
        response,
    })
}

#[derive(Serialize)]
struct FfiPingOk<'a> {
    ok: bool,
    rtt_ms: u64,
    reply: &'a str,
    mac_received: &'a str,
    remote_id: &'a str,
    received_at_unix_ms: u64,
}

#[derive(Serialize)]
struct FfiPingError<'a> {
    ok: bool,
    error: &'a str,
}

#[unsafe(no_mangle)]
pub extern "C" fn iroh_demo_ping(ticket: *const c_char, message: *const c_char) -> *mut c_char {
    let result = ffi_ping(ticket, message);
    let json = match result {
        Ok(summary) => serde_json::to_string(&FfiPingOk {
            ok: true,
            rtt_ms: summary.rtt_ms,
            reply: &summary.response.reply,
            mac_received: &summary.response.mac_received,
            remote_id: &summary.response.remote_id,
            received_at_unix_ms: summary.response.received_at_unix_ms,
        }),
        Err(error) => serde_json::to_string(&FfiPingError {
            ok: false,
            error: &error.to_string(),
        }),
    }
    .unwrap_or_else(|error| {
        format!(r#"{{"ok":false,"error":"failed to encode FFI response: {error}"}}"#)
    });

    CString::new(json).unwrap_or_else(empty_c_string).into_raw()
}

#[unsafe(no_mangle)]
pub extern "C" fn iroh_demo_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }

    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

fn ffi_ping(ticket: *const c_char, message: *const c_char) -> Result<PingSummary> {
    let ticket = c_string(ticket).context("missing ticket")?;
    let message = c_string(message).context("missing message")?;
    let runtime = tokio::runtime::Runtime::new()?;
    runtime.block_on(ping_ticket(&ticket, &message))
}

fn c_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }

    let value = unsafe { CStr::from_ptr(ptr) };
    Some(value.to_string_lossy().into_owned())
}

fn empty_c_string(error: std::ffi::NulError) -> CString {
    let without_nuls = error
        .into_vec()
        .into_iter()
        .filter(|byte| *byte != 0)
        .collect::<Vec<_>>();
    CString::new(without_nuls).unwrap_or_default()
}

fn unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis().try_into().unwrap_or(u64::MAX))
        .unwrap_or_default()
}
