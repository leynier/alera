use tokio::net::TcpListener;

pub(super) enum MobileGatewayReplacement {
    Keep,
    Disabled,
    Bound {
        listener: TcpListener,
        bind_address: String,
    },
}
