//! Reading a public address for the core, when the player said yes: which address, and what its answer means, is the
//! core's (Online.swift). Here are the bounds: the hosts, the time, the size, the pace.

use crate::Host;
use serde_json::{json, Value};
use std::collections::VecDeque;
use std::io::Read;
use std::path::PathBuf;
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter};

/// Between two questions, whatever asks.
const PACE: Duration = Duration::from_millis(600);
const REST: Duration = Duration::from_secs(60);
const LONGEST_REST: Duration = Duration::from_secs(900);
/// A service that says it is asked too much is left alone.
const SLOW_REST: Duration = Duration::from_secs(300);
const STEPS: usize = 20;

#[derive(Default)]
pub struct Online {
    waiting: Mutex<VecDeque<String>>,
    added: Condvar,
    /// One lookup at a time, and when the last question went out.
    busy: Mutex<Option<Instant>>,
}

fn agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(20)))
        .timeout_connect(Some(Duration::from_secs(6)))
        .max_redirects(0)
        .http_status_as_error(false)
        .user_agent(concat!("OortNX/", env!("CARGO_PKG_VERSION")))
        .tls_config(ureq::tls::TlsConfig::builder().provider(ureq::tls::TlsProvider::NativeTls).root_certs(ureq::tls::RootCerts::PlatformVerifier).build())
        .build()
        .into()
}

/// The places the core may name, checked again here.
fn allowed(url: &str) -> bool {
    let Some(rest) = url.strip_prefix("https://") else { return false };
    let host = rest.split(['/', '?', '#']).next().unwrap_or_default();
    let wikipedia = ["en", "it", "fr", "de", "es", "pt", "zh"].iter().any(|l| host == format!("{l}.wikipedia.org"));
    let pictures = [".steamstatic.com", ".steamusercontent.com"].iter().any(|s| host.ends_with(s));
    host.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-') && (host == "store.steampowered.com" || host == "www.wikidata.org" || wikipedia || pictures)
}

/// The proofs answer from this computer: `OORT_ONLINE=http://127.0.0.1:<port>` and nothing else.
fn place(url: &str) -> Option<String> {
    let Ok(own) = std::env::var("OORT_ONLINE") else { return Some(url.to_string()) };
    let port: u16 = own.strip_prefix("http://127.0.0.1:")?.parse().ok()?;
    Some(format!("http://127.0.0.1:{port}/{}", url.strip_prefix("https://")?))
}

/// One address: its status and its bytes. No answer, too late or too large is status 0.
fn read(agent: &ureq::Agent, url: &str, limit: u64) -> (u16, Vec<u8>) {
    let get = || -> Option<(u16, Vec<u8>)> {
        let mut reply = agent.get(place(url)?).call().ok()?;
        let status = reply.status().as_u16();
        let mut bytes = Vec::new();
        reply.body_mut().with_config().limit(limit + 1).reader().read_to_end(&mut bytes).ok()?;
        (bytes.len() as u64 <= limit).then_some((status, bytes))
    };
    get().unwrap_or((0, Vec::new()))
}

impl Online {
    /// Asks for these games when there is time; `front` before the others.
    pub fn want(&self, ids: Vec<String>, front: bool) {
        let mut waiting = self.waiting.lock().unwrap_or_else(|e| e.into_inner());
        for id in ids {
            if front {
                waiting.retain(|w| *w != id);
                waiting.push_front(id);
            } else if !waiting.contains(&id) {
                waiting.push_back(id);
            }
        }
        waiting.truncate(20_000);
        self.added.notify_one();
    }

    fn next(&self) -> String {
        let mut waiting = self.waiting.lock().unwrap_or_else(|e| e.into_inner());
        loop {
            if let Some(id) = waiting.pop_front() {
                return id;
            }
            waiting = self.added.wait(waiting).unwrap_or_else(|e| e.into_inner());
        }
    }

    /// One lookup, question by question.
    pub fn run(&self, host: &Host, start: Value) -> Result<Value, String> {
        let mut last = self.busy.lock().unwrap_or_else(|e| e.into_inner());
        let agent = agent();
        let mut step = host.core.ask("online.start", start)?;
        for _ in 0..STEPS {
            if step["done"] == json!(true) {
                return Ok(step);
            }
            let url = step["get"].as_str().filter(|u| allowed(u)).ok_or("online")?;
            if let Some(before) = *last {
                std::thread::sleep(PACE.saturating_sub(before.elapsed()));
            }
            *last = Some(Instant::now());
            let (status, bytes) = read(&agent, url, step["limit"].as_u64().unwrap_or(1 << 20).min(16 << 20));
            let answer = match step["save"].as_str() {
                Some(save) => {
                    let part = PathBuf::from(format!("{save}.part"));
                    let written = status == 200 && std::fs::write(part, bytes).is_ok();
                    json!({ "status": if written { 200 } else { 404 } })
                }
                None => json!({ "status": status, "text": String::from_utf8_lossy(&bytes) }),
            };
            step = host.core.ask("online.answer", answer)?;
        }
        Err("online".into())
    }

    /// The library's games, one after the other. Without a network it rests, longer each time, and says nothing.
    pub fn work(self: Arc<Self>, host: Arc<Host>, app: AppHandle) {
        std::thread::spawn(move || {
            let mut rest = REST;
            loop {
                let id = self.next();
                match self.run(&host, json!({ "id": id })) {
                    Ok(done) => {
                        rest = REST;
                        let _ = app.emit("online", json!({ "id": id, "found": done["found"] }));
                    }
                    Err(e) if e == "online-off" => self.waiting.lock().unwrap_or_else(|e| e.into_inner()).clear(),
                    Err(e) if e == "online" || e == "online-slow" => {
                        self.want(vec![id], true);
                        std::thread::sleep(if e == "online-slow" { SLOW_REST } else { rest });
                        rest = (rest * 2).min(LONGEST_REST);
                    }
                    Err(_) => {}
                }
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::net::TcpListener;

    #[test]
    fn only_the_listed_hosts_are_read() {
        for good in ["https://store.steampowered.com/api/storesearch/?term=a", "https://fr.wikipedia.org/w/api.php?x", "https://www.wikidata.org/w/api.php", "https://shared.akamai.steamstatic.com/a.jpg"] {
            assert!(allowed(good), "{good}");
        }
        for bad in ["http://store.steampowered.com/", "https://store.steampowered.com:444/", "https://store.steampowered.com@x.org/", "https://steamstatic.com.x.org/", "https://127.0.0.1/", "https://xwikipedia.org/", "file:///etc/passwd"] {
            assert!(!allowed(bad), "{bad}");
        }
    }

    /// A service on this computer that answers once.
    fn answering(reply: &'static [u8]) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let at = format!("http://{}/x", listener.local_addr().unwrap());
        std::thread::spawn(move || {
            if let Ok((mut s, _)) = listener.accept() {
                let mut ask = [0; 2048];
                let _ = std::io::Read::read(&mut s, &mut ask);
                let _ = s.write_all(reply);
            }
        });
        at
    }

    #[test]
    fn answers_are_bounded_and_failures_are_quiet() {
        let a = agent();
        assert_eq!(read(&a, &answering(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok"), 10), (200, b"ok".to_vec()));
        assert_eq!(read(&a, &answering(b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nlarge"), 4).0, 0, "too large");
        assert_eq!(read(&a, &answering(b"HTTP/1.1 429 Slow\r\nContent-Length: 0\r\n\r\n"), 4).0, 429);
        assert_ne!(read(&a, &answering(b"HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:1/\r\nContent-Length: 0\r\n\r\n"), 4).0, 200, "a redirect is not followed");
        assert_eq!(read(&a, &answering(b"HTTP/1.1 200 OK\r\nContent-Length: 50\r\n\r\ncut"), 100).0, 0, "cut short");
        assert_eq!(read(&a, "http://127.0.0.1:1/", 4).0, 0, "nobody there");
    }

    #[test]
    fn a_game_waits_once_and_the_one_looked_at_goes_first() {
        let o = Online::default();
        o.want(vec!["a".into(), "b".into(), "a".into()], false);
        o.want(vec!["b".into()], true);
        assert_eq!((o.next(), o.next()), ("b".to_string(), "a".to_string()));
        assert!(o.waiting.lock().unwrap().is_empty());
    }
}
