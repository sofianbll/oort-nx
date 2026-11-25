//! oort-core, the Swift program that holds the logic: one JSON line out, one JSON line back.

use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{channel, Receiver};
use std::sync::Mutex;
use std::time::Duration;

/// Longer than any answer: a folder of thousands of games reads in well under a second.
const PATIENCE: Duration = Duration::from_secs(20);

struct Running {
    child: Child,
    stdin: ChildStdin,
    lines: Receiver<String>,
}

impl Drop for Running {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

pub struct Companion {
    program: PathBuf,
    args: Vec<String>,
    running: Mutex<(u64, Option<Running>)>,
}

impl Companion {
    pub fn new(program: PathBuf, args: Vec<String>) -> Companion {
        Companion { program, args, running: Mutex::new((0, None)) }
    }

    fn start(&self) -> Result<Running, String> {
        let mut cmd = Command::new(&self.program);
        cmd.args(&self.args).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::inherit());
        hide_console(&mut cmd);
        let mut child = cmd.spawn().map_err(|e| format!("core-start: {e}"))?;
        let stdin = child.stdin.take().ok_or("core-start")?;
        let stdout = child.stdout.take().ok_or("core-start")?;
        let (tx, lines) = channel();
        std::thread::spawn(move || {
            for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                if tx.send(line).is_err() {
                    break;
                }
            }
        });
        Ok(Running { child, stdin, lines })
    }

    /// One request. A companion that died or hangs is replaced on the next one: what it keeps is on disk.
    pub fn ask(&self, method: &str, params: Value) -> Result<Value, String> {
        let mut guard = self.running.lock().unwrap_or_else(|e| e.into_inner());
        let (id, slot) = &mut *guard;
        *id += 1;
        if slot.is_none() {
            *slot = Some(self.start()?);
        }
        let Some(running) = slot.as_mut() else { return Err("core-start".into()) };
        let line = json!({ "id": *id, "method": method, "params": params }).to_string() + "\n";
        let reply = running
            .stdin
            .write_all(line.as_bytes())
            .and_then(|_| running.stdin.flush())
            .ok()
            .and_then(|_| running.lines.recv_timeout(PATIENCE).ok());
        let Some(reply) = reply else {
            *slot = None;
            return Err("core-lost".into());
        };
        let reply: Value = serde_json::from_str(&reply).map_err(|_| "core-reply".to_string())?;
        if reply["id"] != json!(*id) {
            *slot = None;
            return Err("core-reply".into());
        }
        match reply.get("error").and_then(Value::as_str) {
            Some(code) => Err(code.to_string()),
            None => Ok(reply.get("result").cloned().unwrap_or(Value::Null)),
        }
    }
}

/// No console flashes up behind the window.
fn hide_console(_cmd: &mut Command) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        _cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    fn fake(script: &str) -> Companion {
        Companion::new("/bin/sh".into(), vec!["-c".into(), script.into()])
    }

    #[test]
    fn answers_errors_and_a_new_start_after_a_death() {
        let c = fake(r#"while read l; do id=$(echo "$l" | sed 's/.*"id":\([0-9]*\).*/\1/'); case "$l" in *die*) exit 1;; *bad*) echo "{\"id\":$id,\"error\":\"no\"}";; *) echo "{\"id\":$id,\"result\":[1]}";; esac; done"#);
        assert_eq!(c.ask("ok", json!({})), Ok(json!([1])));
        assert_eq!(c.ask("bad", json!({})), Err("no".into()));
        assert_eq!(c.ask("die", json!({})), Err("core-lost".into()));
        assert_eq!(c.ask("ok", json!({})), Ok(json!([1])));
    }

    #[test]
    fn a_reply_to_something_else_is_not_believed() {
        let c = fake(r#"while read l; do echo '{"id":999,"result":1}'; done"#);
        assert_eq!(c.ask("ok", json!({})), Err("core-reply".into()));
        assert!(Companion::new("/nowhere/oort-core".into(), vec![]).ask("ok", json!({})).unwrap_err().starts_with("core-start"));
    }
}
