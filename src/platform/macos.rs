// https://developer.apple.com/documentation/appkit/nscursor
// https://github.com/servo/core-foundation-rs
// https://github.com/rust-windowing/winit

use super::{CursorData, ResultType};
use cocoa::{
    appkit::{NSApp, NSApplication, NSApplicationActivationPolicy::*},
    base::{id, nil, BOOL, NO, YES},
    foundation::{NSDictionary, NSPoint, NSSize, NSString},
};
use core_foundation::{
    array::{CFArrayGetCount, CFArrayGetValueAtIndex},
    dictionary::CFDictionaryRef,
    string::CFStringRef,
};
use core_graphics::{
    display::{kCGNullWindowID, kCGWindowListOptionOnScreenOnly, CGWindowListCopyWindowInfo},
    window::{kCGWindowName, kCGWindowOwnerPID},
};
use hbb_common::{
    anyhow::anyhow,
    bail, log,
    message_proto::{DisplayInfo, Resolution},
    sysinfo::{Pid, Process, ProcessRefreshKind, System},
};
use include_dir::{include_dir, Dir};
use objc::rc::autoreleasepool;
use objc::{class, msg_send, sel, sel_impl};
use scrap::{libc::c_void, quartz::ffi::*};
use std::{
    collections::HashMap,
    os::unix::process::CommandExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

static PRIVILEGES_SCRIPTS_DIR: Dir =
    include_dir!("$CARGO_MANIFEST_DIR/src/platform/privileges_scripts");
static mut LATEST_SEED: i32 = 0;

// Using a fixed temporary directory for updates is preferable to
// using one that includes the custom client name.
const UPDATE_TEMP_DIR: &str = "/tmp/.onedeskupdate";

extern "C" {
    fn CGSCurrentCursorSeed() -> i32;
    fn CGEventCreate(r: *const c_void) -> *const c_void;
    fn CGEventGetLocation(e: *const c_void) -> CGPoint;
    static kAXTrustedCheckOptionPrompt: CFStringRef;
    fn AXIsProcessTrustedWithOptions(options: CFDictionaryRef) -> BOOL;
    fn InputMonitoringAuthStatus(_: BOOL) -> BOOL;
    fn IsCanScreenRecording(_: BOOL) -> BOOL;
    fn CanUseNewApiForScreenCaptureCheck() -> BOOL;
    fn MacCheckAdminAuthorization() -> BOOL;
    fn MacGetModeNum(display: u32, numModes: *mut u32) -> BOOL;
    fn MacGetModes(
        display: u32,
        widths: *mut u32,
        heights: *mut u32,
        hidpis: *mut BOOL,
        max: u32,
        numModes: *mut u32,
    ) -> BOOL;
    fn majorVersion() -> u32;
    fn MacGetMode(display: u32, width: *mut u32, height: *mut u32) -> BOOL;
    fn MacSetMode(display: u32, width: u32, height: u32, tryHiDPI: bool) -> BOOL;
}

pub fn major_version() -> u32 {
    unsafe { majorVersion() }
}

pub fn is_process_trusted(prompt: bool) -> bool {
    autoreleasepool(|| unsafe_is_process_trusted(prompt))
}

fn unsafe_is_process_trusted(prompt: bool) -> bool {
    unsafe {
        let value = if prompt { YES } else { NO };
        let value: id = msg_send![class!(NSNumber), numberWithBool: value];
        let options = NSDictionary::dictionaryWithObject_forKey_(
            nil,
            value,
            kAXTrustedCheckOptionPrompt as _,
        );
        AXIsProcessTrustedWithOptions(options as _) == YES
    }
}

pub fn is_can_input_monitoring(prompt: bool) -> bool {
    unsafe {
        let value = if prompt { YES } else { NO };
        InputMonitoringAuthStatus(value) == YES
    }
}

pub fn is_can_screen_recording(prompt: bool) -> bool {
    autoreleasepool(|| unsafe_is_can_screen_recording(prompt))
}

// macOS >= 10.15
// https://stackoverflow.com/questions/56597221/detecting-screen-recording-settings-on-macos-catalina/
// remove just one app from all the permissions: tccutil reset All com.carriez.onedesk
fn unsafe_is_can_screen_recording(prompt: bool) -> bool {
    // we got some report that we show no permission even after set it, so we try to use new api for screen recording check
    // the new api is only available on macOS >= 10.15, but on stackoverflow, some people said it works on >= 10.16 (crash on 10.15),
    // but also some said it has bug on 10.16, so we just use it on 11.0.
    unsafe {
        if CanUseNewApiForScreenCaptureCheck() == YES {
            return IsCanScreenRecording(if prompt { YES } else { NO }) == YES;
        }
    }
    let mut can_record_screen: bool = false;
    unsafe {
        let our_pid: i32 = std::process::id() as _;
        let our_pid: id = msg_send![class!(NSNumber), numberWithInteger: our_pid];
        let window_list =
            CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
        let n = CFArrayGetCount(window_list);
        let dock = NSString::alloc(nil).init_str("Dock");
        for i in 0..n {
            let w: id = CFArrayGetValueAtIndex(window_list, i) as _;
            let name: id = msg_send![w, valueForKey: kCGWindowName as id];
            if name.is_null() {
                continue;
            }
            let pid: id = msg_send![w, valueForKey: kCGWindowOwnerPID as id];
            let is_me: BOOL = msg_send![pid, isEqual: our_pid];
            if is_me == YES {
                continue;
            }
            let pid: i32 = msg_send![pid, intValue];
            let p: id = msg_send![
                class!(NSRunningApplication),
                runningApplicationWithProcessIdentifier: pid
            ];
            if p.is_null() {
                // ignore processes we don't have access to, such as WindowServer, which manages the windows named "Menubar" and "Backstop Menubar"
                continue;
            }
            let url: id = msg_send![p, executableURL];
            let exe_name: id = msg_send![url, lastPathComponent];
            if exe_name.is_null() {
                continue;
            }
            let is_dock: BOOL = msg_send![exe_name, isEqual: dock];
            if is_dock == YES {
                // ignore the Dock, which provides the desktop picture
                continue;
            }
            can_record_screen = true;
            break;
        }
    }
    if !can_record_screen && prompt {
        use scrap::{Capturer, Display};
        if let Ok(d) = Display::primary() {
            Capturer::new(d).ok();
        }
    }
    can_record_screen
}

pub fn install_service() -> bool {
    is_installed_daemon(false)
}

/// Try to acquire exclusive GUI lock using flock (atomic, race-free).
/// Returns true if lock acquired, false if another GUI holds it.
/// Lock auto-releases when process exits (OS cleans up fd).
pub fn try_acquire_gui_lock() -> bool {
    use std::os::unix::io::IntoRawFd;
    let Ok(file) = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .open("/tmp/onedesk_gui.lock")
    else {
        return true; // can't create lock, proceed anyway
    };
    let fd = file.into_raw_fd();
    // LOCK_EX | LOCK_NB = exclusive non-blocking
    let result = unsafe { libc::flock(fd, libc::LOCK_EX | libc::LOCK_NB) };
    if result == 0 {
        // Lock acquired. Don't close fd - keeps lock until process exits.
        log::info!("GUI lock acquired (PID {})", std::process::id());
        true
    } else {
        log::info!("Another GUI is already running, exiting");
        unsafe { libc::close(fd); }
        false
    }
}

/// Check if the GUI lock file is held by another process (GUI is running).
/// Does NOT acquire the lock — only checks. Safe to call from --server process.
pub fn is_gui_lock_held() -> bool {
    use std::os::unix::io::AsRawFd;
    let Ok(file) = std::fs::OpenOptions::new()
        .write(true)
        .open("/tmp/onedesk_gui.lock")
    else {
        return false;
    };
    let fd = file.as_raw_fd();
    let result = unsafe { libc::flock(fd, libc::LOCK_EX | libc::LOCK_NB) };
    if result == 0 {
        // We acquired the lock — no GUI is running. Release it immediately.
        unsafe { libc::flock(fd, libc::LOCK_UN) };
        false
    } else {
        // Lock held by another process — GUI is running.
        true
    }
    // file dropped here, fd closed automatically
}

/// Try to auto-start the daemon and agent on app startup.
/// If plist files were removed (e.g. user stopped service), restore them from embedded resources
/// and reload. Always clears stop-service flag.
pub fn try_start_daemon_if_not_running() {
    // Clear stop-service flag in local config.
    hbb_common::config::Config::set_option("stop-service".into(), "".into());

    let full_name = crate::get_full_name();

    // Daemon plist
    let daemon_label = format!("{}_service", full_name);
    let daemon_plist_path = format!("/Library/LaunchDaemons/{}.plist", daemon_label);

    // Agent plist
    let agent_label = format!("{}_server", full_name);
    let agent_plist_path = format!("/Library/LaunchAgents/{}.plist", agent_label);

    let daemon_exists = std::path::Path::new(&daemon_plist_path).exists();
    let agent_exists = std::path::Path::new(&agent_plist_path).exists();

    // Check if the daemon (service) process is already running.
    // launchctl list as regular user cannot see LaunchDaemons (root-level),
    // so use pgrep to check the actual process instead.
    let service_running = std::process::Command::new("pgrep")
        .args(&["-x", "service"])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);

    if service_running {
        log::info!("Daemon service process is already running, skipping admin prompt");
    } else if !daemon_exists || !agent_exists {
        // Plist files missing — reinstall via osascript (shows admin password dialog)
        log::info!("Plist files missing (daemon={}, agent={}), attempting to reinstall", daemon_exists, agent_exists);
        is_installed_daemon(true);
        std::thread::sleep(std::time::Duration::from_secs(3));
    } else {
        // Plist exists but service not running — let launchd handle it (KeepAlive=true).
        // Do NOT prompt admin password on every startup.
        log::info!("Daemon service not running but plist exists, launchd will auto-restart (KeepAlive=true)");
    }

    // Ensure agent is loaded in launchd (for background operation after GUI exits).
    // Do NOT unload+reload — that restarts the agent process, which conflicts with
    // the GUI's in-process server and kills the GUI via IPC Data::Close.
    if std::path::Path::new(&agent_plist_path).exists() {
        let agent_loaded = std::process::Command::new("launchctl")
            .args(&["list", &agent_label])
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false);

        if !agent_loaded {
            log::info!("Agent not loaded in launchd, loading: {}", agent_plist_path);
            let _ = std::process::Command::new("launchctl")
                .args(&["load", "-w", &agent_plist_path])
                .status();
        } else {
            log::info!("Agent {} is already loaded in launchd", agent_label);
        }
    }

    // Notify via IPC to clear stop-service flag.
    // GUI's in-process server should already be running at this point.
    std::thread::sleep(std::time::Duration::from_secs(1));
    crate::ipc::set_option("stop-service", "");
}

// Remember to check if `update_daemon_agent()` need to be changed if changing `is_installed_daemon()`.
// No need to merge the existing dup code, because the code in these two functions are too critical.
// New code should be written in a common function.
pub fn is_installed_daemon(prompt: bool) -> bool {
    let daemon = format!("{}_service.plist", crate::get_full_name());
    let agent = format!("{}_server.plist", crate::get_full_name());
    let agent_plist_file = format!("/Library/LaunchAgents/{}", agent);
    if !prompt {
        // in macos 13, there is new way to check if they are running or enabled, https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos#Respond-to-changes-in-System-Settings
        if !std::path::Path::new(&format!("/Library/LaunchDaemons/{}", daemon)).exists() {
            return false;
        }
        if !std::path::Path::new(&agent_plist_file).exists() {
            return false;
        }
        return true;
    }

    let Some(install_script) = PRIVILEGES_SCRIPTS_DIR.get_file("install.scpt") else {
        return false;
    };
    let Some(install_script_body) = install_script.contents_utf8().map(correct_app_name) else {
        return false;
    };

    let Some(daemon_plist) = PRIVILEGES_SCRIPTS_DIR.get_file("daemon.plist") else {
        return false;
    };
    let Some(daemon_plist_body) = daemon_plist.contents_utf8().map(correct_app_name) else {
        return false;
    };

    let Some(agent_plist) = PRIVILEGES_SCRIPTS_DIR.get_file("agent.plist") else {
        return false;
    };
    let Some(agent_plist_body) = agent_plist.contents_utf8().map(correct_app_name) else {
        return false;
    };

    std::thread::spawn(move || {
        match std::process::Command::new("osascript")
            .arg("-e")
            .arg(install_script_body)
            .arg(daemon_plist_body)
            .arg(agent_plist_body)
            .arg(&get_active_username())
            .status()
        {
            Err(e) => {
                log::error!("run osascript failed: {}", e);
            }
            _ => {
                let installed = std::path::Path::new(&agent_plist_file).exists();
                log::info!("Agent file {} installed: {}", agent_plist_file, installed);
                if installed {
                    log::info!("launch server");
                    std::process::Command::new("launchctl")
                        .args(&["load", "-w", &agent_plist_file])
                        .status()
                        .ok();
                }
            }
        }
    });
    false
}

fn update_daemon_agent(agent_plist_file: String, update_source_dir: String, sync: bool) {
    let update_script_file = "update.scpt";
    let Some(update_script) = PRIVILEGES_SCRIPTS_DIR.get_file(update_script_file) else {
        return;
    };
    let Some(update_script_body) = update_script.contents_utf8().map(correct_app_name) else {
        return;
    };

    let Some(daemon_plist) = PRIVILEGES_SCRIPTS_DIR.get_file("daemon.plist") else {
        return;
    };
    let Some(daemon_plist_body) = daemon_plist.contents_utf8().map(correct_app_name) else {
        return;
    };
    let Some(agent_plist) = PRIVILEGES_SCRIPTS_DIR.get_file("agent.plist") else {
        return;
    };
    let Some(agent_plist_body) = agent_plist.contents_utf8().map(correct_app_name) else {
        return;
    };

    let func = move || {
        let mut binding = std::process::Command::new("osascript");
        let cmd = binding
            .arg("-e")
            .arg(update_script_body)
            .arg(daemon_plist_body)
            .arg(agent_plist_body)
            .arg(&get_active_username())
            .arg(std::process::id().to_string())
            .arg(update_source_dir);
        match cmd.status() {
            Err(e) => {
                log::error!("run osascript failed: {}", e);
            }
            _ => {
                let installed = std::path::Path::new(&agent_plist_file).exists();
                log::info!("Agent file {} installed: {}", &agent_plist_file, installed);
                if installed {
                    // Unload first, or load may not work if already loaded.
                    // We hope that the load operation can immediately trigger a start.
                    std::process::Command::new("launchctl")
                        .args(&["unload", "-w", &agent_plist_file])
                        .stdin(Stdio::null())
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .status()
                        .ok();
                    let status = std::process::Command::new("launchctl")
                        .args(&["load", "-w", &agent_plist_file])
                        .status();
                    log::info!("launch server, status: {:?}", &status);
                }
            }
        }
    };
    if sync {
        func();
    } else {
        std::thread::spawn(func);
    }
}

fn correct_app_name(s: &str) -> String {
    let mut s = s.to_owned();
    if let Some(bundleid) = get_bundle_id() {
        s = s.replace("com.carriez.onedesk", &bundleid);
    }
    s = s.replace("onedesk", &crate::get_app_name().to_lowercase());
    s = s.replace("OneDesk", &crate::get_app_name());
    s
}

pub fn uninstall_service(show_new_window: bool, sync: bool) -> bool {
    // to-do: do together with win/linux about refactory start/stop service
    if !is_installed_daemon(false) {
        return false;
    }

    let Some(script_file) = PRIVILEGES_SCRIPTS_DIR.get_file("uninstall.scpt") else {
        return false;
    };
    let Some(script_body) = script_file.contents_utf8().map(correct_app_name) else {
        return false;
    };

    let func = move || {
        match std::process::Command::new("osascript")
            .arg("-e")
            .arg(script_body)
            .status()
        {
            Err(e) => {
                log::error!("run osascript failed: {}", e);
            }
            _ => {
                let agent = format!("{}_server.plist", crate::get_full_name());
                let agent_plist_file = format!("/Library/LaunchAgents/{}", agent);
                let uninstalled = !std::path::Path::new(&agent_plist_file).exists();
                log::info!(
                    "Agent file {} uninstalled: {}",
                    agent_plist_file,
                    uninstalled
                );
                if uninstalled {
                    if !show_new_window {
                        let _ = crate::ipc::close_all_instances();
                        // leave ipc a little time
                        std::thread::sleep(std::time::Duration::from_millis(300));
                    }
                    crate::ipc::set_option("stop-service", "Y");
                    if show_new_window {
                        std::process::Command::new("open")
                            .arg("-n")
                            .arg(&format!("/Applications/{}.app", crate::get_app_name()))
                            .spawn()
                            .ok();
                        // leave open a little time
                        std::thread::sleep(std::time::Duration::from_millis(300));
                    }
                    // Spawn a fully detached cleanup script using background subshell.
                    // (...)& makes the inner subshell run independently - the outer sh
                    // exits immediately, and the subshell is reparented to PID 1.
                    // This ensures killall survives even after launchctl remove kills --server.
                    let app_name = crate::get_app_name();
                    let full_name = crate::get_full_name();
                    std::process::Command::new("sh")
                        .arg("-c")
                        .arg(&format!(
                            "(launchctl remove {full_name}_server 2>/dev/null; sleep 0.5; killall -9 {app_name} 2>/dev/null; pkill -9 -f {app_name}.app 2>/dev/null) &",
                        ))
                        .stdin(std::process::Stdio::null())
                        .stdout(std::process::Stdio::null())
                        .stderr(std::process::Stdio::null())
                        .spawn()
                        .ok();
                    quit_gui();
                }
            }
        }
    };
    if sync {
        func();
    } else {
        std::thread::spawn(func);
    }
    true
}

pub fn get_cursor_pos() -> Option<(i32, i32)> {
    unsafe {
        let e = CGEventCreate(0 as _);
        let point = CGEventGetLocation(e);
        CFRelease(e);
        Some((point.x as _, point.y as _))
    }
    /*
    let mut pt: NSPoint = unsafe { msg_send![class!(NSEvent), mouseLocation] };
    let screen: id = unsafe { msg_send![class!(NSScreen), currentScreenForMouseLocation] };
    let frame: NSRect = unsafe { msg_send![screen, frame] };
    pt.x -= frame.origin.x;
    pt.y -= frame.origin.y;
    Some((pt.x as _, pt.y as _))
    */
}

pub fn get_focused_display(displays: Vec<DisplayInfo>) -> Option<usize> {
    autoreleasepool(|| unsafe_get_focused_display(displays))
}

fn unsafe_get_focused_display(displays: Vec<DisplayInfo>) -> Option<usize> {
    unsafe {
        let main_screen: id = msg_send![class!(NSScreen), mainScreen];
        let screen: id = msg_send![main_screen, deviceDescription];
        let id: id =
            msg_send![screen, objectForKey: NSString::alloc(nil).init_str("NSScreenNumber")];
        let display_name: u32 = msg_send![id, unsignedIntValue];

        displays
            .iter()
            .position(|d| d.name == display_name.to_string())
    }
}

pub fn get_cursor() -> ResultType<Option<u64>> {
    autoreleasepool(|| unsafe_get_cursor())
}

fn unsafe_get_cursor() -> ResultType<Option<u64>> {
    unsafe {
        let seed = CGSCurrentCursorSeed();
        if seed == LATEST_SEED {
            return Ok(None);
        }
        LATEST_SEED = seed;
    }
    let c = get_cursor_id()?;
    Ok(Some(c.1))
}

pub fn reset_input_cache() {
    unsafe {
        LATEST_SEED = 0;
    }
}

fn get_cursor_id() -> ResultType<(id, u64)> {
    unsafe {
        let c: id = msg_send![class!(NSCursor), currentSystemCursor];
        if c == nil {
            bail!("Failed to call [NSCursor currentSystemCursor]");
        }
        let hotspot: NSPoint = msg_send![c, hotSpot];
        let img: id = msg_send![c, image];
        if img == nil {
            bail!("Failed to call [NSCursor image]");
        }
        let size: NSSize = msg_send![img, size];
        let tif: id = msg_send![img, TIFFRepresentation];
        if tif == nil {
            bail!("Failed to call [NSImage TIFFRepresentation]");
        }
        let rep: id = msg_send![class!(NSBitmapImageRep), imageRepWithData: tif];
        if rep == nil {
            bail!("Failed to call [NSBitmapImageRep imageRepWithData]");
        }
        let rep_size: NSSize = msg_send![rep, size];
        let mut hcursor =
            size.width + size.height + hotspot.x + hotspot.y + rep_size.width + rep_size.height;
        let x = (rep_size.width * hotspot.x / size.width) as usize;
        let y = (rep_size.height * hotspot.y / size.height) as usize;
        for i in 0..2 {
            let mut x2 = x + i;
            if x2 >= rep_size.width as usize {
                x2 = rep_size.width as usize - 1;
            }
            let mut y2 = y + i;
            if y2 >= rep_size.height as usize {
                y2 = rep_size.height as usize - 1;
            }
            let color: id = msg_send![rep, colorAtX:x2 y:y2];
            if color != nil {
                let r: f64 = msg_send![color, redComponent];
                let g: f64 = msg_send![color, greenComponent];
                let b: f64 = msg_send![color, blueComponent];
                let a: f64 = msg_send![color, alphaComponent];
                hcursor += (r + g + b + a) * (255 << i) as f64;
            }
        }
        Ok((c, hcursor as _))
    }
}

pub fn get_cursor_data(hcursor: u64) -> ResultType<CursorData> {
    autoreleasepool(|| unsafe_get_cursor_data(hcursor))
}

// https://github.com/stweil/OSXvnc/blob/master/OSXvnc-server/mousecursor.c
fn unsafe_get_cursor_data(hcursor: u64) -> ResultType<CursorData> {
    unsafe {
        let (c, hcursor2) = get_cursor_id()?;
        if hcursor != hcursor2 {
            bail!("cursor changed");
        }
        let hotspot: NSPoint = msg_send![c, hotSpot];
        let img: id = msg_send![c, image];
        let size: NSSize = msg_send![img, size];
        let reps: id = msg_send![img, representations];
        if reps == nil {
            bail!("Failed to call [NSImage representations]");
        }
        let nreps: usize = msg_send![reps, count];
        if nreps == 0 {
            bail!("Get empty [NSImage representations]");
        }
        let rep: id = msg_send![reps, objectAtIndex: 0];
        /*
        let n: id = msg_send![class!(NSNumber), numberWithFloat:1.0];
        let props: id = msg_send![class!(NSDictionary), dictionaryWithObject:n forKey:NSString::alloc(nil).init_str("NSImageCompressionFactor")];
        let image_data: id = msg_send![rep, representationUsingType:2 properties:props];
        let () = msg_send![image_data, writeToFile:NSString::alloc(nil).init_str("cursor.jpg") atomically:0];
        */
        let mut colors: Vec<u8> = Vec::new();
        colors.reserve((size.height * size.width) as usize * 4);
        // TIFF is rgb colorspace, no need to convert
        // let cs: id = msg_send![class!(NSColorSpace), sRGBColorSpace];
        for y in 0..(size.height as _) {
            for x in 0..(size.width as _) {
                let color: id = msg_send![rep, colorAtX:x as cocoa::foundation::NSInteger y:y as cocoa::foundation::NSInteger];
                // let color: id = msg_send![color, colorUsingColorSpace: cs];
                if color == nil {
                    continue;
                }
                let r: f64 = msg_send![color, redComponent];
                let g: f64 = msg_send![color, greenComponent];
                let b: f64 = msg_send![color, blueComponent];
                let a: f64 = msg_send![color, alphaComponent];
                colors.push((r * 255.) as _);
                colors.push((g * 255.) as _);
                colors.push((b * 255.) as _);
                colors.push((a * 255.) as _);
            }
        }
        Ok(CursorData {
            id: hcursor,
            colors: colors.into(),
            hotx: hotspot.x as _,
            hoty: hotspot.y as _,
            width: size.width as _,
            height: size.height as _,
            ..Default::default()
        })
    }
}

fn get_active_user(t: &str) -> String {
    if let Ok(output) = std::process::Command::new("ls")
        .args(vec![t, "/dev/console"])
        .output()
    {
        for line in String::from_utf8_lossy(&output.stdout).lines() {
            if let Some(n) = line.split_whitespace().nth(2) {
                return n.to_owned();
            }
        }
    }
    "".to_owned()
}

pub fn get_active_username() -> String {
    get_active_user("-l")
}

pub fn get_active_userid() -> String {
    get_active_user("-n")
}

pub fn get_active_user_home() -> Option<PathBuf> {
    let username = get_active_username();
    if !username.is_empty() {
        let home = PathBuf::from(format!("/Users/{}", username));
        if home.exists() {
            return Some(home);
        }
    }
    None
}

pub fn is_prelogin() -> bool {
    get_active_userid() == "0"
}

// https://stackoverflow.com/questions/11505255/osx-check-if-the-screen-is-locked
// No "CGSSessionScreenIsLocked" can be found when macOS is not locked.
//
// `ioreg -n Root -d1` returns `"CGSSessionScreenIsLocked"=Yes`
// `ioreg -n Root -d1 -a` returns
// ```
// ...
//    <key>CGSSessionScreenIsLocked</key>
//    <true/>
// ...
// ```
pub fn is_locked() -> bool {
    match std::process::Command::new("ioreg")
        .arg("-n")
        .arg("Root")
        .arg("-d1")
        .output()
    {
        Ok(output) => {
            let output_str = String::from_utf8_lossy(&output.stdout);
            // Although `"CGSSessionScreenIsLocked"=Yes` was printed on my macOS,
            // I also check `"CGSSessionScreenIsLocked"=true` for better compability.
            output_str.contains("\"CGSSessionScreenIsLocked\"=Yes")
                || output_str.contains("\"CGSSessionScreenIsLocked\"=true")
        }
        Err(e) => {
            log::error!("Failed to query ioreg for the lock state: {}", e);
            false
        }
    }
}

pub fn is_root() -> bool {
    crate::username() == "root"
}

pub fn run_as_user(arg: Vec<&str>) -> ResultType<Option<std::process::Child>> {
    let uid = get_active_userid();
    let cmd = std::env::current_exe()?;
    let mut args = vec!["asuser", &uid, cmd.to_str().unwrap_or("")];
    args.append(&mut arg.clone());
    let task = std::process::Command::new("launchctl").args(args).spawn()?;
    Ok(Some(task))
}

pub fn lock_screen() {
    std::process::Command::new(
        "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
    )
    .arg("-suspend")
    .output()
    .ok();
}

pub fn start_os_service() {
    log::info!("Username: {}", crate::username());
    if let Err(err) = crate::ipc::start("_service") {
        log::error!("Failed to start ipc_service: {}", err);
    }

    /* // mouse/keyboard works in prelogin now with launchctl asuser.
       // below can avoid multi-users logged in problem, but having its own below problem.
       // Not find a good way to start --cm without root privilege (affect file transfer).
       // one way is to start with `launchctl asuser <uid> open -n -a /Applications/OneDesk.app/ --args --cm`,
       // this way --cm is started with the user privilege, but we will have problem to start another OneDesk.app
       // with open in explorer.
        use std::sync::{
            atomic::{AtomicBool, Ordering},
            Arc,
        };
        let running = Arc::new(AtomicBool::new(true));
        let r = running.clone();
        let mut uid = "".to_owned();
        let mut server: Option<std::process::Child> = None;
        if let Err(err) = ctrlc::set_handler(move || {
            r.store(false, Ordering::SeqCst);
        }) {
            println!("Failed to set Ctrl-C handler: {}", err);
        }
        while running.load(Ordering::SeqCst) {
            let tmp = get_active_userid();
            let mut start_new = false;
            if tmp != uid && !tmp.is_empty() {
                uid = tmp;
                log::info!("active uid: {}", uid);
                if let Some(ps) = server.as_mut() {
                    hbb_common::allow_err!(ps.kill());
                }
            }
            if let Some(ps) = server.as_mut() {
                match ps.try_wait() {
                    Ok(Some(_)) => {
                        server = None;
                        start_new = true;
                    }
                    _ => {}
                }
            } else {
                start_new = true;
            }
            if start_new {
                match run_as_user("--server") {
                    Ok(Some(ps)) => server = Some(ps),
                    Err(err) => {
                        log::error!("Failed to start server: {}", err);
                    }
                    _ => { /*no happen*/ }
                }
            }
            std::thread::sleep(std::time::Duration::from_millis(super::SERVICE_INTERVAL));
        }

        if let Some(ps) = server.take().as_mut() {
            hbb_common::allow_err!(ps.kill());
        }
        log::info!("Exit");
    */
}

pub fn toggle_blank_screen(_v: bool) {
    // https://unix.stackexchange.com/questions/17115/disable-keyboard-mouse-temporarily
}

pub fn block_input(_v: bool) -> (bool, String) {
    (true, "".to_owned())
}

pub fn is_installed() -> bool {
    if let Ok(p) = std::env::current_exe() {
        return p
            .to_str()
            .unwrap_or_default()
            .starts_with(&format!("/Applications/{}.app", crate::get_app_name()));
    }
    false
}

pub fn quit_gui() {
    unsafe {
        let () = msg_send!(NSApp(), terminate: nil);
    };
}

#[inline]
pub fn try_remove_temp_update_dir(dir: Option<&str>) {
    let target_path = Path::new(dir.unwrap_or(UPDATE_TEMP_DIR));
    if target_path.exists() {
        std::fs::remove_dir_all(target_path).ok();
    }
}

pub fn update_me() -> ResultType<()> {
    let is_installed_daemon = is_installed_daemon(false);
    let option_stop_service = "stop-service";
    let is_service_stopped = hbb_common::config::option2bool(
        option_stop_service,
        &crate::ui_interface::get_option(option_stop_service),
    );

    let cmd = std::env::current_exe()?;
    // OneDesk.app/Contents/MacOS/OneDesk
    let app_dir = cmd
        .parent()
        .and_then(|p| p.parent())
        .and_then(|p| p.parent())
        .map(|d| d.to_string_lossy().to_string());
    let Some(app_dir) = app_dir else {
        bail!("Unknown app directory of current exe file: {:?}", cmd);
    };

    let app_name = crate::get_app_name();
    if is_installed_daemon && !is_service_stopped {
        let agent = format!("{}_server.plist", crate::get_full_name());
        let agent_plist_file = format!("/Library/LaunchAgents/{}", agent);
        std::process::Command::new("launchctl")
            .args(&["unload", "-w", &agent_plist_file])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .ok();
        update_daemon_agent(agent_plist_file, app_dir, true);
    } else {
        // `kill -9` may not work without "administrator privileges"
        let update_body = format!(
            r#"
do shell script "
pgrep -x '{app_name}' | grep -v {pid} | xargs kill -9 && rm -rf '/Applications/{app_name}.app' && ditto '{app_dir}' '/Applications/{app_name}.app' && chown -R {user}:staff '/Applications/{app_name}.app' && xattr -r -d com.apple.quarantine '/Applications/{app_name}.app'
" with prompt "{app_name} wants to update itself" with administrator privileges
    "#,
            app_name = app_name,
            pid = std::process::id(),
            app_dir = app_dir,
            user = get_active_username()
        );
        match Command::new("osascript")
            .arg("-e")
            .arg(update_body)
            .status()
        {
            Ok(status) if !status.success() => {
                log::error!("osascript execution failed with status: {}", status);
            }
            Err(e) => {
                log::error!("run osascript failed: {}", e);
            }
            _ => {}
        }
    }
    std::process::Command::new("open")
        .arg("-n")
        .arg(&format!("/Applications/{}.app", app_name))
        .spawn()
        .ok();
    // leave open a little time
    std::thread::sleep(std::time::Duration::from_millis(300));
    Ok(())
}

pub fn update_from_dmg(dmg_path: &str) -> ResultType<()> {
    println!("Starting update from DMG: {}", dmg_path);
    extract_dmg(dmg_path, UPDATE_TEMP_DIR)?;
    println!("DMG extracted");
    update_extracted(UPDATE_TEMP_DIR)?;
    println!("Update process started");
    Ok(())
}

pub fn update_to(_file: &str) -> ResultType<()> {
    update_extracted(UPDATE_TEMP_DIR)?;
    Ok(())
}

pub fn extract_update_dmg(file: &str) {
    let mut evt: HashMap<&str, String> =
        HashMap::from([("name", "extract-update-dmg".to_string())]);
    match extract_dmg(file, UPDATE_TEMP_DIR) {
        Ok(_) => {
            log::info!("Extracted dmg file to {}", UPDATE_TEMP_DIR);
        }
        Err(e) => {
            evt.insert("err", e.to_string());
            log::error!("Failed to extract dmg file {}: {}", file, e);
        }
    }
    let evt = serde_json::ser::to_string(&evt).unwrap_or("".to_owned());
    #[cfg(feature = "flutter")]
    crate::flutter::push_global_event(crate::flutter::APP_TYPE_MAIN, evt);
}

fn extract_dmg(dmg_path: &str, target_dir: &str) -> ResultType<()> {
    let mount_point = "/Volumes/OneDeskUpdate";
    let target_path = Path::new(target_dir);

    if target_path.exists() {
        std::fs::remove_dir_all(target_path)?;
    }
    std::fs::create_dir_all(target_path)?;

    let status = Command::new("hdiutil")
        .args(&["attach", "-nobrowse", "-mountpoint", mount_point, dmg_path])
        .status()?;

    if !status.success() {
        bail!("Failed to attach DMG image at {}: {:?}", dmg_path, status);
    }

    struct DmgGuard(&'static str);
    impl Drop for DmgGuard {
        fn drop(&mut self) {
            let _ = Command::new("hdiutil")
                .args(&["detach", self.0, "-force"])
                .status();
        }
    }
    let _guard = DmgGuard(mount_point);

    let app_name = format!("{}.app", crate::get_app_name());
    let src_path = format!("{}/{}", mount_point, app_name);
    let dest_path = format!("{}/{}", target_dir, app_name);

    let copy_status = Command::new("ditto")
        .args(&[&src_path, &dest_path])
        .status()?;

    if !copy_status.success() {
        bail!(
            "Failed to copy application from {} to {}: {:?}",
            src_path,
            dest_path,
            copy_status
        );
    }

    if !Path::new(&dest_path).exists() {
        bail!(
            "Copy operation failed - destination not found at {}",
            dest_path
        );
    }

    Ok(())
}

fn update_extracted(target_dir: &str) -> ResultType<()> {
    let app_name = crate::get_app_name();
    let exe_path = format!(
        "{}/{}.app/Contents/MacOS/{}",
        target_dir, app_name, app_name
    );
    let _child = unsafe {
        if let Err(e) = Command::new(&exe_path)
            .arg("--update")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .pre_exec(|| {
                hbb_common::libc::setsid();
                Ok(())
            })
            .spawn()
        {
            try_remove_temp_update_dir(Some(target_dir));
            bail!(e);
        }
    };
    Ok(())
}

pub fn get_double_click_time() -> u32 {
    // to-do: https://github.com/servo/core-foundation-rs/blob/786895643140fa0ee4f913d7b4aeb0c4626b2085/cocoa/src/appkit.rs#L2823
    500 as _
}

pub fn hide_dock() {
    unsafe {
        NSApp().setActivationPolicy_(NSApplicationActivationPolicyAccessory);
    }
}

#[inline]
#[allow(dead_code)]
fn get_server_start_time_of(p: &Process, path: &Path) -> Option<i64> {
    let cmd = p.cmd();
    if cmd.len() <= 1 {
        return None;
    }
    if &cmd[1] != "--server" {
        return None;
    }
    let Ok(cur) = std::fs::canonicalize(p.exe()) else {
        return None;
    };
    if &cur != path {
        return None;
    }
    Some(p.start_time() as _)
}

#[inline]
#[allow(dead_code)]
fn get_server_start_time(sys: &mut System, path: &Path) -> Option<(i64, Pid)> {
    sys.refresh_processes_specifics(ProcessRefreshKind::new());
    for (_, p) in sys.processes() {
        if let Some(t) = get_server_start_time_of(p, path) {
            return Some((t, p.pid() as _));
        }
    }
    None
}

pub fn handle_application_should_open_untitled_file() {
    hbb_common::log::debug!("icon clicked on finder");
    let x = std::env::args().nth(1).unwrap_or_default();
    if x == "--server" || x == "--cm" || x == "--tray" {
        std::thread::spawn(move || crate::handle_url_scheme("".to_lowercase()));
    }
}

/// Override tao's NSApp delegate to handle applicationShouldHandleReopen.
/// When the user clicks the app in Finder/Launchpad while --server is running,
/// macOS sends a reopen event. We override the delegate method to launch a GUI.
pub fn setup_reopen_handler() {
    unsafe {
        let app: id = msg_send![class!(NSApplication), sharedApplication];
        let delegate: id = msg_send![app, delegate];
        if delegate == nil {
            log::warn!("No NSApp delegate found, skipping reopen handler setup");
            return;
        }
        let cls = (*delegate).class();
        let sel = sel!(applicationShouldHandleReopen:hasVisibleWindows:);

        // Use objc runtime to replace or add the method
        let method: *mut std::ffi::c_void =
            objc::runtime::class_getInstanceMethod(cls, sel) as *mut std::ffi::c_void;
        let imp: objc::runtime::Imp = std::mem::transmute(
            handle_reopen as extern "C" fn(&objc::runtime::Object, objc::runtime::Sel, id, BOOL) -> BOOL
        );
        if !method.is_null() {
            objc::runtime::method_setImplementation(
                method as *mut _,
                imp,
            );
            log::info!("Reopen handler installed on tao delegate");
        } else {
            let types = std::ffi::CString::new("B@:@B").unwrap();
            let added = objc::runtime::class_addMethod(
                cls as *const _ as *mut objc::runtime::Class,
                sel,
                imp,
                types.as_ptr(),
            );
            if added {
                log::info!("Reopen handler added to tao delegate");
            } else {
                log::error!("Failed to add reopen handler");
            }
        }
    }
}

extern "C" fn handle_reopen(
    _this: &objc::runtime::Object,
    _sel: objc::runtime::Sel,
    _app: id,
    _has_visible_windows: BOOL,
) -> BOOL {
    log::info!("applicationShouldHandleReopen triggered, launching GUI");
    std::thread::spawn(|| {
        crate::handle_url_scheme("".to_string());
    });
    NO
}

/// Get all resolutions of the display. The resolutions are:
/// 1. Sorted by width and height in descending order, with duplicates removed.
/// 2. Filtered out if the width is less than 800 (800x600) if there are too many (e.g., >15).
/// 3. Contain HiDPI resolutions and the real resolutions.
///
/// We don't need to distinguish between HiDPI and real resolutions.
/// When the controlling side changes the resolution, it will call `change_resolution_directly()`.
/// `change_resolution_directly()` will try to use the HiDPI resolution first.
/// This is how teamviewer does it for now.
///
/// If we need to distinguish HiDPI and real resolutions, we can add a flag to the `Resolution` struct.
pub fn resolutions(name: &str) -> Vec<Resolution> {
    let mut v = vec![];
    if let Ok(display) = name.parse::<u32>() {
        let mut num = 0;
        unsafe {
            if YES == MacGetModeNum(display, &mut num) {
                let (mut widths, mut heights, mut _hidpis) =
                    (vec![0; num as _], vec![0; num as _], vec![NO; num as _]);
                let mut real_num = 0;
                if YES
                    == MacGetModes(
                        display,
                        widths.as_mut_ptr(),
                        heights.as_mut_ptr(),
                        _hidpis.as_mut_ptr(),
                        num,
                        &mut real_num,
                    )
                {
                    if real_num <= num {
                        v = (0..real_num)
                            .map(|i| Resolution {
                                width: widths[i as usize] as _,
                                height: heights[i as usize] as _,
                                ..Default::default()
                            })
                            .collect::<Vec<_>>();
                        // Sort by (w, h), desc
                        v.sort_by(|a, b| {
                            if a.width == b.width {
                                b.height.cmp(&a.height)
                            } else {
                                b.width.cmp(&a.width)
                            }
                        });
                        // Remove duplicates
                        v.dedup_by(|a, b| a.width == b.width && a.height == b.height);
                        // Filter out the ones that are less than width 800 (800x600) if there are too many.
                        // We can also do this filtering on the client side, but it is better not to change the client side to reduce the impact.
                        if v.len() > 15 {
                            // Most width > 800, so it's ok to remove the small ones.
                            v.retain(|r| r.width >= 800);
                        }
                        if v.len() > 15 {
                            // Ignore if the length is still too long.
                        }
                    }
                }
            }
        }
    }
    v
}

pub fn current_resolution(name: &str) -> ResultType<Resolution> {
    let display = name.parse::<u32>().map_err(|e| anyhow!(e))?;
    unsafe {
        let (mut width, mut height) = (0, 0);
        if NO == MacGetMode(display, &mut width, &mut height) {
            bail!("MacGetMode failed");
        }
        Ok(Resolution {
            width: width as _,
            height: height as _,
            ..Default::default()
        })
    }
}

pub fn change_resolution_directly(name: &str, width: usize, height: usize) -> ResultType<()> {
    let display = name.parse::<u32>().map_err(|e| anyhow!(e))?;
    unsafe {
        if NO == MacSetMode(display, width as _, height as _, true) {
            bail!("MacSetMode failed");
        }
    }
    Ok(())
}

pub fn check_super_user_permission() -> ResultType<bool> {
    unsafe { Ok(MacCheckAdminAuthorization() == YES) }
}

pub fn elevate(args: Vec<&str>, prompt: &str) -> ResultType<bool> {
    let cmd = std::env::current_exe()?;
    match cmd.to_str() {
        Some(cmd) => {
            let mut cmd_with_args = cmd.to_string();
            for arg in args {
                cmd_with_args = format!("{} {}", cmd_with_args, arg);
            }
            let script = format!(
                r#"do shell script "{}" with prompt "{}" with administrator privileges"#,
                cmd_with_args, prompt
            );
            match std::process::Command::new("osascript")
                .arg("-e")
                .arg(script)
                .arg(&get_active_username())
                .status()
            {
                Err(e) => {
                    bail!("Failed to run osascript: {}", e);
                }
                Ok(status) => Ok(status.success() && status.code() == Some(0)),
            }
        }
        None => {
            bail!("Failed to get current exe str");
        }
    }
}

pub struct WakeLock(Option<keepawake::AwakeHandle>);

impl WakeLock {
    pub fn new(display: bool, idle: bool, sleep: bool) -> Self {
        WakeLock(
            keepawake::Builder::new()
                .display(display)
                .idle(idle)
                .sleep(sleep)
                .create()
                .ok(),
        )
    }

    pub fn set_display(&mut self, display: bool) -> ResultType<()> {
        self.0
            .as_mut()
            .map(|h| h.set_display(display))
            .ok_or(anyhow!("no AwakeHandle"))?
    }
}

fn get_bundle_id() -> Option<String> {
    unsafe {
        let bundle: id = msg_send![class!(NSBundle), mainBundle];
        if bundle.is_null() {
            return None;
        }

        let bundle_id: id = msg_send![bundle, bundleIdentifier];
        if bundle_id.is_null() {
            return None;
        }

        let c_str: *const std::os::raw::c_char = msg_send![bundle_id, UTF8String];
        if c_str.is_null() {
            return None;
        }

        let bundle_id_str = std::ffi::CStr::from_ptr(c_str)
            .to_string_lossy()
            .to_string();
        Some(bundle_id_str)
    }
}
