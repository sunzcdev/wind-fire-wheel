"""
运维 daemon — 风火轮团队模板的通用巡道守护。

每个项目实例化时，从 template/ops/ 复制 watcher.py（共享代码），
实例自己的 config.json 定义监控项和恢复规则。

用法：
  python3 watcher.py                    # 前台运行
  python3 watcher.py --daemon           # 后台运行（写pid文件）
  python3 watcher.py --status           # 查运行状态
  python3 watcher.py --stop             # 停后台进程
"""
import os, sys, json, time, subprocess, signal, logging, argparse

# ── 路径 ──────────────────────────────────────────
INSTANCE_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATE_DIR = os.path.normpath(os.path.join(INSTANCE_DIR, "../../template/ops"))
PROJECT_NAME = os.path.basename(os.path.dirname(os.path.dirname(INSTANCE_DIR)))  # instances/<project>/ops

PID_FILE = os.path.join(INSTANCE_DIR, "daemon.pid")
LOG_FILE = os.path.join(INSTANCE_DIR, "daemon.log")
CONFIG_FILE = os.path.join(INSTANCE_DIR, "config.json")
RULES_FILE = os.path.join(INSTANCE_DIR, "rules.md")


# ── 日志 ──────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(),
    ],
)
log = logging.getLogger("ops")


# ── 配置加载 ──────────────────────────────────────
def load_config() -> dict:
    defaults = {
        "project": PROJECT_NAME,
        "poll_interval": 30,          # 每 N 秒检查一次
        "gate_timeout": 120,          # 同gate卡多久算超时（秒）
        "max_restarts": 3,            # 连续重启上限
        "report_to_pm": True,         # 是否报PM
        "checks": [],
    }
    if not os.path.exists(CONFIG_FILE):
        log.warning("config.json not found, using defaults")
        return defaults
    with open(CONFIG_FILE) as f:
        cfg = json.load(f)
    for k, v in defaults.items():
        cfg.setdefault(k, v)
    return cfg


# ── 规则加载 ──────────────────────────────────────
def load_rules() -> str:
    if os.path.exists(RULES_FILE):
        with open(RULES_FILE) as f:
            return f.read()
    return ""


# ── 检查基类 ──────────────────────────────────────
class Check:
    """单个检查项的基类。子类重写 check() 和 recover()。"""
    def __init__(self, name: str, cfg: dict):
        self.name = name
        self.cfg = cfg
        self.fail_count = 0

    def check(self) -> tuple:
        """返回 (ok: bool, detail: str)"""
        raise NotImplementedError

    def recover(self) -> tuple:
        """返回 (success: bool, action: str)"""
        return (False, "no recovery defined")

    @property
    def max_fails(self) -> int:
        return self.cfg.get("max_fails_before_report", 3)


# ── 检查：进程是否活着 ────────────────────────────
class ProcessCheck(Check):
    def check(self):
        name = self.cfg.get("process_name", "")
        if not name:
            return (True, "no process_name configured")
        try:
            r = subprocess.run(
                ["pgrep", "-f", name],
                capture_output=True, text=True, timeout=5,
            )
            if r.returncode == 0 and r.stdout.strip():
                return (True, f"process '{name}' alive (pid {r.stdout.strip().split()[0]})")
            return (False, f"process '{name}' not found")
        except Exception as e:
            return (False, f"process check error: {e}")

    def recover(self):
        cmd = self.cfg.get("restart_cmd", "")
        if not cmd:
            return (False, "no restart_cmd configured")
        try:
            subprocess.run(cmd, shell=True, timeout=30)
            time.sleep(3)
            # 验证是否起来了
            ok, _ = self.check()
            return (ok, f"restarted: {cmd}")
        except Exception as e:
            return (False, f"restart failed: {e}")


# ── 检查：gate 是否超时 ──────────────────────────
class GateCheck(Check):
    def __init__(self, name, cfg):
        super().__init__(name, cfg)
        self.last_status = None
        self.last_change_time = time.time()

    def check(self):
        ctx_path = self.cfg.get("context_file", "")
        if not ctx_path or not os.path.exists(ctx_path):
            return (True, "no context file")
        try:
            with open(ctx_path) as f:
                ctx = json.load(f)
            status = ctx.get("status", "unknown")
            now = time.time()

            if status != self.last_status:
                self.last_status = status
                self.last_change_time = now
                return (True, f"gate advanced to '{status}'")

            elapsed = now - self.last_change_time
            timeout = self.cfg.get("gate_timeout", 120)
            if elapsed > timeout:
                return (False, f"gate '{status}' stuck for {elapsed:.0f}s (> {timeout}s)")
            return (True, f"gate '{status}' running ({elapsed:.0f}s)")
        except Exception as e:
            return (True, f"gate check error: {e}")

    def recover(self):
        """按 level 处理：
        P0 — 重启 daemon
        P1 — 报 PM
        P2 — 跳过当前 gate
        """
        level = self.cfg.get("recovery_level", "P1")
        daemon_cmd = self.cfg.get("daemon_cmd", "")

        if level == "P0" and daemon_cmd:
            try:
                subprocess.run(daemon_cmd, shell=True, timeout=30)
                return (True, f"P0: restarted daemon: {daemon_cmd}")
            except Exception as e:
                return (False, f"P0 daemon restart failed: {e}")

        return (False, f"{level}: gate stuck — reported to PM")


# ── 检查：磁盘 ──────────────────────────────────
class DiskCheck(Check):
    def check(self):
        threshold = self.cfg.get("disk_threshold", 85)
        path = self.cfg.get("disk_path", "/")
        try:
            r = subprocess.run(
                ["df", "--output=pcent", path],
                capture_output=True, text=True, timeout=5,
            )
            lines = r.stdout.strip().split("\n")
            if len(lines) >= 2:
                pct = int(lines[1].strip().rstrip("%"))
                if pct >= threshold:
                    return (False, f"disk at {pct}% (threshold {threshold}%)")
                return (True, f"disk at {pct}%")
            return (True, "disk check ok")
        except Exception as e:
            return (True, f"disk check error: {e}")

    def recover(self):
        cleanup = self.cfg.get("cleanup_cmd", "")
        if cleanup:
            try:
                subprocess.run(cleanup, shell=True, timeout=30)
                return (True, f"ran cleanup: {cleanup}")
            except Exception:
                pass
        return (False, "disk above threshold — report to PM")


# ── 检查：API key ────────────────────────────────
class ApiKeyCheck(Check):
    def check(self):
        env_file = self.cfg.get("env_file", "")
        key_name = self.cfg.get("key_name", "")
        if not env_file or not key_name:
            return (True, "no api key check configured")
        try:
            with open(env_file) as f:
                content = f.read()
            if key_name in content and "=" in content:
                val = [l for l in content.split("\n") if l.startswith(key_name)][0]
                val = val.split("=", 1)[1].strip().strip("'\"")
                if len(val) > 10:
                    return (True, f"{key_name} exists")
                return (False, f"{key_name} looks empty/expired")
            return (False, f"{key_name} not found in {env_file}")
        except Exception as e:
            return (False, f"api key check error: {e}")

    def recover(self):
        return (False, "API key issue — report to PM")


# ── 检查工厂 ─────────────────────────────────────
def make_check(check_cfg: dict) -> Check:
    t = check_cfg.get("type", "")
    name = check_cfg.get("name", t)
    if t == "process":
        return ProcessCheck(name, check_cfg)
    elif t == "gate":
        return GateCheck(name, check_cfg)
    elif t == "disk":
        return DiskCheck(name, check_cfg)
    elif t == "api_key":
        return ApiKeyCheck(name, check_cfg)
    else:
        log.warning(f"unknown check type: {t}")
        return None


# ── 主循环 ──────────────────────────────────────
def run_loop(cfg: dict):
    rules = load_rules()
    checks = [make_check(c) for c in cfg.get("checks", [])]
    checks = [c for c in checks if c is not None]

    if not checks:
        log.error("No checks configured — refusing to run. Create a project-specific config.json with checks.")
        return

    log.info(f"=== 运维 daemon started for project: {cfg['project']} ===")
    if rules:
        log.info(f"Loaded rules ({len(rules)} chars)")

    restart_count = 0

    while True:
        for check in checks:
            try:
                ok, detail = check.check()
                if ok:
                    check.fail_count = 0
                    log.debug(f"[OK] {check.name}: {detail}")
                else:
                    check.fail_count += 1
                    log.warning(f"[FAIL] {check.name}: {detail} (fail #{check.fail_count})")

                    if check.fail_count >= check.max_fails:
                        log.info(f"[RECOVERY] {check.name}: attempting recovery...")
                        recovered, action = check.recover()
                        if recovered:
                            log.info(f"[RECOVERED] {check.name}: {action}")
                            check.fail_count = 0
                            restart_count = 0
                        else:
                            restart_count += 1
                            log.error(f"[ESCALATE] {check.name}: recovery failed ({action})")
                            if cfg.get("report_to_pm"):
                                _report_to_pm(cfg["project"], check.name, action)
                            if restart_count >= cfg.get("max_restarts", 3):
                                log.critical(f"[CRITICAL] {cfg['project']}: max restarts reached")
                                _report_to_pm(cfg["project"], "SYSTEM", "max restarts reached — needs human intervention")
                                restart_count = 0
            except Exception as e:
                log.error(f"[ERROR] {check.name}: exception: {e}")

        time.sleep(cfg.get("poll_interval", 30))


# ── 报PM ─────────────────────────────────────────
def _report_to_pm(project: str, check_name: str, detail: str):
    """向 PM 报告异常。当前写入日志，后续对接 send_message。"""
    msg = f"[运维] {project}: {check_name} — {detail}"
    log.warning(f"REPORT TO PM: {msg}")
    # TODO: send_message 接口
    # send_message(target="weixin:...", message=msg)


# ── PID 文件管理 ────────────────────────────────
def write_pid():
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))

def read_pid() -> int:
    if os.path.exists(PID_FILE):
        with open(PID_FILE) as f:
            return int(f.read().strip())
    return 0

def is_running(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError):
        return False


# ── 入口 ─────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="风火轮运维 daemon")
    parser.add_argument("--daemon", action="store_true", help="后台运行")
    parser.add_argument("--status", action="store_true", help="查运行状态")
    parser.add_argument("--stop", action="store_true", help="停止后台进程")
    args = parser.parse_args()

    if args.status:
        pid = read_pid()
        if pid and is_running(pid):
            print(f"运维 daemon 运行中 (pid {pid})")
        else:
            print("运维 daemon 未运行")
        sys.exit(0)

    if args.stop:
        pid = read_pid()
        if pid and is_running(pid):
            os.kill(pid, signal.SIGTERM)
            print(f"已停止运维 daemon (pid {pid})")
        else:
            print("运维 daemon 未运行")
        sys.exit(0)

    if args.daemon:
        pid = os.fork()
        if pid > 0:
            print(f"运维 daemon 已启动 (pid {pid})")
            sys.exit(0)
        # 子进程继续
        os.setsid()

    write_pid()
    cfg = load_config()
    try:
        run_loop(cfg)
    except KeyboardInterrupt:
        log.info("运维 daemon stopped by user")
    except Exception as e:
        log.critical(f"运维 daemon crashed: {e}")
        raise
