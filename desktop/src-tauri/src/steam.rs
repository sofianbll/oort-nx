//! A game Steam starts: the number goes to Steam, then the game's own processes are followed. Steam may update itself or
//! the game first, and a game may ask Steam to start it again: none of these is its end.

use std::time::Duration;

/// Steam was told, and no game came. An update that runs starts the count again.
pub const DEADLINE: Duration = Duration::from_secs(300);
/// A process that ends this soon may be a launcher, or a game that asks Steam to start it again.
const SHORT: Duration = Duration::from_secs(20);
const AFTER_SHORT: Duration = Duration::from_secs(25);
const AFTER_LONG: Duration = Duration::from_secs(6);
/// How long a game that came and left may update before it counts as over.
const AFTER_UPDATE: Duration = Duration::from_secs(1800);

#[derive(Debug, PartialEq)]
pub enum Event {
    Started,
    /// How long ago the game was last seen.
    Ended(Duration),
    NeverCame,
}

/// What is known of one session, moved by looks at the running processes. Times count from the request.
#[derive(Default)]
pub struct Session {
    asked: Duration,
    played: Option<(Duration, Duration)>,
}

impl Session {
    pub fn look(&mut self, now: Duration, seen: bool, updating: bool) -> Option<Event> {
        match (self.played, seen) {
            (None, true) => {
                self.played = Some((now, now));
                Some(Event::Started)
            }
            (None, false) => {
                if updating {
                    self.asked = now;
                }
                (now - self.asked > DEADLINE).then_some(Event::NeverCame)
            }
            (Some((first, _)), true) => {
                self.played = Some((first, now));
                None
            }
            (Some((first, last)), false) => {
                let short = last - first < SHORT;
                let wait = if short && updating { AFTER_UPDATE } else if short { AFTER_SHORT } else { AFTER_LONG };
                (now - last > wait).then_some(Event::Ended(now - last))
            }
        }
    }

    pub fn has_started(&self) -> bool {
        self.played.is_some()
    }

    pub fn idle(&self, now: Duration) -> Duration {
        self.played.map_or(Duration::ZERO, |(_, last)| now - last)
    }
}

/// Built from a number, nothing else.
pub fn link(app: u32) -> String {
    format!("steam://rungameid/{app}")
}

/// Where Steam says it is installed, in the registry of this user, then of the machine.
#[cfg(windows)]
pub fn folder() -> Option<String> {
    use windows::core::w;
    use windows::Win32::System::Registry::{HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE};
    text(HKEY_CURRENT_USER, w!("Software\\Valve\\Steam"), w!("SteamPath"))
        .or_else(|| text(HKEY_LOCAL_MACHINE, w!("SOFTWARE\\WOW6432Node\\Valve\\Steam"), w!("InstallPath")))
        .or_else(|| text(HKEY_LOCAL_MACHINE, w!("SOFTWARE\\Valve\\Steam"), w!("InstallPath")))
}

#[cfg(windows)]
fn text(root: windows::Win32::System::Registry::HKEY, key: windows::core::PCWSTR, name: windows::core::PCWSTR) -> Option<String> {
    use windows::Win32::System::Registry::{RegGetValueW, RRF_RT_REG_SZ};
    let mut buffer = [0u16; 1024];
    let mut size = std::mem::size_of_val(&buffer) as u32;
    unsafe { RegGetValueW(root, key, name, RRF_RT_REG_SZ, None, Some(buffer.as_mut_ptr() as _), Some(&mut size)) }.ok().ok()?;
    let letters = buffer.iter().position(|c| *c == 0)?;
    Some(String::from_utf16_lossy(&buffer[..letters])).filter(|t| !t.is_empty())
}

/// On Linux the core knows the usual places; `OORT_STEAM` names one on a Mac, for the proofs.
#[cfg(not(windows))]
pub fn folder() -> Option<String> {
    if cfg!(debug_assertions) { std::env::var("OORT_STEAM").ok() } else { None }
}

/// Hands the game's number to Steam.
#[cfg(windows)]
pub fn start(app: u32) -> Result<(), String> {
    use windows::core::{w, HSTRING, PCWSTR};
    use windows::Win32::System::Registry::HKEY_CLASSES_ROOT;
    use windows::Win32::UI::{Shell::ShellExecuteW, WindowsAndMessaging::SW_SHOWNORMAL};
    // Without Steam, Windows would ask for an app to open the link with.
    text(HKEY_CLASSES_ROOT, w!("steam\\shell\\open\\command"), PCWSTR::null()).ok_or("steam-missing")?;
    let done = unsafe { ShellExecuteW(None, w!("open"), &HSTRING::from(link(app)), PCWSTR::null(), PCWSTR::null(), SW_SHOWNORMAL) };
    if done.0 as isize > 32 { Ok(()) } else { Err("steam-refused".into()) }
}

#[cfg(not(windows))]
pub fn start(app: u32) -> Result<(), String> {
    use std::process::{Command, Stdio};
    let program = if cfg!(target_os = "macos") { std::env::var("OORT_STEAM_OPEN").unwrap_or_else(|_| "/usr/bin/false".into()) } else { "xdg-open".into() };
    let mut child = Command::new(program).arg(link(app)).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().map_err(|_| "steam-missing")?;
    // It answers at once when nothing opens the link; some desktops keep it running.
    for _ in 0..20 {
        if let Ok(Some(status)) = child.try_wait() {
            return if status.success() { Ok(()) } else { Err("steam-missing".into()) };
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    std::thread::spawn(move || child.wait());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const S: fn(u64) -> Duration = Duration::from_secs;

    #[test]
    fn a_plain_game_starts_and_ends() {
        let mut s = Session::default();
        assert_eq!(s.look(S(1), false, false), None);
        assert_eq!(s.look(S(5), true, false), Some(Event::Started));
        assert_eq!(s.look(S(100), true, false), None);
        assert_eq!(s.look(S(103), false, false), None, "a moment between two processes is not the end");
        assert_eq!(s.look(S(104), true, false), None);
        assert_eq!(s.look(S(111), false, true), Some(Event::Ended(S(7))), "an update after a game does not hold it");
    }

    #[test]
    fn a_game_that_steam_starts_again_is_one_session() {
        let mut s = Session::default();
        assert_eq!(s.look(S(2), true, false), Some(Event::Started));
        assert_eq!(s.look(S(4), false, false), None);
        assert_eq!(s.look(S(20), false, false), None, "Steam takes its time");
        assert_eq!(s.look(S(21), true, false), None);
        assert!(s.has_started());
        let mut gone = Session::default();
        gone.look(S(2), true, false);
        assert_eq!(gone.look(S(28), false, false), Some(Event::Ended(S(26))));
        let mut updated = Session::default();
        updated.look(S(2), true, false);
        assert_eq!(updated.look(S(600), false, true), None, "it left so that Steam updates it");
        assert_eq!(updated.look(S(620), true, false), None);
        assert_eq!(updated.idle(S(621)), S(1));
    }

    #[test]
    fn an_update_is_waited_for_and_silence_is_not() {
        let mut s = Session::default();
        for t in 1..1000 {
            assert_eq!(s.look(S(t), false, true), None);
        }
        assert_eq!(s.look(S(1299), false, false), None);
        assert_eq!(s.look(S(1300), false, false), Some(Event::NeverCame));
    }

    #[test]
    fn the_link_is_a_number() {
        assert_eq!(link(900100), "steam://rungameid/900100");
    }
}
