use crate::service::hub::run_service;

use std::ffi::OsString;

use std::time::Duration;

use tokio::runtime::Runtime;

use windows_service::{
    define_windows_service,
    service::{
        ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus,
        ServiceType,
    },
    service_control_handler::{self, ServiceControlHandlerResult},
    service_dispatcher, Result,
};

// [2026-09-23] 由 FlClashHelperService 改走:嗰个係官方 FlClash 嘅服务名,
// 撞咗两个 App 会抢同一个 root 服务。⚠️ 必须同 `lib/common/constant.dart` 嘅
// `appHelperService` 一致;`legacyFlClashHelperService` 只係用嚟卸载残留。
const SERVICE_NAME: &str = "VogueslyHelperService";

const SERVICE_TYPE: ServiceType = ServiceType::OWN_PROCESS;

pub fn main() -> Result<()> {
    start_service()
}

pub fn start_service() -> Result<()> {
    service_dispatcher::start(SERVICE_NAME, serveice)
}

define_windows_service!(serveice, service_main);

pub fn service_main(_arguments: Vec<OsString>) {
    if let Ok(rt) = Runtime::new() {
        rt.block_on(async {
            let _ = run_windows_service().await;
        });
    }
}
async fn run_windows_service() -> anyhow::Result<()> {
    let status_handle = service_control_handler::register(
        SERVICE_NAME,
        move |event| -> ServiceControlHandlerResult {
            match event {
                ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
                // [0.9.96] 退出前先收埋自己起嘅核心。原本直接 exit(0) ⇒ 核心变孤儿(SYSTEM、session 0),
                //   09-30 实测:用户开住增强模式时覆盖安装新版,安装器 `sc stop` 之后核心仲喺度,
                //   RestartManager 关唔到(Permission Denied + Session Mismatch)⇒ 整个安装 Abort,服务又已经删咗。
                ServiceControl::Stop => {
                    crate::service::hub::stop_internal();
                    std::process::exit(0)
                }
                _ => ServiceControlHandlerResult::NotImplemented,
            }
        },
    )?;

    status_handle.set_service_status(ServiceStatus {
        service_type: SERVICE_TYPE,
        current_state: ServiceState::Running,
        controls_accepted: ServiceControlAccept::STOP,
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 0,
        wait_hint: Duration::default(),
        process_id: None,
    })?;

    run_service().await
}




