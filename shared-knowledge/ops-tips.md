# 风火轮共享知识库 — 运维踩坑记录

## 桌面自动化 — CDP
- **Trae CDP 端口**: 9229, 激活信号 SIGUSR1
- **连接前必须先激活 Inspector**: `kill -SIGUSR1 $(pgrep -f trae-cn)` → 等 2s
- **webContents 索引不固定**: 每次枚举 `getAllWebContents()`，不硬编码
- **React 受控组件接收 InputEvent('beforeinput')**，非 textContent 直改
- **发送用 KeyboardEvent Enter**，非模拟点击
- **检测完成靠 DOM 文本稳定**：`.assistant-chat-turn-content` 内容停止增长 ≥3s
- **判断 done 前必须二次验证**：检测弹窗/检测完成各一次，防假阳性
- **Session ID 提取**：CDP 真实鼠标双点头像 → xclip 读剪贴板；SQLite state.vscdb 兜底
- **取完后清理剪贴板**：`xclip -selection clipboard` 写入空
- **轨迹提取**：从 DOM `.assistant-chat-turn-content` 直接提取文本（不走剪贴板，Electron JS click 不会触发原生剪贴板）

## 授权弹窗处理
- **关键词多策略**：搜 body.innerText 含`等待你的操作`、`高风险命令`、`请仔细检查`、`请检查`、`请在运行前检查`
- **自动点「跳过」「保留」「取消」**，不点「运行」「删除」
- **最大重试 3 次**
- **资源管理**：df/du 定期检查磁盘，~/.hermes/cache/ 和 ~/.hermes/data/solo-coder/ 定时清理

## 代理与环境
- **ALL_PROXY=socks5://127.0.0.1:1081** 影响所有 HTTP 请求
- **子进程继承代理变量** → lark-cli 被 socks 拦截，必须 clean_env
- **过滤的代理变量**：ALL_PROXY/http_proxy/HTTPS_PROXY/SOCKS_PROXY/socks_proxy 等 10 个

## 进程管理
- **gateway-watchdog**：systemd 每 30s 检查，崩了自动杀 trae-cn 残留 + 重启
- **Trae 进程**：/usr/bin/trae-cn
- **进程残留**：daemon 崩了可能留 trae-cn zombie，watchdog 清理
- **桌面锁屏**：任何 GUI 操作前必须先 loginctl unlock-sessions
- **xdotool 不可靠时用 ydotool**（内核级输入）
