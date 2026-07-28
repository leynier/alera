use super::*;

async fn next_chunk(
    stream: &mut std::pin::Pin<Box<impl futures_util::Stream<Item = Result<Bytes, Infallible>>>>,
) -> Bytes {
    tokio::time::timeout(Duration::from_secs(1), stream.next())
        .await
        .expect("video stream timed out")
        .expect("video stream closed")
        .expect("video chunk was infallible")
}

#[tokio::test]
async fn android_new_subscriber_gets_complete_gop_then_live_frames_once() {
    let source = AndroidVideoSource::new(8);
    source
        .publish(AndroidVideoFrameKind::Config, Bytes::from_static(b"config"))
        .await;
    source
        .publish(AndroidVideoFrameKind::Key, Bytes::from_static(b"key"))
        .await;
    source
        .publish(AndroidVideoFrameKind::Delta, Bytes::from_static(b"p1"))
        .await;

    let mut video = Box::pin(android_stream(source.clone()).await);
    source
        .publish(AndroidVideoFrameKind::Delta, Bytes::from_static(b"p2"))
        .await;

    let mut chunks = Vec::new();
    for _ in 0..4 {
        chunks.push(next_chunk(&mut video).await);
    }
    assert_eq!(
        chunks,
        [
            Bytes::from_static(b"config"),
            Bytes::from_static(b"key"),
            Bytes::from_static(b"p1"),
            Bytes::from_static(b"p2"),
        ]
    );
}

#[tokio::test]
async fn android_lag_recovers_missing_gop_suffix_without_duplicates() {
    let source = AndroidVideoSource::new(2);
    source
        .publish(AndroidVideoFrameKind::Config, Bytes::from_static(b"config"))
        .await;
    source
        .publish(AndroidVideoFrameKind::Key, Bytes::from_static(b"key"))
        .await;
    let mut video = Box::pin(android_stream(source.clone()).await);
    assert_eq!(next_chunk(&mut video).await, Bytes::from_static(b"config"));
    assert_eq!(next_chunk(&mut video).await, Bytes::from_static(b"key"));

    for frame in [b"p1", b"p2", b"p3", b"p4"] {
        source
            .publish(AndroidVideoFrameKind::Delta, Bytes::from_static(frame))
            .await;
    }
    let mut recovered = Vec::new();
    for _ in 0..4 {
        recovered.push(next_chunk(&mut video).await);
    }
    assert_eq!(
        recovered,
        [
            Bytes::from_static(b"p1"),
            Bytes::from_static(b"p2"),
            Bytes::from_static(b"p3"),
            Bytes::from_static(b"p4"),
        ]
    );

    source
        .publish(AndroidVideoFrameKind::Delta, Bytes::from_static(b"p5"))
        .await;
    assert_eq!(next_chunk(&mut video).await, Bytes::from_static(b"p5"));
}

#[tokio::test]
async fn android_lag_restarts_with_config_when_a_newer_keyframe_exists() {
    let source = AndroidVideoSource::new(2);
    source
        .publish(AndroidVideoFrameKind::Config, Bytes::from_static(b"config"))
        .await;
    source
        .publish(AndroidVideoFrameKind::Key, Bytes::from_static(b"key1"))
        .await;
    let mut video = Box::pin(android_stream(source.clone()).await);
    assert_eq!(next_chunk(&mut video).await, Bytes::from_static(b"config"));
    assert_eq!(next_chunk(&mut video).await, Bytes::from_static(b"key1"));

    for (kind, frame) in [
        (AndroidVideoFrameKind::Delta, b"p1".as_slice()),
        (AndroidVideoFrameKind::Delta, b"p2".as_slice()),
        (AndroidVideoFrameKind::Key, b"key2".as_slice()),
        (AndroidVideoFrameKind::Delta, b"p3".as_slice()),
    ] {
        source.publish(kind, Bytes::copy_from_slice(frame)).await;
    }

    assert_eq!(next_chunk(&mut video).await, Bytes::from_static(b"config"));
    assert_eq!(next_chunk(&mut video).await, Bytes::from_static(b"key2"));
    assert_eq!(next_chunk(&mut video).await, Bytes::from_static(b"p3"));
}

#[tokio::test]
async fn android_stream_closes_when_its_producer_finishes() {
    let source = AndroidVideoSource::new(2);
    source
        .publish(AndroidVideoFrameKind::Config, Bytes::from_static(b"config"))
        .await;
    let mut video = Box::pin(android_stream(source.clone()).await);
    assert_eq!(next_chunk(&mut video).await, Bytes::from_static(b"config"));

    source.close();

    let ended = tokio::time::timeout(Duration::from_secs(1), video.next())
        .await
        .expect("video stream timed out");
    assert!(ended.is_none());
}

#[tokio::test]
async fn proxy_refuses_non_ipv6_loopback_sources() {
    for url in [
        "http://127.0.0.1:1234/stream.mjpeg",
        "http://example.com/stream.mjpeg",
        "https://[::1]:1234/stream.mjpeg",
        "not a url",
    ] {
        let response = proxy_response(url.to_string(), Arc::new(AtomicBool::new(true))).await;
        assert_eq!(response.status(), StatusCode::BAD_GATEWAY);
    }
}

#[tokio::test]
async fn proxy_body_closes_with_an_error_after_an_idle_upstream() {
    let upstream = stream::iter([Ok(Bytes::from_static(b"frame"))])
        .chain(stream::pending::<Result<Bytes, std::io::Error>>());
    let healthy = Arc::new(AtomicBool::new(true));
    let mut bounded = Box::pin(monitored_proxy_stream(
        upstream,
        Duration::from_millis(20),
        healthy.clone(),
    ));

    assert!(healthy.load(Ordering::Relaxed));
    assert_eq!(
        bounded.next().await.unwrap().unwrap(),
        Bytes::from_static(b"frame")
    );
    let error = bounded.next().await.unwrap().unwrap_err();
    assert_eq!(error.kind(), std::io::ErrorKind::TimedOut);
    assert!(!healthy.load(Ordering::Relaxed));
    assert!(bounded.next().await.is_none());
}
