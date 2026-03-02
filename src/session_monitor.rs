/// 세션 모니터
/// 주기적으로 현재 세션 상태를 확인하고, 버전 체크를 수행합니다.
/// Flutter에서 저장한 인증 정보(LocalConfig)를 사용하여 API 요청을 보냅니다.

use crate::hbbs_http::create_http_client_with_url;
use hbb_common::{config::LocalConfig, log};
use std::time::Duration;

const CHECK_INTERVAL: Duration = Duration::from_secs(60 * 3); // 3분

/// 세션 모니터 시작 (별도 스레드)
/// 시작 시 즉시 한번 실행 후 3분 간격으로 반복
pub fn start_session_monitor() {
    std::thread::spawn(|| {
        log::info!("[SessionMonitor] Started");

        loop {
            if let Err(e) = check_session() {
                log::debug!("[SessionMonitor] Session check error: {}", e);
            }
            if let Err(e) = check_version() {
                log::debug!("[SessionMonitor] Version check error: {}", e);
            }
            std::thread::sleep(CHECK_INTERVAL);
        }
    });
}

/// LocalConfig에서 인증 정보 읽기
struct AuthInfo {
    api_server: String,
    cookie: String,
    user_agent: String,
    device_key: String,
    session_key: String,
}

fn get_auth_info() -> Option<AuthInfo> {
    let api_server = LocalConfig::get_option_from_file("api_server_url");
    let cookie = LocalConfig::get_option_from_file("auth_cookie");
    let user_agent = LocalConfig::get_option_from_file("auth_user_agent");
    let device_key = LocalConfig::get_option_from_file("device_key");
    let session_key = LocalConfig::get_option_from_file("session_key");

    if api_server.is_empty() || cookie.is_empty() || session_key.is_empty() {
        return None; // 로그인 상태가 아님
    }

    Some(AuthInfo {
        api_server,
        cookie,
        user_agent,
        device_key,
        session_key,
    })
}

/// 현재 세션 상태 확인
fn check_session() -> Result<(), Box<dyn std::error::Error>> {
    let auth = match get_auth_info() {
        Some(a) => a,
        None => return Ok(()), // 로그인 안 된 상태, 무시
    };

    let url = format!(
        "{}/api/devices/sessions/status/me/current",
        auth.api_server
    );
    let client = create_http_client_with_url(&url);

    let body = serde_json::json!({
        "deviceKey": auth.device_key,
        "sessionKey": auth.session_key,
    });

    let response = client
        .post(&url)
        .header("Content-Type", "application/json")
        .header("Accept", "application/json")
        .header("Cookie", &auth.cookie)
        .header("User-Agent", &auth.user_agent)
        .body(body.to_string())
        .send()?;

    let status_code = response.status();
    let resp_text = response.text()?;

    log::debug!(
        "[SessionMonitor] Session check response ({}): {}",
        status_code,
        &resp_text
    );

    // 응답 파싱
    if let Ok(json) = serde_json::from_str::<serde_json::Value>(&resp_text) {
        // result.status 필드 확인
        let session_status = json
            .get("result")
            .and_then(|r| r.get("status"))
            .and_then(|s| s.as_str())
            .unwrap_or("");

        if session_status == "KILLED" {
            log::warn!("[SessionMonitor] Session KILLED - another device logged in");
            // Flutter GUI는 별도 프로세스이므로 push_global_event 사용 불가.
            // Flutter 측에서 직접 API를 호출하여 세션 상태를 확인합니다.
        }
    }

    Ok(())
}

/// 버전 체크
fn check_version() -> Result<(), Box<dyn std::error::Error>> {
    let auth = match get_auth_info() {
        Some(a) => a,
        None => return Ok(()),
    };

    let url = format!(
        "{}/api/devices/version/update/check",
        auth.api_server
    );
    let client = create_http_client_with_url(&url);

    let body = serde_json::json!({
        "currentVersion": crate::VERSION,
    });

    let response = client
        .post(&url)
        .header("Content-Type", "application/json")
        .header("Accept", "application/json")
        .header("Cookie", &auth.cookie)
        .header("User-Agent", &auth.user_agent)
        .body(body.to_string())
        .send()?;

    let resp_text = response.text()?;

    log::info!(
        "[SessionMonitor] Version check response: {}",
        &resp_text
    );

    if let Ok(json) = serde_json::from_str::<serde_json::Value>(&resp_text) {
        let server_version = json
            .get("result")
            .and_then(|r| r.get("version"))
            .and_then(|v| v.as_str())
            .unwrap_or("");

        if !server_version.is_empty() && server_version != crate::VERSION {
            log::info!(
                "[SessionMonitor] New version available: {} (current: {})",
                server_version,
                crate::VERSION
            );

            // Flutter GUI는 별도 프로세스이므로 push_global_event 사용 불가.
            // Flutter 측에서 직접 API를 호출하여 버전을 확인합니다.
        }
    }

    Ok(())
}

/// 서비스 종료 시 로그아웃 처리 (자동 로그인이 아닌 경우)
pub fn logout_on_quit() {
    let auto_login = LocalConfig::get_option_from_file("auto_login");
    if auto_login == "Y" {
        log::info!("[SessionMonitor] Auto-login enabled, skipping logout on quit");
        return;
    }

    let auth = match get_auth_info() {
        Some(a) => a,
        None => {
            log::info!("[SessionMonitor] No auth info, skipping logout on quit");
            return;
        }
    };

    // 세션 종료
    let end_url = format!("{}/api/devices/sessions/end", auth.api_server);
    let client = create_http_client_with_url(&end_url);
    let body = serde_json::json!({ "sessionKey": auth.session_key });
    match client
        .post(&end_url)
        .header("Content-Type", "application/json")
        .header("Cookie", &auth.cookie)
        .header("User-Agent", &auth.user_agent)
        .body(body.to_string())
        .send()
    {
        Ok(resp) => log::info!("[SessionMonitor] End session on quit: {}", resp.status()),
        Err(e) => log::debug!("[SessionMonitor] End session on quit error: {}", e),
    }

    // 로그아웃
    let logout_url = format!("{}/api/auth/logout", auth.api_server);
    let client2 = create_http_client_with_url(&logout_url);
    match client2
        .post(&logout_url)
        .header("Content-Type", "application/json")
        .header("Cookie", &auth.cookie)
        .header("User-Agent", &auth.user_agent)
        .send()
    {
        Ok(resp) => log::info!("[SessionMonitor] Logout on quit: {}", resp.status()),
        Err(e) => log::debug!("[SessionMonitor] Logout on quit error: {}", e),
    }

    // 로컬 인증 데이터 정리
    LocalConfig::set_option("access_token".to_string(), "".to_string());
    LocalConfig::set_option("user_info".to_string(), "".to_string());
    LocalConfig::set_option("auth_cookie".to_string(), "".to_string());
    LocalConfig::set_option("session_key".to_string(), "".to_string());
    LocalConfig::set_option("device_key".to_string(), "".to_string());

    log::info!("[SessionMonitor] Logout on quit completed");
}

/// 플랫폼별 다운로드 URL 추출
fn get_platform_download_url(json: &serde_json::Value) -> String {
    let result = match json.get("result") {
        Some(r) => r,
        None => return String::new(),
    };

    #[cfg(target_os = "windows")]
    let key = "winDownloadUrl";
    #[cfg(target_os = "macos")]
    let key = "macDownloadUrl";
    #[cfg(target_os = "linux")]
    let key = "linuxDownloadUrl";
    #[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
    let key = "";

    if key.is_empty() {
        return String::new();
    }

    result
        .get(key)
        .and_then(|u| u.as_str())
        .unwrap_or("")
        .to_string()
}
