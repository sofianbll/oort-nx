//! Oort NX for Windows and Linux: the window, the controller, and the processes games run in.
//! Everything the app knows or decides is in oort-core (Swift), asked through `companion`.

mod companion;
mod online;
mod pad;
#[cfg(all(debug_assertions, target_os = "macos"))]
mod probe;
#[cfg(unix)]
#[path = "session_unix.rs"]
mod session;
#[cfg(windows)]
#[path = "session_windows.rs"]
mod session;
mod steam;

use companion::Companion;
use online::Online;
use serde_json::{json, Value};
use session::Tracked;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, Manager, State, WebviewWindowBuilder};

/// A sign of life for the session, so a power cut loses less than this.
const BEAT: Duration = Duration::from_secs(30);
/// The launch screen is seen before the window steps aside.
const STEP_ASIDE: Duration = Duration::from_millis(1600);
const CLOSE_GRACE: Duration = Duration::from_secs(8);
/// How often the processes of a game Steam started are looked at.
const LOOK: Duration = Duration::from_secs(1);
/// The waiting screen gives way to Steam after this.
const STEAM_ASIDE: Duration = Duration::from_secs(12);
const MAX_ART: u64 = 24 << 20;

#[derive(Default)]
struct Playing {
    game: Option<(Arc<Tracked>, Arc<AtomicBool>)>,
    preparing: Option<(Arc<Tracked>, Arc<AtomicBool>)>,
}

struct Host {
    core: Companion,
    data: PathBuf,
    playing: Mutex<Playing>,
    online: Arc<Online>,
    /// Names of the controllers plugged in, as the system gives them.
    pads: Mutex<Vec<String>>,
    /// The window stepped aside for a game, and has to come back.
    aside: AtomicBool,
}

impl Host {
    fn playing(&self) -> std::sync::MutexGuard<'_, Playing> {
        self.playing.lock().unwrap_or_else(|e| e.into_inner())
    }
}

/// The page's questions to the core. Requests that start or end something are the host's own.
#[tauri::command(async)]
fn core(host: State<'_, Arc<Host>>, method: String, params: Value) -> Result<Value, String> {
    let own = ["launch.plan", "prepare.plan", "prepare.end", "prepare.line", "game.art", "online.start", "online.answer", "steam.where", "steam.updating"];
    if own.contains(&method.as_str()) || method.starts_with("session.") {
        return Err("method".into());
    }
    if ["library.rescan", "steam", "steam.set"].contains(&method.as_str()) {
        find_steam(&host);
    }
    host.core.ask(&method, params)
}

/// Steam may be installed while Oort is open: the registry is asked each time it matters.
fn find_steam(host: &Host) {
    if let Some(path) = steam::folder() {
        let _ = host.core.ask("steam.where", json!({ "path": path }));
    }
}

fn command(plan: &Value) -> Result<Command, String> {
    let text = |k: &str| plan[k].as_str().map(str::to_string).ok_or(format!("plan-{k}"));
    let mut cmd = Command::new(text("program")?);
    cmd.args(plan["args"].as_array().into_iter().flatten().filter_map(Value::as_str)).current_dir(text("directory")?);
    for (name, value) in plan["env"].as_object().into_iter().flatten() {
        if let Some(value) = value.as_str() {
            cmd.env(name, value);
        }
    }
    cmd.stdin(Stdio::null());
    Ok(cmd)
}

/// What the game prints goes to one file per game, the last launch only.
fn log(data: &Path, id: &str) -> Result<(Stdio, Stdio), String> {
    let folder = data.join("logs");
    std::fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
    let name: String = id.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '-').collect();
    let file = std::fs::File::create(folder.join(name + ".log")).map_err(|e| e.to_string())?;
    Ok((file.try_clone().map_err(|e| e.to_string())?.into(), file.into()))
}

#[tauri::command(async)]
fn launch(app: AppHandle, host: State<'_, Arc<Host>>, id: String, fullscreen: bool) -> Result<Value, String> {
    let host = host.inner().clone();
    let mut playing = host.playing();
    if playing.game.is_some() || playing.preparing.is_some() {
        return Err("already-playing".into());
    }
    let plan = host.core.ask("launch.plan", json!({ "id": id, "mode": if fullscreen { "bigpicture" } else { "desktop" } }))?;
    if let Some(number) = plan["steam"].as_u64().and_then(|n| u32::try_from(n).ok()) {
        let folder = plan["folder"].as_str().map(PathBuf::from).ok_or("folder-missing")?;
        let tracked = Arc::new(Tracked::of_folder(folder, number)?);
        steam::start(number)?;
        let closed = Arc::new(AtomicBool::new(false));
        playing.game = Some((tracked.clone(), closed.clone()));
        drop(playing);
        std::thread::spawn(move || follow_steam(app, host, id, tracked, closed));
        return Ok(Value::Null);
    }
    let mut cmd = command(&plan)?;
    let (out, err) = log(&host.data, &id)?;
    cmd.stdout(out).stderr(err);
    let tracked = Arc::new(Tracked::spawn(&mut cmd, plan["folder"].as_str().map(PathBuf::from)).map_err(|e| format!("start: {e}"))?);
    let closed = Arc::new(AtomicBool::new(false));
    playing.game = Some((tracked.clone(), closed.clone()));
    drop(playing);
    let session = host.core.ask("session.start", json!({ "id": id })).unwrap_or(Value::Null);
    let ended = Arc::new(AtomicBool::new(false));

    let (beat_host, beat_session, beat_ended) = (host.clone(), session.clone(), ended.clone());
    std::thread::spawn(move || loop {
        std::thread::park_timeout(BEAT);
        if beat_ended.load(Ordering::Relaxed) {
            break;
        }
        let _ = beat_host.core.ask("session.beat", json!({ "session": beat_session }));
    });

    let (aside_app, aside_ended) = (app.clone(), ended.clone());
    std::thread::spawn(move || {
        std::thread::sleep(STEP_ASIDE);
        if !aside_ended.load(Ordering::Relaxed) {
            step_aside(&aside_app);
        }
    });

    std::thread::spawn(move || {
        tracked.wait();
        ended.store(true, Ordering::Relaxed);
        let code = tracked.exit_code().map(|c| json!(c)).unwrap_or(Value::Null);
        let end = host
            .core
            .ask("session.end", json!({ "session": session, "code": code, "closed": closed.load(Ordering::Relaxed) }))
            .unwrap_or_else(|e| json!({ "id": id, "error": e }));
        come_back(&app, &host, end);
    });
    Ok(Value::Null)
}

fn come_back(app: &AppHandle, host: &Host, end: Value) {
    host.playing().game = None;
    let aside = host.aside.swap(false, Ordering::SeqCst);
    if let Some(w) = app.get_webview_window("main") {
        // GNOME leaves a minimized window where it is when it asks to come back (Wayland has no such request, and X11
        // refuses one that no key or click made): hidden, then shown anew, it is in front again.
        // shortcut: under X11 a full screen window comes back as a window (F11 twice); Wayland keeps it. Ceiling: asked
        // right after `show`, X11 ignores it; the next try asks once the window is mapped again.
        if aside && cfg!(target_os = "linux") {
            let _ = w.hide();
        }
        let _ = w.show();
        let _ = w.unminimize();
        let _ = w.set_focus();
    }
    let _ = app.emit("session", end);
}

fn step_aside(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        app.state::<Arc<Host>>().aside.store(true, Ordering::SeqCst);
        let _ = w.minimize();
    }
}

/// Looks at the game's own processes until they are gone for good. Play time counts from the first one to the last.
fn follow_steam(app: AppHandle, host: Arc<Host>, id: String, tracked: Arc<Tracked>, closed: Arc<AtomicBool>) {
    let from = Instant::now();
    let (mut game, mut session, mut beat, mut aside, mut said) = (steam::Session::default(), Value::Null, Instant::now(), None, "");
    let updating = || host.core.ask("steam.updating", json!({ "id": id })).unwrap_or(Value::Null) == json!(true);
    loop {
        let seen = tracked.is_running();
        // Steam's own files are read only while they can change the answer.
        let update = !seen && updating();
        let phase = if seen || game.has_started() { "playing" } else if update { "updating" } else { "waiting" };
        if phase != said {
            said = phase;
            let _ = app.emit("steam", json!({ "id": id, "phase": phase }));
        }
        match game.look(from.elapsed(), seen, update) {
            Some(steam::Event::Started) => {
                session = host.core.ask("session.start", json!({ "id": id })).unwrap_or(Value::Null);
                (beat, aside) = (Instant::now(), Some(Instant::now() + STEP_ASIDE));
            }
            Some(steam::Event::Ended(_)) => break,
            Some(steam::Event::NeverCame) => return come_back(&app, &host, json!({ "id": id, "error": "steam-not-started" })),
            None => {}
        }
        if closed.load(Ordering::Relaxed) && !seen {
            break;
        }
        // A window of Steam's own may be waiting for an answer behind Oort.
        if aside.is_none() && !game.has_started() && from.elapsed() > STEAM_ASIDE {
            aside = Some(Instant::now());
        }
        if aside.is_some_and(|at| Instant::now() >= at) {
            step_aside(&app);
            aside = Some(from + Duration::from_secs(u32::MAX.into()));
        }
        if beat.elapsed() > BEAT && session.is_string() {
            beat = Instant::now();
            let _ = host.core.ask("session.beat", json!({ "session": session }));
        }
        std::thread::sleep(LOOK);
    }
    let end = if session.is_string() {
        // Steam keeps the game's code to itself: a game of Steam's never counts as a crash.
        host.core
            .ask("session.end", json!({ "session": session, "code": 0, "closed": true, "idle": game.idle(from.elapsed()).as_secs_f64() }))
            .unwrap_or_else(|e| json!({ "id": id, "error": e }))
    } else {
        json!({ "id": id, "cancelled": true })
    };
    come_back(&app, &host, end);
}

#[tauri::command(async)]
fn close_game(host: State<'_, Arc<Host>>) -> Result<(), String> {
    let playing = host.playing();
    let (tracked, closed) = playing.game.as_ref().or(playing.preparing.as_ref()).cloned().ok_or("not-playing")?;
    drop(playing);
    closed.store(true, Ordering::Relaxed);
    tracked.close(CLOSE_GRACE);
    Ok(())
}

/// The game's own setup step: no window, its progress lines shown as they come.
#[tauri::command(async)]
fn prepare(app: AppHandle, host: State<'_, Arc<Host>>, id: String) -> Result<(), String> {
    let host = host.inner().clone();
    let mut playing = host.playing();
    if playing.game.is_some() || playing.preparing.is_some() {
        return Err("already-playing".into());
    }
    let plan = host.core.ask("prepare.plan", json!({ "id": id }))?;
    let mut cmd = command(&plan)?;
    let (_, err) = log(&host.data, &format!("{id}-prepare"))?;
    cmd.stdout(Stdio::piped()).stderr(err);
    let tracked = Tracked::spawn_read(&mut cmd, plan["folder"].as_str().map(PathBuf::from)).map_err(|e| format!("start: {e}"))?;
    let (tracked, output) = (Arc::new(tracked.0), tracked.1);
    playing.preparing = Some((tracked.clone(), Arc::new(AtomicBool::new(false))));
    drop(playing);
    std::thread::spawn(move || {
        if let Some(output) = output {
            for line in BufReader::new(output).lines().map_while(Result::ok) {
                if let Ok(Value::Object(progress)) = host.core.ask("prepare.line", json!({ "line": line })) {
                    let _ = app.emit("prepare", json!({ "id": id, "progress": progress }));
                }
            }
        }
        tracked.wait();
        let code = tracked.exit_code().map(|c| json!(c)).unwrap_or(Value::Null);
        let end = host.core.ask("prepare.end", json!({ "id": id, "code": code })).unwrap_or_else(|e| json!({ "done": false, "message": e }));
        host.playing().preparing = None;
        let _ = app.emit("prepare", json!({ "id": id, "end": end }));
    });
    Ok(())
}

/// Asks the public services about these games, one after the other; `front` before the ones that wait.
#[tauri::command]
fn online_look(host: State<'_, Arc<Host>>, ids: Vec<String>, front: bool) {
    host.online.want(ids, front);
}

/// Results for a name the player typed.
#[tauri::command(async)]
fn online_search(host: State<'_, Arc<Host>>, id: String, text: String) -> Result<Value, String> {
    host.online.run(&host, json!({ "id": id, "want": "choices", "text": text }))
}

/// The result the player chose.
#[tauri::command(async)]
fn online_pick(host: State<'_, Arc<Host>>, id: String, choice: Value) -> Result<Value, String> {
    host.online.run(&host, json!({ "id": id, "appID": choice["appID"], "item": choice["item"] }))
}

/// Opens a project's page or a licence in the player's browser: https only, and only what the app itself lists.
#[tauri::command(async)]
fn open_link(host: State<'_, Arc<Host>>, url: String) -> Result<(), String> {
    let own = ["https://github.com/sofianbll/oort-nx", "https://github.com/sofianbll/oort-nx/releases", "https://github.com/elripalda/RecompLauncher-SDK", "https://github.com/ddoinn/padwake"];
    let known = own.contains(&url.as_str());
    if !known && !host.core.ask("game.link", json!({ "url": url })).is_ok_and(|v| v == json!(true)) {
        return Err("link".into());
    }
    open(&url)
}

#[tauri::command(async)]
fn open_folder(host: State<'_, Arc<Host>>, id: String, name: Option<String>) -> Result<(), String> {
    let path = host.core.ask("game.folder", json!({ "id": id, "name": name }))?;
    let path = path.as_str().ok_or("folder-missing")?;
    if !Path::new(path).is_dir() {
        return Err("folder-missing".into());
    }
    open(path)
}

fn open(target: &str) -> Result<(), String> {
    #[cfg(windows)]
    let mut cmd = Command::new("explorer.exe");
    #[cfg(target_os = "macos")]
    let mut cmd = Command::new("/usr/bin/open");
    #[cfg(all(unix, not(target_os = "macos")))]
    let mut cmd = Command::new("xdg-open");
    cmd.arg(target).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    let mut child = cmd.spawn().map_err(|e| e.to_string())?;
    std::thread::spawn(move || child.wait());
    Ok(())
}

#[tauri::command]
fn set_fullscreen(window: tauri::WebviewWindow, on: bool) -> Result<(), String> {
    window.set_fullscreen(on).map_err(|e| e.to_string())
}

#[tauri::command]
fn pads(host: State<'_, Arc<Host>>) -> Vec<String> {
    host.pads.lock().unwrap_or_else(|e| e.into_inner()).clone()
}

fn named(app: &AppHandle, names: Vec<String>) {
    let host = app.state::<Arc<Host>>();
    *host.pads.lock().unwrap_or_else(|e| e.into_inner()) = names.clone();
    let _ = app.emit("pads", names);
}

#[tauri::command]
fn quit(app: AppHandle) {
    app.exit(0);
}

/// What the Power card may offer, in its order. Steam Deck's own game mode keeps every window full screen and in front:
/// there is nothing to change.
fn abilities_of(game_mode: bool) -> Vec<&'static str> {
    if game_mode { vec!["restart", "quit"] } else { vec!["fullscreen", "hide", "restart", "quit"] }
}

#[tauri::command]
fn abilities() -> Vec<&'static str> {
    let set = |name| std::env::var_os(name).is_some_and(|v| !v.is_empty());
    abilities_of(set("GAMESCOPE_WAYLAND_DISPLAY") || std::env::var("XDG_CURRENT_DESKTOP").is_ok_and(|v| v.eq_ignore_ascii_case("gamescope")))
}

#[tauri::command]
fn hide(window: tauri::WebviewWindow) -> Result<(), String> {
    window.minimize().map_err(|e| e.to_string())
}

/// Never while a game runs or gets ready: its play time is being counted, its setup would stop halfway.
#[tauri::command]
fn restart(app: AppHandle, host: State<'_, Arc<Host>>) -> Result<(), String> {
    let busy = { let now = host.playing(); now.game.is_some() || now.preparing.is_some() };
    if busy {
        return Err("already-playing".into());
    }
    app.restart()
}

/// The folder of what games printed, the last launch of each.
#[tauri::command(async)]
fn open_logs(host: State<'_, Arc<Host>>) -> Result<(), String> {
    let folder = host.data.join("logs");
    std::fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
    open(&folder.to_string_lossy())
}

/// `/<game id>/<kind>`: only a picture the core names for that game, and only if it is one.
fn art(host: &Host, path: &str) -> Option<(&'static str, Vec<u8>)> {
    let mut parts = path.trim_start_matches('/').split('/');
    let (id, kind) = (parts.next()?, parts.next()?);
    let file = host.core.ask("game.art", json!({ "id": id, "kind": kind })).ok()?;
    let file = PathBuf::from(file.as_str()?);
    if std::fs::metadata(&file).ok()?.len() > MAX_ART {
        return None;
    }
    let bytes = std::fs::read(&file).ok()?;
    Some((picture(&bytes)?, bytes))
}

fn picture(bytes: &[u8]) -> Option<&'static str> {
    match bytes {
        [0x89, b'P', b'N', b'G', ..] => Some("image/png"),
        [0xff, 0xd8, 0xff, ..] => Some("image/jpeg"),
        [b'R', b'I', b'F', b'F', _, _, _, _, b'W', b'E', b'B', b'P', ..] => Some("image/webp"),
        _ => None,
    }
}

fn system() -> &'static str {
    if cfg!(windows) { "windows" } else if cfg!(target_os = "macos") { "macos" } else { "linux" }
}

/// `OORT_DATA` keeps everything in one folder: a portable copy, or a test.
fn setup(app: &AppHandle) -> Result<Arc<Host>, Box<dyn std::error::Error>> {
    let paths = app.path();
    let data = match std::env::var_os("OORT_DATA") {
        Some(p) => PathBuf::from(p),
        None => paths.app_local_data_dir()?,
    };
    std::fs::create_dir_all(&data)?;
    let exe = std::env::current_exe()?;
    let program = exe.with_file_name(if cfg!(windows) { "oort-core.exe" } else { "oort-core" });
    let text = |p: PathBuf| p.to_string_lossy().into_owned();
    let mut args = Vec::new();
    for (name, value) in [
        ("--data", Some(text(data.clone()))),
        ("--system", Some(system().to_string())),
        ("--home", paths.home_dir().ok().map(text)),
        ("--documents", paths.document_dir().ok().map(text)),
        ("--local", paths.local_data_dir().ok().map(text)),
        ("--config", paths.config_dir().ok().map(text)),
        ("--languages", Some(languages())),
    ] {
        if let Some(value) = value {
            args.extend([name.to_string(), value]);
        }
    }
    Ok(Arc::new(Host { core: Companion::new(program, args), data, playing: Mutex::default(), online: Arc::default(), pads: Mutex::default(), aside: AtomicBool::default() }))
}

fn languages() -> String {
    if let Ok(forced) = std::env::var("OORT_LANGUAGE") {
        return forced;
    }
    environment_language().unwrap_or_default()
}

/// The language of the environment, on Linux; elsewhere the page sends the system's with `hello`.
fn environment_language() -> Option<String> {
    ["LC_ALL", "LC_MESSAGES", "LANG"].iter().find_map(|n| std::env::var(n).ok()).filter(|l| l != "C" && l != "POSIX").map(|l| l.split('.').next().unwrap_or("").replace('_', "-"))
}

pub fn run() {
    let app = tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            core, launch, close_game, prepare, open_link, open_folder, set_fullscreen, pads, quit, abilities, hide, restart, open_logs, online_look, online_search, online_pick,
            #[cfg(all(debug_assertions, target_os = "macos"))]
            probe::shot,
            #[cfg(all(debug_assertions, target_os = "macos"))]
            probe::report
        ])
        .register_asynchronous_uri_scheme_protocol("oort-art", |ctx, request, responder| {
            let app = ctx.app_handle().clone();
            std::thread::spawn(move || {
                let host = app.state::<Arc<Host>>();
                let found = art(&host, request.uri().path());
                let reply = match found {
                    Some((kind, bytes)) => tauri::http::Response::builder().header("Content-Type", kind).header("Cache-Control", "max-age=60").body(bytes),
                    None => tauri::http::Response::builder().status(404).body(Vec::new()),
                };
                if let Ok(reply) = reply {
                    responder.respond(reply);
                }
            });
        })
        .setup(|app| {
            let handle = app.handle().clone();
            let host = setup(&handle)?;
            app.manage(host.clone());
            find_steam(&host);
            host.online.clone().work(host.clone(), handle.clone());
            let view = host.core.ask("view", json!({})).unwrap_or(Value::Null);
            let window = WebviewWindowBuilder::from_config(&handle, &handle.config().app.windows[0])?;
            #[cfg(all(debug_assertions, target_os = "macos"))]
            let window = probe::prepare(window);
            let window = window.build()?;
            if view["fullscreen"] == json!(true) {
                let _ = window.set_fullscreen(true);
            }
            // WebKitGTK has no Gamepad API; elsewhere the page reads the controller itself.
            if cfg!(target_os = "linux") || std::env::var_os("OORT_PAD").is_some() {
                let names = handle.clone();
                pad::run(
                    move |state| {
                        let focused = handle.get_webview_window("main").is_some_and(|w| w.is_focused().unwrap_or(false));
                        if focused {
                            let _ = handle.emit("pad", state);
                        }
                    },
                    move |list| named(&names, list),
                );
                return Ok(());
            }
            #[cfg(windows)]
            pad::watch(move |list| named(&handle, list));
            Ok(())
        })
        .build(tauri::generate_context!());
    match app {
        Ok(app) => app.run(|_, _| {}),
        Err(e) => {
            eprintln!("oort: {e}");
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn power_offers_what_this_system_does_and_quit_is_last() {
        for game_mode in [false, true] {
            assert_eq!(abilities_of(game_mode).last(), Some(&"quit"));
        }
        assert!(!abilities_of(true).contains(&"fullscreen"));
    }

    #[test]
    fn only_pictures_are_served() {
        assert_eq!(picture(b"\x89PNG\r\n"), Some("image/png"));
        assert_eq!(picture(b"RIFF\0\0\0\0WEBPVP8 "), Some("image/webp"));
        assert_eq!(picture(b"<svg onload=x>"), None);
        assert_eq!(picture(b""), None);
    }

    #[test]
    fn a_plan_becomes_a_command() {
        let plan = json!({ "program": "/g/run", "args": ["--a", "b c"], "env": { "X": "1" }, "directory": "/g" });
        let cmd = command(&plan).unwrap();
        assert_eq!(cmd.get_args().collect::<Vec<_>>(), ["--a", "b c"]);
        assert_eq!(cmd.get_current_dir(), Some(Path::new("/g")));
        assert!(command(&json!({ "args": [] })).is_err());
    }
}
