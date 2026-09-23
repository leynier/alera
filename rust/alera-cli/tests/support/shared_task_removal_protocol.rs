use super::*;
use std::path::{Path, PathBuf};

pub(super) fn register(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    token: &str,
    root: &Path,
) -> PathBuf {
    send(
        writer,
        json!({"id":0,"type":"hello","payload":{"protocolVersion":PROTOCOL_VERSION,"token":token,"sharedCheckoutWorkspacesV1":true}}),
    );
    assert_eq!(read_response(reader, 0)["ok"], true);
    let folder = root.join("shared-project");
    std::fs::create_dir(&folder).unwrap();
    std::fs::write(folder.join("retained.txt"), "shared files stay\n").unwrap();
    send(
        writer,
        json!({"id":9100,"type":"project.register","payload":{"path":folder,"name":"Shared removal fixture"}}),
    );
    let project = read_response(reader, 9100);
    assert_eq!(project["ok"], true, "{project}");
    send(
        writer,
        json!({"id":9101,"type":"workspace.createShared","payload":{"projectId":project["payload"]["project"]["id"],"id":"w1","name":"Task to remove"}}),
    );
    let task = read_response(reader, 9101);
    assert_eq!(task["ok"], true, "{task}");
    assert_eq!(task["payload"]["workspace"]["id"], "w1");
    folder
}

pub(super) fn remove(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    request_id: i64,
) -> Value {
    send(
        writer,
        json!({"id":9102,"type":"workspace.bufferGuard.acquire","payload":{"id":"w1","operation":"removeShared"}}),
    );
    let guard = read_response(reader, 9102);
    assert_eq!(guard["ok"], true, "{guard}");
    assert_eq!(guard["payload"]["ready"], true, "{guard}");
    send(
        writer,
        json!({"id":request_id,"type":"workspace.removeShared","payload":{"id":"w1","closeSessions":true,"deleteBranch":false,"bufferGuardId":guard["payload"]["guardId"]}}),
    );
    read_response(reader, request_id)
}
