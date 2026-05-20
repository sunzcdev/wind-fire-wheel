#!/usr/bin/env python3
"""Dev daemon — 监听任务队列，调 claude 干活

用法:
  python3 dev-daemon.py --instance <instance_dir> [--interval 10]

行为:
  loop:
    扫 tasks/pending/ 下的 .task.json
    有 → 移到 in_progress/ → 调 claude -p → 结果写回 → 移到 done/
    无 → sleep interval 秒
"""

import json, os, sys, time, subprocess, uuid, shutil, glob

def log(msg):
    print(f'[dev-daemon] {time.strftime("%H:%M:%S")} {msg}', flush=True)

def main():
    args = parse_args()
    instance_dir = args['instance_dir']
    interval = args.get('interval', 10)

    pending_dir = os.path.join(instance_dir, 'tasks', 'pending')
    progress_dir = os.path.join(instance_dir, 'tasks', 'in_progress')
    done_dir = os.path.join(instance_dir, 'tasks', 'done')

    for d in [pending_dir, progress_dir, done_dir]:
        os.makedirs(d, exist_ok=True)

    log(f'启动 — 监听 {pending_dir}')

    while True:
        tasks = sorted(glob.glob(os.path.join(pending_dir, '*.task.json')))
        for task_path in tasks:
            try:
                task = json.load(open(task_path))
            except json.JSONDecodeError as e:
                log(f'⚠️  JSON 解析失败: {os.path.basename(task_path)} — {e}')
                # 移到 failed 目录
                fail_dir = os.path.join(os.path.dirname(pending_dir), 'failed')
                os.makedirs(fail_dir, exist_ok=True)
                shutil.move(task_path, os.path.join(fail_dir, os.path.basename(task_path)))
                continue
            task_id = task.get('task_id', os.path.basename(task_path))
            project_dir = task.get('project_dir', instance_dir)
            prompt = task.get('prompt', '')
            log(f'领活: {task_id}')

            # 移到 in_progress
            progress_path = os.path.join(progress_dir, os.path.basename(task_path))
            shutil.move(task_path, progress_path)

            # 执行
            start_ts = time.time()
            result = execute_task(project_dir, prompt)
            duration = time.time() - start_ts
            result['duration_sec'] = round(duration, 1)

            # 检查文件变更
            diff_out = subprocess.run(
                ['git', 'diff', '--stat', 'HEAD'],
                capture_output=True, text=True, cwd=project_dir,
                timeout=10
            )
            result['files_changed'] = diff_out.stdout.strip()

            # 写回 task
            task['status'] = 'done' if result['exit_code'] == 0 else 'failed'
            task['result'] = result
            task['completed_at'] = time.strftime('%Y-%m-%d %H:%M:%S')
            json.dump(task, open(progress_path, 'w'), indent=2, ensure_ascii=False)

            # 移到 done
            done_path = os.path.join(done_dir, os.path.basename(task_path))
            shutil.move(progress_path, done_path)

            log(f'完成: {task_id} (exit={result["exit_code"]}, {duration:.0f}s, 改={result["files_changed"] or "无"}')

        time.sleep(interval)

def execute_task(project_dir, prompt):
    """调 claude -p 干活"""
    if not prompt.strip():
        return {'exit_code': -1, 'error': '空 prompt', 'stdout': '', 'stderr': ''}

    try:
        proc = subprocess.run(
            ['claude', '-p', '--dangerously-skip-permissions', '--effort', 'low'],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=300,
            cwd=project_dir
        )
        return {
            'exit_code': proc.returncode,
            'stdout': proc.stdout[-2000:],
            'stderr': proc.stderr[-1000:],
            'error': None
        }
    except subprocess.TimeoutExpired:
        return {'exit_code': 124, 'error': 'timeout 300s', 'stdout': '', 'stderr': ''}
    except FileNotFoundError:
        return {'exit_code': -2, 'error': 'claude 命令未找到', 'stdout': '', 'stderr': ''}
    except Exception as e:
        return {'exit_code': -3, 'error': str(e), 'stdout': '', 'stderr': ''}

def parse_args():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--instance', required=True, help='实例目录路径')
    parser.add_argument('--interval', type=int, default=10, help='轮询间隔（秒）')
    args = parser.parse_args()
    return {'instance_dir': os.path.abspath(args.instance), 'interval': args.interval}


if __name__ == '__main__':
    main()
