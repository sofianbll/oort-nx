//! The processes of one session on Linux (and a Mac while developing): the child in a process group of its own.

use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdout, Command};
use std::sync::Mutex;
use std::time::{Duration, Instant};

pub struct Tracked {
    /// Set when another program (Steam) starts the game: its folder and its number there.
    place: Option<(PathBuf, u32)>,
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
        Ok((Tracked { place: None, group: child.id() as i32, child: Mutex::new(Some(child)), code: Mutex::new(None) }, output))
    }

    /// A session that another program starts (Steam): nothing is spawned, only the processes of the folder are its own.
    pub fn of_folder(folder: PathBuf, app: u32) -> Result<Tracked, String> {
        let folder = std::fs::canonicalize(&folder).unwrap_or(folder);
        if folder.components().count() < 3 {
            return Err("folder-missing".into());
        }
        Ok(Tracked { place: Some((folder, app)), group: 0, child: Mutex::new(None), code: Mutex::new(None) })
    }

    /// Whether a process of the session runs now.
    pub fn is_running(&self) -> bool {
        match &self.place {
            Some((folder, app)) => !processes_of(folder, *app).is_empty(),
            None => self.alive(),
        }
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
        if let Some((folder, app)) = &self.place {
            let tell = |signal| processes_of(folder, *app).into_iter().for_each(|pid| unsafe { libc::kill(pid, signal); });
            tell(libc::SIGTERM);
            while self.is_running() && Instant::now() < until {
                std::thread::sleep(LOOK);
            }
            return tell(libc::SIGKILL);
        }
        unsafe { libc::kill(-self.group, libc::SIGTERM) };
        while self.alive() && Instant::now() < until {
            std::thread::sleep(LOOK);
        }
        if self.alive() {
            unsafe { libc::kill(-self.group, libc::SIGKILL) };
        }
    }
}

/// Processes run from a game's folder, or that Steam started for it (a Windows game runs inside a helper from elsewhere).
fn processes_of(folder: &Path, app: u32) -> Vec<i32> {
    let me = std::process::id() as i32;
    all_processes().into_iter().filter(|(pid, program, line)| *pid != me && belongs(program, line, folder, app)).map(|(pid, ..)| pid).collect()
}

fn belongs(program: &str, line: &[String], folder: &Path, app: u32) -> bool {
    let inside = |text: &str| Path::new(text) != folder && Path::new(text).starts_with(folder);
    inside(program)
        || line.iter().any(|w| w == "SteamLaunch") && line.iter().any(|w| *w == format!("AppId={app}"))
        || line.first().is_some_and(|w| inside(w))
}

#[cfg(target_os = "linux")]
fn all_processes() -> Vec<(i32, String, Vec<String>)> {
    let Ok(all) = std::fs::read_dir("/proc") else { return vec![] };
    all.flatten()
        .filter_map(|entry| {
            let pid = entry.file_name().to_str()?.parse().ok()?;
            // One that ended and that nobody collected has no command line.
            let line = std::fs::read(entry.path().join("cmdline")).ok().filter(|l| !l.is_empty())?;
            let program = std::fs::read_link(entry.path().join("exe")).map(|p| p.to_string_lossy().into_owned()).unwrap_or_default();
            Some((pid, program, line.split(|b| *b == 0).filter(|w| !w.is_empty()).map(|w| String::from_utf8_lossy(w).into_owned()).collect()))
        })
        .collect()
}

#[cfg(not(target_os = "linux"))]
fn all_processes() -> Vec<(i32, String, Vec<String>)> {
    let Ok(out) = Command::new("/bin/ps").args(["-axo", "pid=,command="]).output() else { return vec![] };
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter_map(|l| {
            let (pid, command) = l.trim().split_once(' ')?;
            // A script is run by its interpreter; its path may hold spaces.
            let command = command.trim();
            let program = command.find(" /").map_or(command, |at| &command[at + 1..]).to_string();
            Some((pid.parse().ok()?, program, command.split(' ').map(str::to_string).collect()))
        })
        .collect()
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
    fn a_game_is_known_by_its_folder_or_its_number() {
        let folder = Path::new("/home/a/Steam/steamapps/common/Drift");
        let words = |t: &str| t.split(' ').map(str::to_string).collect::<Vec<_>>();
        assert!(belongs("/home/a/Steam/steamapps/common/Drift/bin/drift", &words("drift"), folder, 9));
        assert!(belongs("/usr/bin/reaper", &words("reaper SteamLaunch AppId=9 -- x"), folder, 9));
        assert!(!belongs("/usr/bin/reaper", &words("reaper SteamLaunch AppId=99 -- x"), folder, 9));
        assert!(!belongs("/home/a/Steam/steamapps/common/Drift II/drift", &words("drift"), folder, 9));
        assert!(!belongs("/usr/bin/less", &words("less /home/a/Steam/steamapps/common/Drift/readme"), folder, 9));
        assert!(Tracked::of_folder("/".into(), 9).is_err());
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
