//! Receives one OAuth redirect on a port bound to 127.0.0.1 (RFC 8252), so the listener is never
//! reachable from the network.

use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

const MAX_REQUEST_BYTES: usize = 65_536;

pub struct Callback {
    pub code: String,
    stream: TcpStream,
}

impl Callback {
    pub async fn respond(mut self, html: &str) {
        send(&mut self.stream, "200 OK", html).await;
    }
}

/// Binds the loopback listener. Port 0 picks a free port.
pub async fn bind(port: u16) -> std::io::Result<TcpListener> {
    TcpListener::bind(("127.0.0.1", port)).await
}

/// Returns the first request whose target `extract` accepts. Favicon requests and stray
/// connections get a 404 and do not end the sign-in. `None` means the timeout passed.
pub async fn receive(listener: TcpListener, timeout: Duration, extract: impl Fn(&str) -> Option<String>) -> Option<Callback> {
    let wait = async {
        loop {
            let Ok((mut stream, _)) = listener.accept().await else { continue };
            let Some(target) = read_request_target(&mut stream).await else { continue };
            match extract(&target) {
                Some(code) => return Callback { code, stream },
                None => send(&mut stream, "404 Not Found", "").await,
            }
        }
    };
    tokio::time::timeout(timeout, wait).await.ok()
}

async fn read_request_target(stream: &mut TcpStream) -> Option<String> {
    let mut request = Vec::new();
    let mut buffer = [0u8; 4096];
    while !request.windows(4).any(|window| window == b"\r\n\r\n") && request.len() < MAX_REQUEST_BYTES {
        let read = tokio::time::timeout(Duration::from_secs(5), stream.read(&mut buffer)).await.ok()?.ok()?;
        if read == 0 {
            break;
        }
        request.extend_from_slice(&buffer[..read]);
    }
    let request = String::from_utf8_lossy(&request);
    let request_line = request.split("\r\n").next()?;
    request_line.split(' ').nth(1).map(str::to_owned)
}

async fn send(stream: &mut TcpStream, status: &str, html: &str) {
    let response = format!(
        "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{html}",
        html.len()
    );
    let _ = stream.write_all(response.as_bytes()).await;
    let _ = stream.shutdown().await;
}

/// The page the browser shows after the redirect.
pub fn page(title: &str, message: &str, succeeded: bool) -> String {
    let escape = |text: &str| text.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;");
    let (mark, color, background) = if succeeded { ("✓", "#62e6a0", "#173d2b") } else { ("!", "#ff7d8a", "#431f24") };
    format!(
        r#"<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>
:root{{color-scheme:dark}}body{{margin:0;min-height:100vh;display:grid;place-items:center;background:#050505;color:#fff;font-family:"Segoe UI",system-ui,sans-serif}}
.card{{width:min(420px,calc(100% - 40px));box-sizing:border-box;padding:42px 36px;border:1px solid #2a2a2a;border-radius:22px;background:#101010;text-align:center;box-shadow:0 24px 70px #000}}
.mark{{width:54px;height:54px;margin:0 auto 22px;border-radius:50%;display:grid;place-items:center;background:{background};color:{color};font-size:28px}}
h1{{margin:0 0 12px;font:32px Georgia,serif;letter-spacing:-.03em}}p{{margin:0;color:#a7a7a7;line-height:1.55;font-size:15px}}
</style></head><body><main class="card"><div class="mark">{mark}</div><h1>{}</h1><p>{}</p></main></body></html>"#,
        escape(title),
        escape(message)
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn ignores_stray_requests_and_returns_the_callback() {
        let listener = bind(0).await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let client = tokio::spawn(async move {
            for target in ["/favicon.ico", "/callback?code=abc"] {
                let mut stream = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
                stream.write_all(format!("GET {target} HTTP/1.1\r\nHost: x\r\n\r\n").as_bytes()).await.unwrap();
                let mut response = String::new();
                let _ = stream.read_to_string(&mut response).await;
                if target.starts_with("/favicon") {
                    assert!(response.starts_with("HTTP/1.1 404"));
                }
            }
        });

        let callback = receive(listener, Duration::from_secs(5), |target| {
            target.strip_prefix("/callback?code=").map(str::to_owned)
        })
        .await
        .unwrap();
        assert_eq!(callback.code, "abc");
        callback.respond("ok").await;
        client.await.unwrap();
    }

    #[test]
    fn pages_escape_messages() {
        assert!(page("Title", "<script>", false).contains("&lt;script&gt;"));
    }
}
