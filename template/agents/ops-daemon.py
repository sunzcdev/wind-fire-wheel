#!/usr/bin/env python3
"""Ops daemon — 全局巡逻，守护所有实例的 agent 进程

用法:
  python3 ops-daemon.py --wind-fire-root <path> [--interval 30]

行为:
  loop 每 30 秒:
    对所有 instances/ 下的项目:
      检查 Dev/Test daemon 是否活着 → 不在则重启
      检查 tasks/pending/ 超时 → 告警
      检查 tasks/in_progress/ 超时 → 告警
      检查磁盘空间
"""

import json, os, sys, time, subprocess, glob, signal

ROOT = None
DAEMON_SCRIPTS = {
    'dev': 'dev-daemon.py',
    'test': 'test-daemon.py',
}
DAEMON_PIDS = {}  # {project: {role: pid}}

def log(msg):
    print(f'[ops-daemon] {time.strftime("%H:%M:%S")} {msg}', flush=True)

def find_daemon_pid(script_name, instance_dir=None):
    """通过 ps aux 找特定实例的 daemon 进程"""
    try:
        out = subprocess.run(
            ['ps', 'aux'], capture_output=True, text=True, timeout=10
        ).stdout
        for line in out.split('\n'):
            if script_name not in line or 'python3' not in line or 'grep' in line:
                continue
            if instance_dir and instance_dir not in line:
                continue
            parts = line.split()
            if parts:
                return int(parts[1])
    except Exception:
        pass
    return None

def start_daemon(role, instance_dir):
    """后台启动一个 daemon"""
    script = os.path.join(ROOT, 'template', 'agents', DAEMON_SCRIPTS[role])
    if not os.path.exists(script):
        log(f'❌ 脚本不存在: {script}')
        return None
    try:
        proc = subprocess.Popen(
            ['python3', script, '--instance', instance_dir],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        log(f'🚀 启动 {role} daemon (PID {proc.pid}) for {os.path.basename(instance_dir)}')
        return proc.pid
    except Exception as e:
        log(f'❌ 启动 {role} daemon 失败: {e}')
        return None

def check_instances():
    """巡逻所有实例"""
    instances_dir = os.path.join(ROOT, 'instances')
    if not os.path.isdir(instances_dir):
        return

    for inst in sorted(os.listdir(instances_dir)):
        inst_dir = os.path.join(instances_dir, inst)
        if not os.path.isdir(inst_dir):
            continue

        # 1. 检查 Dev daemon
        dev_pid = find_daemon_pid(DAEMON_SCRIPTS['dev'], inst_dir)
        if dev_pid is None:
            log(f'{inst}: Dev daemon 不在运行，启动...')
            pid = start_daemon('dev', inst_dir)
            if pid:
                DAEMON_PIDS[f'{inst}/dev'] = pid

        # 2. 检查 Test daemon
        test_pid = find_daemon_pid(DAEMON_SCRIPTS['test'], inst_dir)
        if test_pid is None:
            log(f'{inst}: Test daemon 不在运行，启动...')
            pid = start_daemon('test', inst_dir)
            if pid:
                DAEMON_PIDS[f'{inst}/test'] = pid

        # 3. 检查 tasks/pending/ 超时
        pending_dir = os.path.join(inst_dir, 'tasks', 'pending')
        if os.path.isdir(pending_dir):
            now = time.time()
            for fname in os.listdir(pending_dir):
                fpath = os.path.join(pending_dir, fname)
                if fname.endswith('.task.json'):
                    age = now - os.path.getmtime(fpath)
                    if age > 300:  # 5 分钟
                        log(f'⚠️  {inst}: {fname} 在 pending 超过 5 分钟')

        # 4. 检查 tasks/in_progress/ 超时
        progress_dir = os.path.join(inst_dir, 'tasks', 'in_progress')
        if os.path.isdir(progress_dir):
            now = time.time()
            for fname in os.listdir(progress_dir):
                fpath = os.path.join(progress_dir, fname)
                if fname.endswith('.task.json'):
                    age = now - os.path.getmtime(fpath)
                    if age > 1800:  # 30 分钟
                        log(f'⚠️  {inst}: {fname} 在 in_progress 超过 30 分钟')

    # 5. 磁盘检查
    try:
        stat = os.statvfs('/')
        free_pct = stat.f_bavail / stat.f_blocks * 100
        if free_pct < 10:
            log(f'⚠️  磁盘空间不足: {free_pct:.0f}% 剩余')
    except Exception:
        pass


def main():
    global ROOT
    ROOT = parse_args()
    interval = 30

    # 启动时先扫一次，拉活所有 daemon
    log(f'启动 — 巡逻 {os.path.join(ROOT, "instances")}')
    check_instances()

    while True:
        time.sleep(interval)
        check_instances()


def parse_args():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--wind-fire-root', default=os.path.expanduser('~/.hermes/data/wind-fire-wheel'))
    args = parser.parse_args()
    return os.path.abspath(args.wind_fire_root)


if __name__ == '__main__':
    main()
