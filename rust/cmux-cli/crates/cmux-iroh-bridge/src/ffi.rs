use std::collections::VecDeque;
use std::ffi::{CStr, c_char, c_void};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use anyhow::{Context, Result, anyhow, bail};
use tokio::sync::mpsc;

use crate::{BridgeRelayMode, connect_encoded_ticket};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);
const SEND_TIMEOUT: Duration = Duration::from_secs(10);
const MAX_PRECONNECT_SENDS: usize = 256;

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CmxIrohClientEventKind {
    Connected = 1,
    Message = 2,
    Closed = 3,
    Error = 4,
}

pub type CmxIrohClientCallback = unsafe extern "C" fn(
    user_data: *mut c_void,
    kind: CmxIrohClientEventKind,
    data: *const u8,
    len: usize,
);

pub struct CmxIrohClientHandle {
    commands: mpsc::UnboundedSender<CmxIrohClientCommand>,
    thread: Option<JoinHandle<()>>,
}

enum CmxIrohClientCommand {
    Send(Vec<u8>),
    Disconnect,
}

struct CmxIrohClientOptions {
    ticket: String,
    relay_mode: BridgeRelayMode,
    pairing_secret: Option<String>,
    callback: CmxIrohClientCallback,
    user_data: usize,
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn cmux_iroh_client_connect(
    ticket: *const c_char,
    pairing_secret: *const c_char,
    relay_mode: u32,
    callback: Option<CmxIrohClientCallback>,
    user_data: *mut c_void,
) -> *mut CmxIrohClientHandle {
    let Some(callback) = callback else {
        return std::ptr::null_mut();
    };
    let ticket = match read_required_c_string(ticket) {
        Ok(value) => value,
        Err(_) => return std::ptr::null_mut(),
    };
    let pairing_secret = match read_optional_c_string(pairing_secret) {
        Ok(value) => value,
        Err(_) => return std::ptr::null_mut(),
    };
    let (tx, rx) = mpsc::unbounded_channel();
    let options = CmxIrohClientOptions {
        ticket,
        relay_mode: ffi_relay_mode(relay_mode),
        pairing_secret,
        callback,
        user_data: user_data as usize,
    };
    let thread = match thread::Builder::new()
        .name("cmux-iroh-client".into())
        .spawn(move || run_client_thread(options, rx))
    {
        Ok(thread) => thread,
        Err(_) => return std::ptr::null_mut(),
    };

    Box::into_raw(Box::new(CmxIrohClientHandle {
        commands: tx,
        thread: Some(thread),
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn cmux_iroh_client_send(
    handle: *mut CmxIrohClientHandle,
    data: *const u8,
    len: usize,
) -> bool {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return false;
    };
    if data.is_null() && len > 0 {
        return false;
    }
    let payload = if len == 0 {
        Vec::new()
    } else {
        unsafe { std::slice::from_raw_parts(data, len) }.to_vec()
    };
    handle
        .commands
        .send(CmxIrohClientCommand::Send(payload))
        .is_ok()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn cmux_iroh_client_disconnect(handle: *mut CmxIrohClientHandle) {
    if handle.is_null() {
        return;
    }
    let mut handle = unsafe { Box::from_raw(handle) };
    let _ = handle.commands.send(CmxIrohClientCommand::Disconnect);
    if let Some(thread) = handle.thread.take() {
        let _ = thread.join();
    }
}

fn ffi_relay_mode(value: u32) -> BridgeRelayMode {
    match value {
        1 => BridgeRelayMode::Disabled,
        _ => BridgeRelayMode::Default,
    }
}

fn run_client_thread(
    options: CmxIrohClientOptions,
    commands: mpsc::UnboundedReceiver<CmxIrohClientCommand>,
) {
    let callback = options.callback;
    let user_data = options.user_data;
    let runtime = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime,
        Err(error) => {
            emit_error(callback, user_data, anyhow!("start iroh runtime: {error}"));
            return;
        }
    };

    if let Err(error) = runtime.block_on(run_client_async(options, commands)) {
        emit_error(callback, user_data, error);
    }
}

async fn run_client_async(
    options: CmxIrohClientOptions,
    mut commands: mpsc::UnboundedReceiver<CmxIrohClientCommand>,
) -> Result<()> {
    let callback = options.callback;
    let user_data = options.user_data;
    let mut pending_sends = VecDeque::new();
    let connect = tokio::time::timeout(
        CONNECT_TIMEOUT,
        connect_encoded_ticket(&options.ticket, options.relay_mode, options.pairing_secret),
    );
    tokio::pin!(connect);

    let mut client = loop {
        tokio::select! {
            connected = &mut connect => {
                break connected.context("iroh connect timed out")??;
            }
            command = commands.recv() => {
                match command {
                    Some(CmxIrohClientCommand::Send(payload)) => {
                        if pending_sends.len() >= MAX_PRECONNECT_SENDS {
                            bail!("too many cmx frames queued before iroh connected");
                        }
                        pending_sends.push_back(payload);
                    }
                    Some(CmxIrohClientCommand::Disconnect) | None => {
                        return Ok(());
                    }
                }
            }
        }
    };
    emit_event(callback, user_data, CmxIrohClientEventKind::Connected, &[]);
    while let Some(payload) = pending_sends.pop_front() {
        write_client_payload(&mut client, &payload).await?;
    }

    loop {
        tokio::select! {
            command = commands.recv() => {
                match command {
                    Some(CmxIrohClientCommand::Send(payload)) => {
                        write_client_payload(&mut client, &payload).await?;
                    }
                    Some(CmxIrohClientCommand::Disconnect) | None => {
                        break;
                    }
                }
            }
            payload = client.read_payload() => {
                match payload.context("read cmx frame over iroh")? {
                    Some(payload) => emit_event(callback, user_data, CmxIrohClientEventKind::Message, &payload),
                    None => break,
                }
            }
        }
    }

    client.endpoint.close().await;
    emit_event(callback, user_data, CmxIrohClientEventKind::Closed, &[]);
    Ok(())
}

async fn write_client_payload(
    client: &mut crate::BridgeClientConnection,
    payload: &[u8],
) -> Result<()> {
    tokio::time::timeout(SEND_TIMEOUT, client.write_payload(payload))
        .await
        .context("send cmx frame over iroh timed out")?
        .context("send cmx frame over iroh")
}

fn emit_error(callback: CmxIrohClientCallback, user_data: usize, error: anyhow::Error) {
    emit_event(
        callback,
        user_data,
        CmxIrohClientEventKind::Error,
        error.to_string().as_bytes(),
    );
}

fn emit_event(
    callback: CmxIrohClientCallback,
    user_data: usize,
    kind: CmxIrohClientEventKind,
    data: &[u8],
) {
    unsafe {
        callback(user_data as *mut c_void, kind, data.as_ptr(), data.len());
    }
}

fn read_required_c_string(value: *const c_char) -> Result<String> {
    if value.is_null() {
        bail!("missing C string");
    }
    let string = unsafe { CStr::from_ptr(value) }
        .to_str()
        .context("C string is not UTF-8")?;
    Ok(string.to_owned())
}

fn read_optional_c_string(value: *const c_char) -> Result<Option<String>> {
    if value.is_null() {
        return Ok(None);
    }
    let string = unsafe { CStr::from_ptr(value) }
        .to_str()
        .context("C string is not UTF-8")?;
    if string.trim().is_empty() {
        Ok(None)
    } else {
        Ok(Some(string.to_owned()))
    }
}
