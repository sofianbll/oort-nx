//! The processes of one session on Linux (and a Mac while developing): the child in a process group of its own.

use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::PathBuf;
use std::process::{Child, ChildStdout, Command};
use std::sync::Mutex;
use std::time::{Duration, Instant};

pub struct Tracked {
    child: Mutex<Option<Child>>,
    group: i32,
    code: Mutex<Option<i64>>,
}

const LOOK: Duration = Duration::from_millis(250);

impl Tracked {
    pub fn spawn(cmd: &mut Command, folder: Option<PathBuf>) -> Result<Tracked, String> {
        Tracked::spawn_read(cmd, folder).map(|(tracked, _)| tracked)
    }

    /// `spawn`, with what the program prints when `cmd` pipes it.
    pub fn spawn_read(cmd: &mut Command, _folder: Option<PathBuf>) -> Result<(Tracked, Option<ChildStdout>), String> {
        let mut child = cmd.process_group(0).spawn().map_err(|e| e.to_string())?;
        let output = child.stdout.take();
        Ok((Tracked { group: child.id() as i32, child: Mutex::new(Some(child)), code: Mutex::new(None) }, output))
    }

    /// Blocks until the child and everything it left in its group are gone.
    pub fn wait(&self) {
        let child = self.child.lock().unwrap_or_else(|e| e.into_inner()).take();
        if let Some(mut child) = child {
            if let Ok(status) = child.wait() {
                // A signal is no exit code; the core reads a missing one as a crash.
                *self.code.lock().unwrap_or_else(|e| e.into_inner()) =
                    status.code().or(status.signal().map(|s| 128 + s)).map(i64::from);
            }
        }
        while self.alive() {
            std::thread::sleep(LOOK);
        }
    }

    fn alive(&self) -> bool {
        unsafe { libc::kill(-self.group, 0) == 0 && !only_dead(self.group) }
    }

    pub fn exit_code(&self) -> Option<i64> {
        *self.code.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Asks every process of the session to end, then ends what is left after `grace`.
    pub fn close(&self, grace: Duration) {
        let until = Instant::now() + grace;
        unsafe { libc::kill(-self.group, libc::SIGTERM) };
        while self.alive() && Instant::now() < until {
            std::thread::sleep(LOOK);
        }
        if self.alive() {
            unsafe { libc::kill(-self.group, libc::SIGKILL) };
        }
    }
}

/// Processes that ended but that nobody has collected still answer a signal: where the system's first process leaves
/// them (a container, some sandboxes), a session would never end.
#[cfg(target_os = "linux")]
fn only_dead(group: i32) -> bool {
    let Ok(all) = std::fs::read_dir("/proc") else { return false };
    let mut seen = false;
    for entry in all.flatten().filter(|e| e.file_name().to_string_lossy().bytes().all(|b| b.is_ascii_digit())) {
        let Some((state, of)) = std::fs::read_to_string(entry.path().join("stat")).ok().as_deref().and_then(state_and_group) else { continue };
        if of == group {
            if !matches!(state, 'Z' | 'X') {
                return false;
            }
            seen = true;
        }
    }
    seen
}

#[cfg(not(target_os = "linux"))]
fn only_dead(_group: i32) -> bool {
    false
}

/// `pid (name) state parent group …`, whatever the name holds.
#[cfg(any(target_os = "linux", test))]
fn state_and_group(stat: &str) -> Option<(char, i32)> {
    let mut after = stat[stat.rfind(')')? + 1..].split_whitespace();
    let state = after.next()?.chars().next()?;
    Some((state, after.nth(1)?.parse().ok()?))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sh(script: &str) -> Tracked {
        Tracked::spawn(Command::new("/bin/sh").args(["-c", script]), None).unwrap()
    }

    #[test]
    fn a_session_lasts_as_long_as_what_the_launcher_started() {
        let t0 = Instant::now();
        let t = sh("(sleep 1) & exit 7");
        t.wait();
        assert!(t0.elapsed() >= Duration::from_millis(900), "the child of the stub counts");
        assert_eq!(t.exit_code(), Some(7));
    }

    #[test]
    fn closing_asks_then_ends() {
        for script in ["sleep 30", "trap '' TERM; sleep 30 & wait; wait; sleep 30"] {
            let t = std::sync::Arc::new(sh(script));
            let waiter = { let t = t.clone(); std::thread::spawn(move || t.wait()) };
            std::thread::sleep(Duration::from_millis(200));
            let t0 = Instant::now();
            t.close(Duration::from_millis(600));
            waiter.join().unwrap();
            assert!(t0.elapsed() < Duration::from_secs(4), "{script}");
        }
    }

    #[test]
    fn a_state_is_read_whatever_the_name() {
        assert_eq!(state_and_group("12 (a) b (c) Z 1 77 12 0"), Some(('Z', 77)));
        assert_eq!(state_and_group("12 (sh) S 1 12 12 0"), Some(('S', 12)));
        assert_eq!(state_and_group("nothing"), None);
    }

    #[test]
    fn a_program_that_does_not_start_says_so() {
        assert!(Tracked::spawn(&mut Command::new("/nowhere/game"), None).is_err());
    }
}
