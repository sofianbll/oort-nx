//! Which controllers are plugged in, and their state where the page cannot read one (WebKitGTK has no Gamepad API):
//! gilrs, sent in the same shape. WebView2 reads a controller itself, but only after a button is pressed, so on Windows
//! the names come from the system.

use gilrs::{Axis, Button, Event, EventType, Gilrs};
use serde_json::{json, Value};
use std::time::Duration;

/// The page's own names for the buttons, whatever the controller.
const BUTTONS: [(Button, &str); 17] = [
    (Button::South, "s"), (Button::East, "e"), (Button::West, "w"), (Button::North, "n"),
    (Button::LeftTrigger, "l1"), (Button::RightTrigger, "r1"), (Button::LeftTrigger2, "l2"), (Button::RightTrigger2, "r2"),
    (Button::Select, "minus"), (Button::Start, "plus"), (Button::LeftThumb, "l"), (Button::RightThumb, "r"), (Button::Mode, "h"),
    (Button::DPadUp, "up"), (Button::DPadDown, "down"), (Button::DPadLeft, "left"), (Button::DPadRight, "right"),
];

fn snapshot(name: &str, pressed: impl Fn(Button) -> bool, value: impl Fn(Axis) -> f32) -> Value {
    let buttons: serde_json::Map<String, Value> = BUTTONS.iter().map(|(b, n)| (n.to_string(), json!(pressed(*b)))).collect();
    // gilrs points up with a positive number, the page with a negative one.
    let axes = [value(Axis::LeftStickX), -value(Axis::LeftStickY), value(Axis::RightStickX), -value(Axis::RightStickY)];
    json!({ "name": name, "b": buttons, "ax": axes.map(|v| (v * 100.0).round() / 100.0) })
}

/// How soon a controller just plugged in is named.
#[cfg(windows)]
const LOOK: Duration = Duration::from_secs(2);

/// Windows' own list of controllers, looked at now and then: its names, nothing of what is pressed.
#[cfg(windows)]
pub fn watch(named: impl Fn(Vec<String>) + Send + 'static) {
    std::thread::spawn(move || {
        let mut before = Vec::new();
        loop {
            let now = plugged_in().unwrap_or_default();
            if now != before {
                named(now.clone());
                before = now;
            }
            std::thread::sleep(LOOK);
        }
    });
}

#[cfg(windows)]
fn plugged_in() -> windows::core::Result<Vec<String>> {
    let list = windows::Gaming::Input::RawGameController::RawGameControllers()?;
    (0..list.Size()?).map(|i| Ok(list.GetAt(i)?.DisplayName()?.to_string())).collect()
}

/// Reads until the app ends; `send` gets the state after each change, or null when the controller leaves, and `named`
/// the controllers plugged in.
pub fn run(send: impl Fn(Value) + Send + 'static, named: impl Fn(Vec<String>) + Send + 'static) {
    std::thread::spawn(move || {
        let Ok(mut gilrs) = Gilrs::new() else { return };
        let names = |gilrs: &Gilrs| gilrs.gamepads().map(|(_, pad)| pad.name().to_string()).collect::<Vec<_>>();
        named(names(&gilrs));
        loop {
            let Some(Event { id, event, .. }) = gilrs.next_event_blocking(Some(Duration::from_millis(500))) else { continue };
            if matches!(event, EventType::Connected | EventType::Disconnected) {
                named(names(&gilrs));
            }
            if matches!(event, EventType::Disconnected) {
                send(Value::Null);
                continue;
            }
            let pad = gilrs.gamepad(id);
            send(snapshot(pad.name(), |b| pad.is_pressed(b), |a| pad.value(a)));
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_state_has_the_pages_shape() {
        let v = snapshot("Pad", |b| b == Button::South, |a| if a == Axis::LeftStickY { 1.0 } else { 0.0 });
        assert_eq!(v["b"]["s"], json!(true));
        assert_eq!(v["b"]["e"], json!(false));
        assert_eq!(v["b"].as_object().unwrap().len(), 17);
        assert_eq!(v["ax"][1], json!(-1.0), "up is negative on the page");
    }
}
