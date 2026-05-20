# Demo 项目 — 方案设计

## 技术选型
- 语言：bash（按需）
- 工具：ip route / ifconfig 获取本机网段，ping -c 1 -W 1 扫描 /24 网段

## 实现方案

### 1. 自动检测网段
```bash
ip route | grep 'scope link' | head -1
```
或
```bash
ip -o -f inet addr show | awk '{print $4}'
```

### 2. 扫描设备
对网段内 1-254 每个 IP 发一个 ping（超时 1s），解析 arp 表获取 MAC。

### 3. 输出格式
```
192.168.1.1    router.home     aa:bb:cc:dd:ee:ff
192.168.1.100  my-pc           11:22:33:44:55:66
```

## 架构
单文件 `lan-scan.sh`，可独立运行，无外部依赖。
