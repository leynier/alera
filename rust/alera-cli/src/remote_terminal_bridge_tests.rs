use super::*;
use tokio::io::{duplex, AsyncBufReadExt, BufReader};

#[tokio::test]
async fn replay_uses_the_recorded_geometry_before_restoring_the_viewport() {
    let fixture: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/terminal_snapshot_geometry.json"
    ))
    .unwrap();
    let payload = json!({"snapshotCols":fixture["cols"],"snapshotRows":fixture["rows"],
        "snapshotBase64":crate::terminal_host::protocol::encode_bytes(fixture["snapshot"].as_str().unwrap().as_bytes())});
    let mut output = Vec::new();
    replay_snapshot(
        &mut output,
        &payload,
        (
            fixture["viewportCols"].as_u64().unwrap() as u16,
            fixture["viewportRows"].as_u64().unwrap() as u16,
        ),
    )
    .await
    .unwrap();
    assert_eq!(output, fixture["replay"].as_str().unwrap().as_bytes());
}

async fn exercise(frames: Vec<Value>) -> (Result<i32>, Vec<u8>) {
    let (owner, client) = duplex(8192);
    let (reader, writer) = tokio::io::split(client);
    let (input, _input_writer) = duplex(1024);
    let (output, mut output_reader) = duplex(8192);
    let server = async move {
        let (reader, mut writer) = tokio::io::split(owner);
        let mut lines = BufReader::new(reader).lines();
        let request: Value =
            serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        assert_eq!(request["id"], 17);
        assert_eq!(request["type"], "createOrAttach");
        assert_eq!(request["payload"]["sessionId"], "owned");
        for frame in frames {
            let mut bytes = serde_json::to_vec(&frame).unwrap();
            bytes.push(b'\n');
            writer.write_all(&bytes).await.unwrap();
        }
    };
    let client = bridge(
        BufReader::new(reader).lines(),
        writer,
        input,
        output,
        json!({"sessionId":"owned"}),
        17,
        || None,
    );
    let (result, ()) = tokio::join!(client, server);
    let mut bytes = Vec::new();
    output_reader.read_to_end(&mut bytes).await.unwrap();
    (result, bytes)
}

fn attached(session: &str) -> Value {
    json!({"id":17,"ok":true,"payload":{"sessionId":session,"snapshotBase64":"","snapshotCols":80,"snapshotRows":24}})
}

#[tokio::test]
async fn forwards_control_bytes_and_dimensions_with_owned_identity() {
    let (owner, client) = duplex(8192);
    let (reader, writer) = tokio::io::split(client);
    let (input, mut input_writer) = duplex(1024);
    input_writer.write_all(&[3, 0, 255]).await.unwrap();
    let server = async move {
        let (reader, mut writer) = tokio::io::split(owner);
        let mut lines = BufReader::new(reader).lines();
        lines.next_line().await.unwrap().unwrap();
        writer
            .write_all(format!("{}\n", attached("owned")).as_bytes())
            .await
            .unwrap();
        let mut seen = HashSet::new();
        while seen.len() < 2 {
            let request: Value =
                serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
            assert_eq!(request["payload"]["sessionId"], "owned");
            let kind = request["type"].as_str().unwrap();
            match kind {
                "write" => assert_eq!(
                    crate::terminal_host::protocol::decode_bytes(
                        request["payload"].get("dataBase64")
                    )
                    .unwrap(),
                    [3, 0, 255]
                ),
                "resize" => {
                    assert_eq!(request["payload"]["cols"], 120);
                    assert_eq!(request["payload"]["rows"], 40);
                }
                other => panic!("Unexpected request {other}"),
            }
            assert!(seen.insert(kind.to_string()));
            writer
                .write_all(
                    format!("{}\n", json!({"id":request["id"],"ok":true,"payload":{}})).as_bytes(),
                )
                .await
                .unwrap();
        }
        writer
            .write_all(
                format!(
                    "{}\n",
                    json!({"event":"exit","payload":{"sessionId":"owned","exitCode":0}})
                )
                .as_bytes(),
            )
            .await
            .unwrap();
    };
    let client = bridge(
        BufReader::new(reader).lines(),
        writer,
        input,
        tokio::io::sink(),
        json!({"sessionId":"owned","cols":80,"rows":24}),
        17,
        || Some((120, 40)),
    );
    let (result, ()) = tokio::time::timeout(std::time::Duration::from_secs(3), async {
        tokio::join!(client, server)
    })
    .await
    .unwrap();
    assert_eq!(result.unwrap(), 0);
    drop(input_writer);
}

#[tokio::test]
async fn forwards_only_owned_output_and_exit() {
    let (result, output) = exercise(vec![
        attached("owned"),
        json!({"event":"output","payload":{"sessionId":"other","dataBase64":"YmFk"}}),
        json!({"event":"exit","payload":{"sessionId":"other","exitCode":99}}),
        json!({"event":"output","payload":{"sessionId":"owned","dataBase64":"b2s="}}),
        json!({"event":"exit","payload":{"sessionId":"owned","exitCode":7}}),
    ])
    .await;
    assert_eq!(result.unwrap(), 7);
    assert_eq!(output, b"ok");
}

#[tokio::test]
async fn disconnect_does_not_report_remote_exit() {
    let (result, _) = exercise(vec![attached("owned")]).await;
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("closure is unverified"));
}

#[tokio::test]
async fn mismatched_attachment_is_rejected() {
    let (result, _) = exercise(vec![attached("other")]).await;
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("another terminal identity"));
}

#[tokio::test]
async fn invalid_exit_status_is_not_success() {
    let (result, _) = exercise(vec![
        attached("owned"),
        json!({"event":"exit","payload":{"sessionId":"owned","exitCode":null}}),
    ])
    .await;
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Invalid remote exit status"));
}

#[tokio::test]
async fn resumes_output_after_backpressure_with_delta_or_replacement() {
    for delta in [true, false] {
        let (owner, client) = duplex(8192);
        let (reader, writer) = tokio::io::split(client);
        let (input, _keep_input_open) = duplex(1024);
        let (output, mut output_reader) = duplex(8192);
        let server = async move {
            let (reader, mut writer) = tokio::io::split(owner);
            let mut lines = BufReader::new(reader).lines();
            lines.next_line().await.unwrap().unwrap();
            for frame in [
                attached("owned"),
                json!({"event":"outputResyncRequired","payload":{"sessionId":"owned"}}),
            ] {
                writer
                    .write_all(format!("{frame}\n").as_bytes())
                    .await
                    .unwrap();
            }
            let request: Value =
                serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
            assert_eq!(request["type"], "setOutputPaused");
            assert_eq!(
                request["payload"],
                json!({"sessionId":"owned","paused":false})
            );
            let payload = if delta {
                json!({"delta":true,"resumed":true})
            } else {
                json!({"delta":false,"sessionId":"owned","snapshotBase64":"c25hcA==","resetInteractionModes":true})
            };
            for frame in [
                json!({"id":request["id"],"ok":true,"payload":payload}),
                json!({"event":"output","payload":{"sessionId":"owned","dataBase64":"bGl2ZQ=="}}),
                json!({"event":"exit","payload":{"sessionId":"owned","exitCode":0}}),
            ] {
                writer
                    .write_all(format!("{frame}\n").as_bytes())
                    .await
                    .unwrap();
            }
        };
        let client = bridge(
            BufReader::new(reader).lines(),
            writer,
            input,
            output,
            json!({"sessionId":"owned"}),
            17,
            || None,
        );
        let (result, ()) = tokio::time::timeout(std::time::Duration::from_secs(3), async {
            tokio::join!(client, server)
        })
        .await
        .unwrap();
        assert_eq!(result.unwrap(), 0);
        let mut bytes = Vec::new();
        output_reader.read_to_end(&mut bytes).await.unwrap();
        assert_eq!(
            bytes,
            if delta {
                b"live".to_vec()
            } else {
                b"\x1bcsnaplive".to_vec()
            }
        );
    }
}

#[tokio::test]
async fn reattachment_resizes_the_surviving_owner_before_any_viewport_change() {
    let (owner, client) = duplex(8192);
    let (reader, writer) = tokio::io::split(client);
    let (input, _keep_input_open) = duplex(1024);
    let server = async move {
        let (reader, mut writer) = tokio::io::split(owner);
        let mut lines = BufReader::new(reader).lines();
        let request: Value =
            serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        assert_eq!(request["payload"]["cols"], 120);
        let mut attachment = attached("owned");
        attachment["payload"]["snapshotCols"] = json!(80);
        attachment["payload"]["snapshotRows"] = json!(24);
        writer
            .write_all(format!("{attachment}\n").as_bytes())
            .await
            .unwrap();
        let resize: Value =
            serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        assert_eq!(resize["type"], "resize");
        assert_eq!(
            resize["payload"],
            json!({"sessionId":"owned","cols":120,"rows":40})
        );
        writer
            .write_all(
                format!(
                    "{}\n",
                    json!({"event":"exit","payload":{"sessionId":"owned","exitCode":0}})
                )
                .as_bytes(),
            )
            .await
            .unwrap();
    };
    let client = bridge(
        BufReader::new(reader).lines(),
        writer,
        input,
        tokio::io::sink(),
        json!({"sessionId":"owned","cols":120,"rows":40}),
        17,
        || None,
    );
    let (result, ()) = tokio::time::timeout(std::time::Duration::from_secs(3), async {
        tokio::join!(client, server)
    })
    .await
    .unwrap();
    assert_eq!(result.unwrap(), 0);
}
