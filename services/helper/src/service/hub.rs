use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::VecDeque;
use std::fs::File;
use std::io::{BufRead, Error, Read};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::{io, thread};
use warp::{Filter, Reply};

// [2026-09-23] 由 47890 改走:47890 係官方 FlClash 嘅值,两个 App 同时装就抢同一个
// **root 权限**埠。⚠️ 必须同 `lib/common/constant.dart` 嘅 `helperPort` 一致。
const LISTEN_PORT: u16 = 47893;

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct StartParams {
    pub path: String,
    pub arg: String,
}

/// 核心喺安装目录入面嘅文件名。installer 把所有嘢铺去同一个 `{app}` 目录
/// (`inno_setup.iss`: `Source: "{SOURCE_DIR}\\*"; DestDir: "{app}"`),
/// 所以 helper 同核心**一定同目录**。
fn core_file_name() -> String {
    format!("FlClashCore{}", std::env::consts::EXE_SUFFIX)
}

/// helper **自己**算核心路径,唔再信调用方传上嚟嗰个。
///
/// 🔴 [2026-09-23] 原本 `StartParams.path` 係调用方传,而 hash 闸係唯一防线 ——
/// 闸一破就係「以 helper 权限(Windows SYSTEM)执行任意二进制」。
fn expected_core_path() -> io::Result<PathBuf> {
    let exe = std::env::current_exe()?;
    let dir = exe.parent().ok_or_else(|| {
        Error::new(io::ErrorKind::Other, "helper executable has no parent dir")
    })?;
    Ok(dir.join(core_file_name()))
}

/// 开核心文件,并**锁住唔畀人写 / 删**,之后对**同一个 handle** 算 hash。
///
/// 🔴 [2026-09-23] 原本係 `sha256_file(path)` 按**名**开一次算 hash,
/// 之后 `Command::new(&path).spawn()` **再按名解析一次** —— 两次解析之间
/// 换个文件 / 换条 symlink 就可以绕过 hash 闸(TOCTOU)。
/// Windows 用 `FILE_SHARE_READ`(只准人哋读)⇒ 由算 hash 到 spawn 之间冇人换得走。
#[cfg(windows)]
fn open_core_locked(path: &Path) -> io::Result<File> {
    use std::os::windows::fs::OpenOptionsExt;
    const FILE_SHARE_READ: u32 = 0x0000_0001;
    std::fs::OpenOptions::new()
        .read(true)
        .share_mode(FILE_SHARE_READ)
        .open(path)
}

#[cfg(not(windows))]
fn open_core_locked(path: &Path) -> io::Result<File> {
    // 非 Windows 冇对应嘅 share-mode 语义;helper 本身亦只喺 Windows 行(见 request.dart
    // 嘅 `system.isWindows && checkIsAdmin()` 闸)。呢度只係令佢编译得过。
    File::open(path)
}

fn sha256_reader(mut file: File) -> Result<String, Error> {
    let mut hasher = Sha256::new();
    let mut buffer = [0; 4096];
    loop {
        let bytes_read = file.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

/// 核心嘅 IPC 地址必须係我哋自己嗰个格式,唔准原样掟落 `.arg()`。
///
/// 🔴 [2026-09-23] 原本 `arg` 完全冇校验。格式见 `lib/common/constant.dart`
/// 嘅 `windowsPipeName` = `\\.\pipe\VogueslyCore_<base36 nonce>`。
fn is_allowed_core_address(arg: &str) -> bool {
    const PREFIX: &str = r"\\.\pipe\VogueslyCore_";
    if !arg.starts_with(PREFIX) {
        return false;
    }
    let nonce = &arg[PREFIX.len()..];
    !nonce.is_empty()
        && nonce.len() <= 16
        && nonce.chars().all(|c| c.is_ascii_alphanumeric())
}

static LOGS: Lazy<Arc<Mutex<VecDeque<String>>>> =
    Lazy::new(|| Arc::new(Mutex::new(VecDeque::with_capacity(100))));
static PROCESS: Lazy<Arc<Mutex<Option<std::process::Child>>>> =
    Lazy::new(|| Arc::new(Mutex::new(None)));

/// 当前这次 start 的 session id。只有攞到佢嘅调用方(即係真正启动核心嗰个 App)
/// 先可以 /stop。
///
/// 🔴 [2026-09-23] 原本 `/stop` **无参数、无校验** ⇒ 本机任何一个进程 POST 一下
/// 就杀到核心 ⇒ VPN 静默掉线(而 UI 可能仲显示「已连接」)。
static SESSION: Lazy<Arc<Mutex<Option<String>>>> = Lazy::new(|| Arc::new(Mutex::new(None)));

/// 用已有嘅 sha2 整一个 session id,唔加 `rand` 依赖(唔想为咗一个 id 扩供应链)。
/// 熵来源:纳秒时钟 + 进程 id + 编译期注入嘅核心 hash。
fn new_session_id() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let mut hasher = Sha256::new();
    hasher.update(nanos.to_le_bytes());
    hasher.update(std::process::id().to_le_bytes());
    hasher.update(env!("TOKEN").as_bytes());
    let hex = format!("{:x}", hasher.finalize());
    hex[..32].to_string()
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct StopParams {
    pub session_id: String,
}

fn start(start_params: StartParams) -> impl Reply {
    // 🔴 [2026-09-23] 呢个函数以 **Windows SYSTEM 权限**执行嘢,以下四道闸缺一不可。

    // 闸 1:核心路径由 helper 自己算,调用方传上嚟嗰个只准**完全一致**。
    let expected = match expected_core_path() {
        Ok(p) => p,
        Err(e) => return format!("helper cannot resolve core path: {}", e),
    };
    if Path::new(&start_params.path) != expected.as_path() {
        return format!(
            "refused: core path must be {}",
            expected.to_string_lossy()
        );
    }

    // 闸 2:IPC 地址格式校验(原本原样掟落 .arg())。
    if !is_allowed_core_address(&start_params.arg) {
        return "refused: malformed core address".to_string();
    }

    // 闸 3:开住**锁死**嘅 handle 算 hash —— 由而家到 spawn 之间冇人换得走个文件。
    //       ⚠️ 原本成段 hash 校验畀 `if !cfg!(debug_assertions)` 包住,
    //          即係 **debug build 嘅 helper 执行任何路径、零校验**。而家冇咗个分支。
    let locked = match open_core_locked(&expected) {
        Ok(f) => f,
        Err(e) => return format!("helper cannot open core: {}", e),
    };
    let sha256 = match sha256_reader(locked) {
        Ok(v) => v,
        Err(e) => return format!("helper cannot hash core: {}", e),
    };
    if sha256 != env!("TOKEN") {
        // 唔好把预期值讲返畀调用方(原本 /ping 会吐,已经係另一个洞)。
        return format!(
            "refused: core signature mismatch (got {})",
            &sha256[..sha256.len().min(16)]
        );
    }

    stop_internal();
    let mut process = PROCESS.lock().unwrap();
    match Command::new(&expected)
        .stderr(Stdio::piped())
        .arg(&start_params.arg)
        .spawn()
    {
        Ok(child) => {
            *process = Some(child);
            let sid = new_session_id();
            *SESSION.lock().unwrap() = Some(sid.clone());
            if let Some(ref mut child) = *process {
                let stderr = child.stderr.take().unwrap();
                let reader = io::BufReader::new(stderr);
                thread::spawn(move || {
                    for line in reader.lines() {
                        match line {
                            Ok(output) => {
                                log_message(output);
                            }
                            Err(_) => {
                                break;
                            }
                        }
                    }
                });
            }
            // 成功 ⇒ 返 `ok:<session_id>`(原本返空字符串)。调用方要留住个 id 先 stop 得。
            format!("ok:{}", sid)
        }
        Err(e) => {
            log_message(e.to_string());
            e.to_string()
        }
    }
}

/// 内部用:`start()` 喺起新核心之前自己收掉旧嗰个。唔校验 session(佢本身就係新一轮)。
/// [0.9.96] 服务收到 Stop(升级 / 卸载 `sc stop`)时亦会调用,见 `windows.rs`。
pub(crate) fn stop_internal() {
    let mut process = PROCESS.lock().unwrap();
    if let Some(mut child) = process.take() {
        let _ = child.kill();
        let _ = child.wait();
    }
    *process = None;
    *SESSION.lock().unwrap() = None;
}

/// HTTP `/stop`:要带住 start 嗰阵攞到嘅 session_id 先做得。
fn api_stop(params: StopParams) -> impl Reply {
    let current = SESSION.lock().unwrap().clone();
    match current {
        // 本来就冇嘢跑 ⇒ 当成功(幂等),唔泄露任何嘢。
        None => "".to_string(),
        Some(sid) if sid == params.session_id => {
            stop_internal();
            "".to_string()
        }
        Some(_) => "refused: session mismatch".to_string(),
    }
}

fn log_message(message: String) {
    let mut log_buffer = LOGS.lock().unwrap();
    if log_buffer.len() == 100 {
        log_buffer.pop_front();
    }
    log_buffer.push_back(format!("{}\n", message));
}

fn get_logs() -> impl Reply {
    let log_buffer = LOGS.lock().unwrap();
    let value = log_buffer
        .iter()
        .cloned()
        .collect::<Vec<String>>()
        .join("\n");
    warp::reply::with_header(value, "Content-Type", "text/plain")
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct PingParams {
    pub core_sha256: String,
}

/// 🔴 [2026-09-23] 原本 `/ping` 係 `.map(|| env!("TOKEN"))` —— 直接把**预期嘅核心
/// SHA256** 吐畀任何一个本机调用方。咁样:
///   ① 信息泄露
///   ② 係 TOCTOU(闸 3)嘅助攻 —— 攻击者攞到预期 hash 就知道要伪造成点
/// 而家反转:由调用方**证明**佢知,helper 只答 ok / mismatch,唔再讲出预期值。
fn ping(params: PingParams) -> impl Reply {
    if params.core_sha256 == env!("TOKEN") {
        "ok".to_string()
    } else {
        "mismatch".to_string()
    }
}

pub async fn run_service() -> anyhow::Result<()> {
    let api_ping = warp::post()
        .and(warp::path("ping"))
        .and(warp::body::json())
        .map(|params: PingParams| ping(params));

    let api_start = warp::post()
        .and(warp::path("start"))
        .and(warp::body::json())
        .map(|start_params: StartParams| start(start_params));

    let api_stop = warp::post()
        .and(warp::path("stop"))
        .and(warp::body::json())
        .map(|params: StopParams| api_stop(params));

    let api_logs = warp::get().and(warp::path("logs")).map(|| get_logs());

    warp::serve(api_ping.or(api_start).or(api_stop).or(api_logs))
        .run(([127, 0, 0, 1], LISTEN_PORT))
        .await;

    Ok(())
}
