#!/usr/bin/env python3
"""风火轮子 agent — 一次性任务执行器

PM 用 terminal(background, notify_on_complete=true) 启动，
子 agent 独立干活，干完通知 PM，PM 回来检查结果。

用法:
  python3 subagent.py --task /path/to/task.json

task.json 格式:
{
  "task_id": "dev-001",
  "type": "dev",
  "role": "developer",
  "prompt": "写一个脚本，扫描局域网设备并输出存活IP",
  "skill_methodology": "遵循以下工程规范：...（PM 从 skill 提取）",
  "project_dir": "/home/sunzc/AIProjects/ai-briefing",
  "files_to_read": ["src/main.py"],
  "acceptance_criteria": "超时 30s 内能跑完整网段"
}

PM 调用示例:
  terminal(background, notify_on_complete=true,
           command="python3 template/agents/subagent.py --task instances/ai-briefing/tasks/pending/dev-001.task.json",
           workdir="/home/sunzc/.hermes/data/wind-fire-wheel")
"""

import json
import os
import sys
import subprocess
import argparse
import time
import shutil


def main():
    args = parse_args()
    task_path = os.path.abspath(args.task)

    # 读 task
    task = read_json(task_path)
    task_id = task.get('task_id', os.path.basename(task_path))
    project_dir = task.get('project_dir', os.getcwd())

    # 在项目目录下建 done/ 文件夹
    tasks_dir = os.path.dirname(os.path.dirname(task_path))
    done_dir = os.path.join(tasks_dir, 'done') if 'pending' in task_path else os.path.join(os.path.dirname(tasks_dir), 'done')
    os.makedirs(done_dir, exist_ok=True)

    log(f'领活: {task_id}')
    log(f'项目: {project_dir}')

    # 拼 prompt
    prompt = build_prompt(task)

    # 如果 task 里指定了看某些文件，加上去
    file_context = build_file_context(task, project_dir)
    if file_context:
        prompt += f'\n\n{file_context}'

    # 记一下 prompt 长度方便以后调优
    log(f'prompt 长度: {len(prompt)} 字符')

    # 执行 —— 调 hermes chat -q
    start = time.time()
    result = run_hermes(prompt, project_dir)
    duration = time.time() - start

    # 看改了哪些文件（如果项目是 git 仓库）
    files_changed = get_git_changes(project_dir)

    # 汇总结果
    output = {
        'task_id': task_id,
        'exit_code': result.returncode,
        'stdout_tail': result.stdout[-3000:] if result.stdout else '',
        'stderr_tail': result.stderr[-1000:] if result.stderr else '',
        'duration_sec': round(duration, 1),
        'files_changed': files_changed,
        'completed_at': time.strftime('%Y-%m-%d %H:%M:%S'),
    }

    # 写回 task 文件到 done/
    task['status'] = 'done' if result.returncode == 0 else 'failed'
    task['result'] = output
    task['completed_at'] = output['completed_at']

    done_path = os.path.join(done_dir, os.path.basename(task_path))
    write_json(done_path, task)

    # 再写一个瘦身的 result 文件，方便 PM 快速看
    result_path = os.path.join(done_dir, f'{task_id}.result.json')
    write_json(result_path, output)

    # 删掉 pending 里的原文件
    if os.path.exists(task_path):
        os.remove(task_path)

    status = '✅' if result.returncode == 0 else '❌'
    log(f'{status} 完成: {task_id} (exit={result.returncode}, {duration:.0f}s)')
    if files_changed:
        log(f'改动: {files_changed}')

    sys.exit(0 if result.returncode == 0 else 1)


def build_prompt(task):
    """拼完整 prompt：skill 方法论 + 角色 + 任务 + 验收标准"""
    parts = []

    skill = task.get('skill_methodology', '')
    if skill:
        parts.append(f'【方法论框架】\n{skill}\n')

    role = task.get('role', 'developer')
    parts.append(f'【你的角色】\n你是一个专业的 {role}。请严格遵循方法论框架执行任务。')

    prompt = task.get('prompt', '')
    parts.append(f'【任务描述】\n{prompt}')

    acceptance = task.get('acceptance_criteria', '')
    if acceptance:
        parts.append(f'【验收标准】\n{acceptance}')

    parts.append(
        '\n请执行上述任务。修改项目目录下的文件来实现需求。'
        '\n完成后用一句话总结你做了什么。'
    )

    return '\n\n'.join(parts)


def build_file_context(task, project_dir):
    """读 task 里指定的文件，做成上下文"""
    files = task.get('files_to_read', [])
    if not files:
        return ''

    parts = []
    for f in files:
        path = os.path.join(project_dir, f) if not os.path.isabs(f) else f
        if os.path.exists(path):
            try:
                with open(path, encoding='utf-8', errors='replace') as fh:
                    content = fh.read()
                # 截长文件
                if len(content) > 5000:
                    content = content[:5000] + '\n... [文件过长，截断]'
                parts.append(f'--- {f} ---\n{content}')
            except Exception as e:
                parts.append(f'--- {f} ---\n[读取失败: {e}]')
        else:
            parts.append(f'--- {f} ---\n[文件不存在]')

    return '\n\n'.join(parts)


def run_hermes(prompt, project_dir, use_worktree=False):
    """调 hermes chat -q 干活

    如果 use_worktree=True 且项目是 git 仓库，用 --worktree 隔离。
    否则不加 --worktree（适用于非 git 目录或临时任务）。
    """
    cmd = ['hermes', 'chat', '-q', prompt, '--yolo']
    if use_worktree:
        cmd.insert(-1, '--worktree')
    try:
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600,
            cwd=project_dir,
            env=os.environ,
        )
    except subprocess.TimeoutExpired:
        log('⏰ 超时 (600s)')
        # 返回一个伪结果
        class TimeoutResult:
            returncode = 124
            stdout = ''
            stderr = 'timeout 600s'
        return TimeoutResult()


def get_git_changes(project_dir):
    """看 git diff stat"""
    try:
        result = subprocess.run(
            ['git', 'diff', '--stat', 'HEAD'],
            capture_output=True, text=True, timeout=10,
            cwd=project_dir,
        )
        return result.stdout.strip()
    except Exception:
        return ''


def log(msg):
    print(f'[subagent] {time.strftime("%H:%M:%S")} {msg}', flush=True)


def read_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def write_json(path, data):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def parse_args():
    parser = argparse.ArgumentParser(description='风火轮子 agent — 一次性任务执行器')
    parser.add_argument('--task', required=True, help='task.json 路径')
    return parser.parse_args()


if __name__ == '__main__':
    main()
