#!/usr/bin/env python3
"""Test daemon — 监听测试任务队列，跑测试脚本出报告

用法:
  python3 test-daemon.py --instance <instance_dir> [--interval 10]

行为:
  loop:
    扫 test-jobs/pending/ 下的 .test.json
    有 → 移到 in_progress/ → 跑测试脚本 → 写报告 → 移到 done/
    无 → sleep interval 秒
"""

import json, os, sys, time, subprocess, shutil, glob

REPORT_DIR_NAME = 'reports'
PENDING = ['test-jobs', 'pending']
IN_PROGRESS = ['test-jobs', 'in_progress']
DONE = ['test-jobs', 'done']

def log(msg):
    print(f'[test-daemon] {time.strftime("%H:%M:%S")} {msg}', flush=True)

def mkdirs(base, *parts):
    d = os.path.join(base, *parts)
    os.makedirs(d, exist_ok=True)
    return d

def main():
    instance_dir, interval = parse_args()

    pending_dir = mkdirs(instance_dir, *PENDING)
    progress_dir = mkdirs(instance_dir, *IN_PROGRESS)
    done_dir = mkdirs(instance_dir, *DONE)
    report_dir = mkdirs(instance_dir, REPORT_DIR_NAME)

    log(f'启动 — 监听 {pending_dir}')

    while True:
        jobs = sorted(glob.glob(os.path.join(pending_dir, '*.test.json')))
        for job_path in jobs:
            job = json.load(open(job_path))
            job_id = job.get('job_id', os.path.basename(job_path))
            project_dir = job.get('project_dir', instance_dir)
            test_script = job.get('test_script', '')
            timeout_sec = job.get('timeout_sec', 60)

            log(f'领活: {job_id} → {test_script}')

            # 移到 in_progress
            job_name = os.path.basename(job_path)
            progress_path = os.path.join(progress_dir, job_name)
            shutil.move(job_path, progress_path)

            # 跑测试
            script_path = os.path.join(project_dir, test_script) if not os.path.isabs(test_script) else test_script
            start_ts = time.time()

            if not os.path.exists(script_path):
                result = {'exit_code': -1, 'error': f'测试脚本不存在: {script_path}', 'stdout': '', 'stderr': ''}
            else:
                try:
                    proc = subprocess.run(
                        ['bash', script_path],
                        capture_output=True, text=True, timeout=timeout_sec,
                        cwd=project_dir
                    )
                    result = {
                        'exit_code': proc.returncode,
                        'stdout': proc.stdout,
                        'stderr': proc.stderr[-1000:],
                        'error': None
                    }
                except subprocess.TimeoutExpired:
                    result = {'exit_code': 124, 'error': f'timeout {timeout_sec}s', 'stdout': '', 'stderr': ''}
                except Exception as e:
                    result = {'exit_code': -3, 'error': str(e), 'stdout': '', 'stderr': ''}

            duration = time.time() - start_ts
            result['duration_sec'] = round(duration, 1)

            # 写测试报告
            passed = result['exit_code'] == 0
            report = {
                'job_id': job_id,
                'test_script': test_script,
                'passed': passed,
                'result': result,
                'ran_at': time.strftime('%Y-%m-%d %H:%M:%S'),
                'duration_sec': round(duration, 1)
            }
            report_path = os.path.join(report_dir, f'{job_id}.report.json')
            json.dump(report, open(report_path, 'w'), indent=2, ensure_ascii=False)

            # 更新 job
            job['status'] = 'done' if passed else 'failed'
            job['result'] = result
            job['completed_at'] = time.strftime('%Y-%m-%d %H:%M:%S')
            json.dump(job, open(progress_path, 'w'), indent=2, ensure_ascii=False)

            # 移到 done
            done_path = os.path.join(done_dir, job_name)
            shutil.move(progress_path, done_path)

            status = '✅ PASS' if passed else '❌ FAIL'
            log(f'完成: {job_id} {status} (exit={result["exit_code"]}, {duration:.0f}s)')

        time.sleep(interval)


def parse_args():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--instance', required=True, help='实例目录路径')
    parser.add_argument('--interval', type=int, default=10, help='轮询间隔（秒）')
    args = parser.parse_args()
    return os.path.abspath(args.instance), args.interval


if __name__ == '__main__':
    main()
