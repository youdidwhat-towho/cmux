use std::time::Duration;

use comeup_daemon::{ComeupServer, ServerOptions};
use comeup_protocol::{ClientMsg, Command, Delta, ServerMsg, Viewport, VisibleTerminal};
use tokio::time::timeout;

const SENTINEL: &str = "COMEUP_SYNC_OK_9D3A";

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn two_local_clients_receive_workspace_delta_and_terminal_output() {
    let dir = tempfile::tempdir().expect("tempdir");
    let server = ComeupServer::start(ServerOptions {
        shell: "/bin/cat".to_string(),
        cwd: Some(dir.path().to_path_buf()),
        initial_viewport: Viewport { cols: 80, rows: 24 },
    })
    .expect("start server");

    let mut first = server
        .connect(Viewport {
            cols: 100,
            rows: 30,
        })
        .await
        .expect("connect first");
    let mut second = server
        .connect(Viewport {
            cols: 120,
            rows: 40,
        })
        .await
        .expect("connect second");

    let initial_terminal_id = match recv(&mut first).await {
        ServerMsg::Welcome { snapshot, .. } => {
            let terminal = snapshot
                .terminals
                .iter()
                .find(|terminal| terminal.id == snapshot.focus.terminal_id)
                .expect("focused terminal");
            assert_eq!(
                terminal.size,
                Viewport {
                    cols: 100,
                    rows: 30
                }
            );
            snapshot.focus.terminal_id
        }
        other => panic!("expected first welcome, got {other:?}"),
    };
    assert!(matches!(recv(&mut second).await, ServerMsg::Welcome { .. }));

    second
        .send(ClientMsg::VisibleTerminals {
            terminals: vec![VisibleTerminal {
                client_id: second.client_id(),
                terminal_id: initial_terminal_id,
                cols: 70,
                rows: 20,
                visible: true,
            }],
        })
        .expect("send visible terminal");
    assert_eq!(
        recv_terminal_size_delta(&mut first, initial_terminal_id).await,
        Viewport { cols: 70, rows: 20 }
    );
    assert_eq!(
        recv_terminal_size_delta(&mut second, initial_terminal_id).await,
        Viewport { cols: 70, rows: 20 }
    );

    first
        .send(ClientMsg::Command {
            id: 1,
            command: Command::CreateWorkspace {
                title: "Build".to_string(),
            },
        })
        .expect("send create workspace");

    let first_delta = recv_workspace_delta(&mut first).await;
    let second_delta = recv_workspace_delta(&mut second).await;
    assert_eq!(first_delta, "Build");
    assert_eq!(second_delta, "Build");

    first
        .send(ClientMsg::TerminalInput {
            terminal_id: initial_terminal_id,
            input_seq: 1,
            data: format!("{SENTINEL}\n").into_bytes(),
        })
        .expect("send terminal input");

    assert_terminal_output_contains(&mut first, SENTINEL).await;
    assert_terminal_output_contains(&mut second, SENTINEL).await;

    server.shutdown();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn silent_disconnect_releases_visible_terminal_size() {
    let dir = tempfile::tempdir().expect("tempdir");
    let server = ComeupServer::start(ServerOptions {
        shell: "/bin/cat".to_string(),
        cwd: Some(dir.path().to_path_buf()),
        initial_viewport: Viewport { cols: 80, rows: 24 },
    })
    .expect("start server");

    let mut first = server
        .connect(Viewport {
            cols: 100,
            rows: 30,
        })
        .await
        .expect("connect first");
    let mut second = server
        .connect(Viewport { cols: 70, rows: 20 })
        .await
        .expect("connect second");

    let initial_terminal_id = match recv(&mut first).await {
        ServerMsg::Welcome { snapshot, .. } => snapshot.focus.terminal_id,
        other => panic!("expected first welcome, got {other:?}"),
    };
    assert!(matches!(recv(&mut second).await, ServerMsg::Welcome { .. }));
    assert_eq!(
        recv_terminal_size_delta(&mut first, initial_terminal_id).await,
        Viewport { cols: 70, rows: 20 }
    );

    drop(second);
    first
        .send(ClientMsg::Command {
            id: 1,
            command: Command::CreateWorkspace {
                title: "After Disconnect".to_string(),
            },
        })
        .expect("send create workspace");

    assert_eq!(
        recv_terminal_size_delta(&mut first, initial_terminal_id).await,
        Viewport {
            cols: 100,
            rows: 30
        }
    );

    server.shutdown();
}

async fn recv(client: &mut comeup_daemon::LocalClient) -> ServerMsg {
    timeout(Duration::from_secs(5), client.recv())
        .await
        .expect("receive timeout")
        .expect("server closed")
}

async fn recv_terminal_size_delta(
    client: &mut comeup_daemon::LocalClient,
    terminal_id: u64,
) -> Viewport {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    loop {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        let msg = timeout(remaining, client.recv())
            .await
            .expect("terminal size delta timeout")
            .expect("server closed");
        if let ServerMsg::Delta {
            delta: Delta::TerminalUpsert { terminal, .. },
        } = msg
            && terminal.id == terminal_id
        {
            return terminal.size;
        }
    }
}

async fn recv_workspace_delta(client: &mut comeup_daemon::LocalClient) -> String {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    loop {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        let msg = timeout(remaining, client.recv())
            .await
            .expect("workspace delta timeout")
            .expect("server closed");
        if let ServerMsg::Delta {
            delta: Delta::WorkspaceUpsert { workspace, .. },
        } = msg
            && workspace.title == "Build"
        {
            return workspace.title;
        }
    }
}

async fn assert_terminal_output_contains(client: &mut comeup_daemon::LocalClient, expected: &str) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    let mut collected = Vec::new();
    while tokio::time::Instant::now() < deadline {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        let msg = timeout(remaining, client.recv())
            .await
            .expect("terminal output timeout")
            .expect("server closed");
        if let ServerMsg::TerminalOutput { data, .. } = msg {
            collected.extend_from_slice(&data);
            if String::from_utf8_lossy(&collected).contains(expected) {
                return;
            }
        }
    }
    panic!(
        "expected terminal output to contain {expected}, got {}",
        String::from_utf8_lossy(&collected)
    );
}
