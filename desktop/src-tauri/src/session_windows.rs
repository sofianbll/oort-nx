// The processes of one session on Windows.
//
// Taken from Padwake (https://github.com/ddoinn/padwake), app/src-tauri/src/games/session.rs at 91cfdef65abbbfc685814685c32face0fdff6b78.
// Copyright (c) 2026 ddoinn, MIT License (see desktop/NOTICE).
// Changes here: the caller chooses where output goes; `open`, `with_appear`, usage, window lookup and the tests that
// need real windows are left out.

//! A session's processes, without Tauri: the spawned child in a Windows job object, plus processes run from a
//! tracked folder (launcher stubs that relaunch the game outside the job).
//! - Tracking is an OS wait: the job's completion port reports "no active processes". Then the folder is checked
//!   once for processes from it, and those are waited on in turn. The session ends when none remain.
//! - Closing asks first (WM_CLOSE to the session's top-level windows, like their X button), waits, then ends only
//!   processes in the job or whose image is under the folder.

use std::os::windows::io::AsRawHandle;
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{ChildStdout, Command};
use std::time::Duration;
use windows::core::{BOOL, PCWSTR, PWSTR};
use windows::Win32::Foundation::{CloseHandle, HANDLE, STILL_ACTIVE, HWND, INVALID_HANDLE_VALUE, LPARAM, WAIT_TIMEOUT, WPARAM};
use windows::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, Thread32First, Thread32Next, PROCESSENTRY32W,
    TH32CS_SNAPPROCESS, TH32CS_SNAPTHREAD, THREADENTRY32,
};
use windows::Win32::System::JobObjects::{
    AssignProcessToJobObject, CreateJobObjectW, JobObjectAssociateCompletionPortInformation,
    JobObjectBasicAccountingInformation, JobObjectBasicProcessIdList, JobObjectExtendedLimitInformation,
    QueryInformationJobObject, SetInformationJobObject, TerminateJobObject, JOBOBJECT_ASSOCIATE_COMPLETION_PORT,
    JOBOBJECT_BASIC_ACCOUNTING_INFORMATION, JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JOB_OBJECT_LIMIT_BREAKAWAY_OK,
};
use windows::Win32::System::Threading::{
    GetCurrentProcessId, GetExitCodeProcess, OpenProcess, OpenThread, QueryFullProcessImageNameW, ResumeThread, TerminateProcess,
    WaitForMultipleObjects, WaitForSingleObject, CREATE_NO_WINDOW, CREATE_SUSPENDED, INFINITE, PROCESS_NAME_WIN32,
    PROCESS_QUERY_LIMITED_INFORMATION, PROCESS_SYNCHRONIZE, PROCESS_TERMINATE, THREAD_SUSPEND_RESUME,
};
use windows::Win32::System::IO::{CreateIoCompletionPort, GetQueuedCompletionStatus, OVERLAPPED};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindow, GetWindowThreadProcessId, IsWindowVisible, PostMessageW, GW_OWNER, WM_CLOSE,
};

/// JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO (in SystemServices, not worth a feature for one number).
const MSG_ACTIVE_PROCESS_ZERO: u32 = 4;
/// Job messages are notifications Windows may drop, so the waiter also looks at the job's count this often.
const RECHECK: u32 = 60_000;

/// A kernel handle, closed on drop. Handles may be used from any thread.
pub(crate) struct Owned(isize);
unsafe impl Send for Owned {}
unsafe impl Sync for Owned {}
impl Owned {
    fn new(h: HANDLE) -> Self {
        Owned(h.0 as isize)
    }
    pub(crate) fn get(&self) -> HANDLE {
        HANDLE(self.0 as _)
    }
}
impl Drop for Owned {
    fn drop(&mut self) {
        unsafe {
            let _ = CloseHandle(self.get());
        }
    }
}

/// The processes of one session.
pub struct Tracked {
    job: Owned,
    port: Owned,
    /// false if Windows refused to put the child in the job (then the child's own handle is waited on), or there is
    /// no child (`open`)
    in_job: bool,
    /// the spawned child; keeping its handle open keeps its pid from being reused. `None` after `open`.
    child: Option<Owned>,
    /// 0 without a child
    pub pid: u32,
    pub folder: Option<PathBuf>,
}

impl Tracked {
    /// Spawns `cmd` suspended, puts it in a new job and lets it run. Its children join the job by themselves; a child
    /// may break away (some launchers ask to), which the folder check then catches.
    pub fn spawn(cmd: &mut Command, folder: Option<PathBuf>) -> Result<Tracked, String> {
        Tracked::spawn_read(cmd, folder).map(|(tracked, _)| tracked)
    }

    /// `spawn`, with what the program prints when `cmd` pipes it.
    pub fn spawn_read(cmd: &mut Command, folder: Option<PathBuf>) -> Result<(Tracked, Option<ChildStdout>), String> {
        let folder = folder.filter(|f| trackable(f));
        unsafe {
            let job = Owned::new(CreateJobObjectW(None, PCWSTR::null()).map_err(|e| format!("job: {e}"))?);
            let port =
                Owned::new(CreateIoCompletionPort(INVALID_HANDLE_VALUE, None, 0, 1).map_err(|e| format!("port: {e}"))?);
            let assoc = JOBOBJECT_ASSOCIATE_COMPLETION_PORT { CompletionKey: std::ptr::null_mut(), CompletionPort: port.get() };
            set_info(&job, JobObjectAssociateCompletionPortInformation, &assoc)?;
            let mut limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
            // without this a launcher asking CreateProcess to break away would fail to start the game at all
            limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_BREAKAWAY_OK;
            set_info(&job, JobObjectExtendedLimitInformation, &limits)?;

            let mut child = cmd
                // no console flashes up behind the window
                .creation_flags(CREATE_SUSPENDED.0 | CREATE_NO_WINDOW.0)
                .spawn()
                .map_err(|e| e.to_string())?;
            let pid = child.id();
            let process = HANDLE(child.as_raw_handle() as _);
            let in_job = AssignProcessToJobObject(job.get(), process).is_ok();
            resume_threads(pid);
            // keep a handle of our own: Child closes its handle on drop
            let own = OpenProcess(PROCESS_SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
                .map_err(|e| format!("opening {pid}: {e}"))?;
            let output = child.stdout.take();
            drop(child);
            Ok((Tracked::new(job, port, in_job, Some(Owned::new(own)), pid, folder), output))
        }
    }

    fn new(job: Owned, port: Owned, in_job: bool, child: Option<Owned>, pid: u32, folder: Option<PathBuf>) -> Tracked {
        Tracked { job, port, in_job, child, pid, folder }
    }

    /// Blocks until the session is over: the job is empty (or, outside a job, the child has exited) and no process runs
    /// from the folder. An OS wait throughout.
    pub fn wait(&self) {
        loop {
            if self.in_job {
                self.wait_job_empty();
            } else if let Some(child) = &self.child {
                unsafe { WaitForSingleObject(child.get(), INFINITE) };
            }
            let Some(folder) = &self.folder else { return };
            // a launcher stub may have started the game outside the job and exited: wait for those too
            let left = processes_under(folder);
            if left.is_empty() {
                return;
            }
            let handles: Vec<Owned> = left
                .iter()
                .filter_map(|p| unsafe { OpenProcess(PROCESS_SYNCHRONIZE, false, p.pid) }.ok().map(Owned::new))
                .collect();
            if handles.is_empty() {
                return;
            }
            let raw: Vec<HANDLE> = handles.iter().take(64).map(Owned::get).collect();
            unsafe { WaitForMultipleObjects(&raw, true, INFINITE) };
        }
    }

    fn wait_job_empty(&self) {
        loop {
            if self.active_in_job() == 0 {
                return;
            }
            let (mut msg, mut key, mut ov) = (0u32, 0usize, std::ptr::null_mut::<OVERLAPPED>());
            let got = unsafe { GetQueuedCompletionStatus(self.port.get(), &mut msg, &mut key, &mut ov, RECHECK) };
            if got.is_ok() && msg == MSG_ACTIVE_PROCESS_ZERO {
                return;
            }
        }
    }

    fn active_in_job(&self) -> u32 {
        let mut info = JOBOBJECT_BASIC_ACCOUNTING_INFORMATION::default();
        let ok = unsafe {
            QueryInformationJobObject(
                Some(self.job.get()),
                JobObjectBasicAccountingInformation,
                &mut info as *mut _ as _,
                std::mem::size_of_val(&info) as u32,
                None,
            )
        };
        if ok.is_ok() {
            info.ActiveProcesses
        } else {
            0
        }
    }

    /// The spawned process's exit code, once it has exited. A launcher stub's code is the stub's, not the game's; a
    /// game opened by its link (`open`) has none.
    pub fn exit_code(&self) -> Option<i64> {
        let child = self.child.as_ref()?;
        let mut code = 0u32;
        unsafe { GetExitCodeProcess(child.get(), &mut code) }.ok()?;
        (code != STILL_ACTIVE.0 as u32).then_some(i64::from(code))
    }

    /// The pids in the job now.
    pub fn job_pids(&self) -> Vec<u32> {
        if !self.in_job {
            let alive = self.child.as_ref().is_some_and(|c| unsafe { WaitForSingleObject(c.get(), 0) } == WAIT_TIMEOUT);
            return if alive { vec![self.pid] } else { vec![] };
        }
        // a header of two u32s, then one usize per pid
        let mut buf = vec![0usize; 1026];
        let ok = unsafe {
            QueryInformationJobObject(
                Some(self.job.get()),
                JobObjectBasicProcessIdList,
                buf.as_mut_ptr() as _,
                (buf.len() * std::mem::size_of::<usize>()) as u32,
                None,
            )
        };
        if ok.is_err() {
            return vec![];
        }
        let n = buf[0] >> 32; // NumberOfProcessIdsInList, the second u32
        buf[1..=n.min(1025)].iter().map(|&p| p as u32).collect()
    }

    /// Every process of the session now: the job's and the folder's, never this app.
    pub fn pids(&self) -> Vec<u32> {
        let mut pids = self.job_pids();
        if let Some(folder) = &self.folder {
            pids.extend(processes_under(folder).into_iter().map(|p| p.pid));
        }
        let me = unsafe { GetCurrentProcessId() };
        pids.retain(|&p| p != me && p != 0);
        pids.sort_unstable();
        pids.dedup();
        pids
    }

    /// Closes the session like its windows' X buttons: WM_CLOSE to every visible top-level window it owns, then up to
    /// `grace` for its processes to exit, then ends what is left (the job, and processes run from the folder).
    pub fn close(&self, grace: Duration) {
        let pids = self.pids();
        let windows = top_windows(&pids);
        for w in &windows {
            unsafe {
                let _ = PostMessageW(Some(HWND(*w as _)), WM_CLOSE, WPARAM(0), LPARAM(0));
            }
        }
        let handles: Vec<Owned> = pids
            .iter()
            .filter_map(|&p| unsafe { OpenProcess(PROCESS_SYNCHRONIZE, false, p) }.ok().map(Owned::new))
            .collect();
        let raw: Vec<HANDLE> = handles.iter().take(64).map(Owned::get).collect();
        let asked = raw.is_empty()
            || unsafe { WaitForMultipleObjects(&raw, true, grace.as_millis().min(u32::MAX as u128) as u32) } != WAIT_TIMEOUT;
        if !asked {
            if self.in_job {
                unsafe {
                    let _ = TerminateJobObject(self.job.get(), 1);
                }
            } else if self.child.as_ref().is_some_and(|c| unsafe { WaitForSingleObject(c.get(), 0) } == WAIT_TIMEOUT) {
                if let Ok(h) = unsafe { OpenProcess(PROCESS_TERMINATE, false, self.pid) } {
                    let h = Owned::new(h);
                    let _ = unsafe { TerminateProcess(h.get(), 1) };
                }
            }
            if let Some(folder) = &self.folder {
                end_under(folder);
            }
        }
    }
}

fn set_info<T>(job: &Owned, class: windows::Win32::System::JobObjects::JOBOBJECTINFOCLASS, info: &T) -> Result<(), String> {
    unsafe { SetInformationJobObject(job.get(), class, info as *const T as _, std::mem::size_of::<T>() as u32) }
        .map_err(|e| format!("job settings: {e}"))
}

/// Resumes the threads of a process started suspended (it has one).
fn resume_threads(pid: u32) {
    unsafe {
        let Ok(snap) = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0) else { return };
        let snap = Owned::new(snap);
        let mut t = THREADENTRY32 { dwSize: std::mem::size_of::<THREADENTRY32>() as u32, ..Default::default() };
        let mut more = Thread32First(snap.get(), &mut t).is_ok();
        while more {
            if t.th32OwnerProcessID == pid {
                if let Ok(h) = OpenThread(THREAD_SUSPEND_RESUME, false, t.th32ThreadID) {
                    let h = Owned::new(h);
                    ResumeThread(h.get());
                }
            }
            more = Thread32Next(snap.get(), &mut t).is_ok();
        }
    }
}

// ---------- processes and folders ----------

/// A running process and its image path.
#[derive(Debug, Clone, PartialEq)]
pub struct Proc {
    pub pid: u32,
    pub image: PathBuf,
}

/// Every process whose image path can be read (most can, with limited query rights), except this app.
pub fn processes() -> Vec<Proc> {
    let me = unsafe { GetCurrentProcessId() };
    let mut out = Vec::new();
    unsafe {
        let Ok(snap) = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) else { return out };
        let snap = Owned::new(snap);
        let mut e = PROCESSENTRY32W { dwSize: std::mem::size_of::<PROCESSENTRY32W>() as u32, ..Default::default() };
        let mut more = Process32FirstW(snap.get(), &mut e).is_ok();
        while more {
            let pid = e.th32ProcessID;
            if pid != 0 && pid != 4 && pid != me {
                if let Ok(h) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) {
                    let h = Owned::new(h);
                    if let Some(image) = image_of(h.get()) {
                        out.push(Proc { pid, image });
                    }
                }
            }
            more = Process32NextW(snap.get(), &mut e).is_ok();
        }
    }
    out
}

fn image_of(h: HANDLE) -> Option<PathBuf> {
    let mut buf = [0u16; 1024];
    let mut len = buf.len() as u32;
    unsafe { QueryFullProcessImageNameW(h, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len) }.ok()?;
    Some(PathBuf::from(String::from_utf16_lossy(&buf[..len as usize])))
}

pub fn processes_under(folder: &Path) -> Vec<Proc> {
    select_under(processes(), folder)
}

/// The processes whose image is inside `folder` (at any depth).
pub fn select_under(all: Vec<Proc>, folder: &Path) -> Vec<Proc> {
    all.into_iter().filter(|p| is_under(&p.image, folder)).collect()
}

/// True if `image` is inside `folder`: compared case-insensitively, component by component, so `Games\Hades` does
/// not take `Games\Hades II`.
pub fn is_under(image: &Path, folder: &Path) -> bool {
    let norm = |p: &Path| {
        let s = p.to_string_lossy().replace('/', "\\").to_lowercase();
        let s = s.strip_prefix(r"\\?\").map(str::to_string).unwrap_or(s);
        s.trim_end_matches('\\').to_string()
    };
    let (image, folder) = (norm(image), norm(folder));
    !folder.is_empty() && image.len() > folder.len() + 1 && image.starts_with(&folder) && image[folder.len()..].starts_with('\\')
}

/// A folder is only tracked if it is a real game folder: never a drive root, where "processes from the folder" would be
/// everything on the drive.
pub fn trackable(folder: &Path) -> bool {
    use std::path::Component;
    folder.is_absolute() && folder.components().filter(|c| matches!(c, Component::Normal(_))).count() >= 1
}

/// Ends the processes run from `folder` (re-checking each one's image after opening it, in case its pid was reused).
fn end_under(folder: &Path) {
    for p in processes_under(folder) {
        let Ok(h) = (unsafe { OpenProcess(PROCESS_TERMINATE | PROCESS_QUERY_LIMITED_INFORMATION, false, p.pid) }) else {
            continue;
        };
        let h = Owned::new(h);
        if image_of(h.get()).is_some_and(|i| is_under(&i, folder)) {
            let _ = unsafe { TerminateProcess(h.get(), 1) };
        }
    }
}

// ---------- windows ----------

/// The visible, unowned top-level windows of `pids`: the ones with an X button a player would press.
pub fn top_windows(pids: &[u32]) -> Vec<isize> {
    struct Find<'a> {
        pids: &'a [u32],
        found: Vec<isize>,
    }
    unsafe extern "system" fn each(hwnd: HWND, lp: LPARAM) -> BOOL {
        let f = unsafe { &mut *(lp.0 as *mut Find) };
        let mut pid = 0;
        unsafe { GetWindowThreadProcessId(hwnd, Some(&mut pid)) };
        if f.pids.contains(&pid)
            && unsafe { IsWindowVisible(hwnd) }.as_bool()
            && unsafe { GetWindow(hwnd, GW_OWNER) }.map_or(true, |o| o.0.is_null())
        {
            f.found.push(hwnd.0 as isize);
        }
        BOOL(1)
    }
    let mut f = Find { pids, found: Vec::new() };
    if !pids.is_empty() {
        unsafe {
            let _ = EnumWindows(Some(each), LPARAM(&mut f as *mut Find as isize));
        }
    }
    f.found
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn folder_matching_is_by_component_and_case_insensitive() {
        let f = Path::new(r"W:\games-test\Hades");
        assert!(is_under(Path::new(r"W:\games-test\Hades\Hades.exe"), f));
        assert!(is_under(Path::new(r"w:\GAMES-TEST\hades\x64\bin\Hades.exe"), f));
        assert!(is_under(Path::new(r"\\?\W:\games-test\Hades\Hades.exe"), f));
        assert!(is_under(Path::new(r"W:\games-test\Hades\Hades.exe"), Path::new(r"W:\games-test\Hades\")));
        assert!(is_under(Path::new("W:/games-test/Hades/Hades.exe"), f));
        // a sibling whose name starts the same is another game
        assert!(!is_under(Path::new(r"W:\games-test\Hades II\Hades2.exe"), f));
        assert!(!is_under(Path::new(r"W:\games-test\Hades"), f), "the folder itself is not a process in it");
        assert!(!is_under(Path::new(r"C:\Windows\explorer.exe"), f));
        assert!(!is_under(Path::new(r"W:\games-test\Hades\x.exe"), Path::new("")));
    }

    #[test]
    fn select_under_keeps_only_the_folder() {
        let p = |pid, s: &str| Proc { pid, image: PathBuf::from(s) };
        let all = vec![
            p(1, r"W:\Games\Celeste\Celeste.exe"),
            p(2, r"W:\Games\Celeste\launcher\stub.exe"),
            p(3, r"W:\Games\Celeste 2\Celeste.exe"),
            p(4, r"C:\Program Files\Steam\steam.exe"),
        ];
        let got: Vec<u32> = select_under(all, Path::new(r"W:\Games\Celeste")).iter().map(|p| p.pid).collect();
        assert_eq!(got, vec![1, 2]);
    }

    #[test]
    fn drive_roots_are_never_tracked() {
        assert!(!trackable(Path::new(r"C:\")));
        assert!(!trackable(Path::new("relative")));
        assert!(trackable(Path::new(r"C:\Games\Hades")));
    }
}
