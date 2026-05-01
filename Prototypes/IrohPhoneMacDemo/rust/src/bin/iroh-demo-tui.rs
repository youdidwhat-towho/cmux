use std::{io, time::Duration};

use anyhow::Result;
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use iroh_phone_mac_demo_ffi::{MacEvent, start_mac_server};
use ratatui::{
    Frame, Terminal,
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
};

#[tokio::main]
async fn main() -> Result<()> {
    let terminal = TerminalGuard::enter()?;
    let result = run(terminal).await;
    TerminalGuard::leave()?;
    result
}

async fn run(mut terminal: Terminal<CrosstermBackend<io::Stdout>>) -> Result<()> {
    let mut server = start_mac_server().await?;
    let ticket = server.ticket.clone();
    let mut logs = vec!["server online, waiting for iPhone".to_string()];

    loop {
        while let Ok(event) = server.events.try_recv() {
            logs.push(render_event(event));
            if logs.len() > 12 {
                logs.remove(0);
            }
        }

        terminal.draw(|frame| draw(frame, &ticket, &logs))?;

        if event::poll(Duration::from_millis(80))? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press && matches!(key.code, KeyCode::Char('q')) {
                    break;
                }
            }
        }
    }

    server.shutdown().await?;
    Ok(())
}

fn draw(frame: &mut Frame<'_>, ticket: &str, logs: &[String]) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(8),
            Constraint::Length(10),
            Constraint::Length(3),
        ])
        .split(frame.area());

    let title = Paragraph::new(Line::from(vec![
        Span::styled(
            "Iroh iPhone <-> Mac demo",
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw("  q quits"),
    ]))
    .block(Block::default().borders(Borders::ALL));
    frame.render_widget(title, chunks[0]);

    let ticket_panel = Paragraph::new(ticket.to_string())
        .wrap(Wrap { trim: false })
        .block(Block::default().borders(Borders::ALL).title("Ticket"));
    frame.render_widget(ticket_panel, chunks[1]);

    let items = logs
        .iter()
        .rev()
        .map(|entry| ListItem::new(entry.as_str()))
        .collect::<Vec<_>>();
    let log_panel = List::new(items).block(Block::default().borders(Borders::ALL).title("Events"));
    frame.render_widget(log_panel, chunks[2]);

    let footer = Paragraph::new("Paste the ticket into the iPhone app, then tap Ping Mac.")
        .block(Block::default().borders(Borders::ALL));
    frame.render_widget(footer, chunks[3]);
}

fn render_event(event: MacEvent) -> String {
    match event {
        MacEvent::Connected { remote_id } => format!("connected: {remote_id}"),
        MacEvent::Request { remote_id, message } => {
            format!("request from {remote_id}: {message}")
        }
        MacEvent::Response { remote_id, bytes } => {
            format!("response to {remote_id}: {bytes} bytes")
        }
        MacEvent::Error { message } => format!("error: {message}"),
    }
}

struct TerminalGuard;

impl TerminalGuard {
    fn enter() -> Result<Terminal<CrosstermBackend<io::Stdout>>> {
        enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, EnterAlternateScreen)?;
        let backend = CrosstermBackend::new(stdout);
        Terminal::new(backend).map_err(Into::into)
    }

    fn leave() -> Result<()> {
        disable_raw_mode()?;
        execute!(io::stdout(), LeaveAlternateScreen)?;
        Ok(())
    }
}
