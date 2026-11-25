//! Debug builds on a Mac only: a scripted walk through the real window, for the proofs in desktop/proof.
//! `OORT_PROBE` names a script run in the page; it may ask for a picture of the page and write one report line.

use block2::RcBlock;
use objc2_app_kit::NSImage;
use objc2_foundation::NSError;
use objc2_web_kit::WKWebView;
use std::sync::mpsc::channel;
use std::time::Duration;
use tauri::{Manager, Wry};

pub fn prepare<'a, M: Manager<Wry>>(mut window: tauri::WebviewWindowBuilder<'a, Wry, M>) -> tauri::WebviewWindowBuilder<'a, Wry, M> {
    if let Some((w, h)) = std::env::var("OORT_SIZE").ok().and_then(|s| s.split_once('x').and_then(|(w, h)| Some((w.parse().ok()?, h.parse().ok()?)))) {
        window = window.inner_size(w, h).min_inner_size(200.0, 200.0).decorations(false);
    }
    if let Some(script) = std::env::var_os("OORT_PROBE").and_then(|p| std::fs::read_to_string(p).ok()) {
        window = window.initialization_script(script);
    }
    window
}

/// The page as WKWebView draws it, as a TIFF.
#[tauri::command(async)]
pub fn shot(window: tauri::WebviewWindow, path: String) -> Result<(), String> {
    std::env::var_os("OORT_PROBE").ok_or("probe")?;
    let (tx, rx) = channel();
    window
        .with_webview(move |view| unsafe {
            let view = &*(view.inner() as *const WKWebView);
            let done = RcBlock::new(move |image: *mut NSImage, _: *mut NSError| {
                let bytes = image.as_ref().and_then(|i| i.TIFFRepresentation()).map(|d| d.to_vec());
                let _ = tx.send(bytes);
            });
            view.takeSnapshotWithConfiguration_completionHandler(None, &done);
        })
        .map_err(|e| e.to_string())?;
    let bytes = rx.recv_timeout(Duration::from_secs(10)).ok().flatten().ok_or("no picture")?;
    std::fs::write(path, bytes).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn report(line: String) {
    if std::env::var_os("OORT_PROBE").is_some() {
        println!("PROBE {line}");
    }
}
