use super::*;
use tokio::io::AsyncWriteExt;
use tokio::net::TcpListener;
use tokio::sync::mpsc;

#[tokio::test]
async fn saturated_tcp_admission_waits_without_disconnect_or_reordering() {
    let (inbox, mut commands) = crate::terminal_host::ServerInbox::channel();
    let mut admitted = 0;
    while inbox
        .send(ServerCommand::ClientDisconnected { id: admitted })
        .is_ok()
    {
        admitted += 1;
    }
    assert!(admitted > 0);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let mut client = TcpStream::connect(listener.local_addr().unwrap())
        .await
        .unwrap();
    let (server, _) = listener.accept().await.unwrap();
    let (_controls, control_rx) = mpsc::unbounded_channel();
    let (_terminal, terminal_rx) = mpsc::channel(16);
    let connection = tokio::spawn(connection_loop(
        server,
        900,
        inbox.clone(),
        control_rx,
        terminal_rx,
    ));
    client.write_all(b"first\nsecond\n").await.unwrap();
    tokio::time::sleep(std::time::Duration::from_millis(30)).await;
    assert!(
        !connection.is_finished(),
        "capacity pressure must not close the connection"
    );
    for _ in 0..admitted {
        commands.try_recv().unwrap();
    }
    for expected in ["first", "second"] {
        let command =
            tokio::time::timeout(std::time::Duration::from_secs(2), inbox.recv(&mut commands))
                .await
                .unwrap()
                .unwrap();
        assert!(matches!(command, ServerCommand::ClientLine { id: 900, line } if line == expected));
    }
    drop(client);
    let command =
        tokio::time::timeout(std::time::Duration::from_secs(2), inbox.recv(&mut commands))
            .await
            .unwrap()
            .unwrap();
    assert!(matches!(
        command,
        ServerCommand::ClientDisconnected { id: 900 }
    ));
    connection.await.unwrap();
}
