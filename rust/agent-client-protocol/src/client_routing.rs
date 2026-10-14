use super::AcpClient;
use crate::client::PendingCallKind;
use crate::rpc::{self, AcpIncoming, AcpResponse};
use crate::AcpError;
use alera_agent_transport::JsonTransport;
use std::time::Duration;

enum RoutingEvent {
    Frame(Box<Result<AcpIncoming, AcpResponse>>),
    Callback,
    Eof,
}

impl<T: JsonTransport> AcpClient<T> {
    pub async fn next_incoming(&mut self) -> Result<Option<AcpIncoming>, AcpError> {
        self.ensure_open()?;
        match self.next_routed_incoming().await {
            Ok(incoming) => Ok(incoming),
            Err(error) => self.fail_routing(error).await,
        }
    }

    async fn next_routed_incoming(&mut self) -> Result<Option<AcpIncoming>, AcpError> {
        loop {
            self.flush_callbacks().await?;
            if let Some(message) = self.incoming.pop_front() {
                return Ok(Some(message));
            }
            match self.receive_routed().await? {
                RoutingEvent::Frame(frame) => match *frame {
                    Ok(incoming) => self.dispatch_request(incoming)?,
                    Err(response) => {
                        let is_prompt = self
                            .pending
                            .get(&response.id.key())
                            .is_some_and(|pending| pending.kind == PendingCallKind::Prompt);
                        self.route_response(response.clone())?;
                        if is_prompt {
                            self.completed.remove(&response.id.key());
                            return Ok(Some(AcpIncoming::Response(response)));
                        }
                    }
                },
                RoutingEvent::Callback => {}
                RoutingEvent::Eof => {
                    self.stop_routing();
                    self.callbacks.reap().await;
                    return Ok(None);
                }
            }
        }
    }

    pub(super) async fn receive_for_call(&mut self, timeout: Duration) -> Result<(), AcpError> {
        let received = tokio::time::timeout(timeout, self.receive_routed()).await;
        let result = match received {
            Ok(Ok(RoutingEvent::Frame(frame))) => match *frame {
                Ok(incoming) => self.dispatch_request(incoming),
                Err(response) => self.route_response(response),
            },
            Ok(Ok(RoutingEvent::Callback)) => Ok(()),
            Ok(Ok(RoutingEvent::Eof)) => Err(AcpError::Closed),
            Ok(Err(error)) => Err(error),
            Err(_) => Err(AcpError::Timeout {
                method: "receive".into(),
                timeout,
            }),
        };
        match result {
            Ok(()) => Ok(()),
            Err(error) => self.fail_routing(error).await,
        }
    }

    async fn receive_routed(&mut self) -> Result<RoutingEvent, AcpError> {
        self.flush_callbacks().await?;
        // Give newly spawned handlers one scheduling turn without holding
        // the transport, so ready callbacks are not starved by ready frames.
        if !self.callbacks.tasks.is_empty() {
            tokio::task::yield_now().await;
        }
        tokio::select! {
            biased;
            completed = self.callbacks.tasks.join_next(), if !self.callbacks.tasks.is_empty() => {
                if let Some(completed) = completed {
                    self.finish_callback(completed)?;
                }
                Ok(RoutingEvent::Callback)
            }
            received = self.transport.recv() => {
                let received = received.map_err(AcpError::from)
                    .and_then(|value| value.map(rpc::classify).transpose());
                match received {
                    Ok(Some(received)) => Ok(RoutingEvent::Frame(Box::new(received))),
                    Ok(None) => Ok(RoutingEvent::Eof),
                    Err(error) => Err(error),
                }
            }
        }
    }

    fn dispatch_request(&mut self, incoming: AcpIncoming) -> Result<(), AcpError> {
        let result = match incoming {
            AcpIncoming::Request(request) => self.callbacks.register(&request.id).and_then(|()| {
                if let Some(handler) = self.request_handler.clone() {
                    self.callbacks.dispatch(request, handler, self.timeout);
                    Ok(())
                } else {
                    self.enqueue(AcpIncoming::Request(request))
                }
            }),
            incoming => self.enqueue(incoming),
        };
        if result.is_err() {
            self.stop_routing();
        }
        result
    }

    fn finish_callback(
        &mut self,
        completed: Result<crate::callbacks::CallbackResult, tokio::task::JoinError>,
    ) -> Result<(), AcpError> {
        let result = self
            .callbacks
            .completed(completed, self.timeout, self.max_response_frame_bytes)
            .and_then(|request| {
                if let Some(request) = request {
                    self.enqueue(AcpIncoming::Request(request))?;
                }
                Ok(())
            });
        if result.is_err() {
            self.stop_routing();
        }
        result
    }

    pub(super) async fn flush_callbacks(&mut self) -> Result<(), AcpError> {
        while let Some(completed) = self.callbacks.tasks.try_join_next() {
            if let Err(error) = self.finish_callback(completed) {
                return self.fail_routing(error).await;
            }
        }
        while let Some(response) = self.callbacks.outbox.front() {
            let sent = tokio::time::timeout_at(
                response.deadline.into(),
                self.transport.send(response.frame.clone()),
            )
            .await;
            match sent {
                Ok(Ok(())) => self.callbacks.sent(),
                Ok(Err(error)) => return self.fail_routing(error.into()).await,
                Err(_) => {
                    return self
                        .fail_routing(AcpError::Timeout {
                            method: format!("peer response {}", response.id),
                            timeout: self.timeout,
                        })
                        .await;
                }
            }
        }
        Ok(())
    }

    pub(super) fn stop_routing(&mut self) {
        self.closed = true;
        self.pending.clear();
        self.completed.clear();
        self.incoming.clear();
        self.callbacks.abort();
    }

    pub(super) async fn send_frame(
        &mut self,
        frame: serde_json::Value,
        method: &str,
    ) -> Result<(), AcpError> {
        match tokio::time::timeout(self.timeout, self.transport.send(frame)).await {
            Ok(Ok(())) => Ok(()),
            Ok(Err(error)) => self.fail_routing(error.into()).await,
            Err(_) => {
                self.fail_routing(AcpError::Timeout {
                    method: method.into(),
                    timeout: self.timeout,
                })
                .await
            }
        }
    }

    pub(super) async fn fail_routing<R>(&mut self, error: AcpError) -> Result<R, AcpError> {
        self.stop_routing();
        self.callbacks.reap().await;
        let _ = tokio::time::timeout(self.timeout, self.transport.close()).await;
        Err(error)
    }
}
