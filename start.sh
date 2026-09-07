#!/bin/bash
apt update
apt install sudo
curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --auth-key=tskey-auth-kiUygmkb9211CNTRL-c5EkBQUL6F6sFTdG1ZRoE6EfWCFt2RY7P --advertise-exit-node

set -euo pipefail

LOG_FILE="/root/log.log"

# 把所有输出同时写到日志和 stdout（Railway 日志可见）
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================"
echo "=== $(date) 开始启动 sshx 环境 ==="
echo "========================================"
echo "系统信息:"
uname -a
echo "架构: $(uname -m)"
echo "当前用户: $(whoami)"
echo "工作目录: $(pwd)"
echo ""

# 检测架构并选择正确二进制（备用方案）
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)  BINARY_URL="https://sshx.s3.amazonaws.com/sshx-x86_64-unknown-linux-musl.tar.gz" ;;
    aarch64|arm64) BINARY_URL="https://sshx.s3.amazonaws.com/sshx-aarch64-unknown-linux-musl.tar.gz" ;;
    *)             BINARY_URL="https://sshx.s3.amazonaws.com/sshx-x86_64-unknown-linux-musl.tar.gz" ;;
esac
echo "检测到架构: $ARCH，使用下载地址: $BINARY_URL"
echo ""

echo "=== 方法1：使用官方安装脚本运行（推荐） ==="
# 官方推荐在 CI / 非交互环境使用
if curl -sSf https://sshx.io/get | sh -s run; then
    echo "官方脚本执行完成"
else
    echo "官方脚本执行失败，尝试手动下载方式..."
fi

echo ""
echo "=== 方法2：手动下载并运行（备用） ==="
echo "正在下载 sshx..."
if curl -L --fail --retry 3 --retry-delay 2 "$BINARY_URL" -o /root/sshx.tar.gz; then
    echo "下载成功，文件大小: $(ls -lh /root/sshx.tar.gz | awk '{print $5}')"
    echo "正在解压..."
    tar xvf /root/sshx.tar.gz -C /root/
    ls -l /root/sshx* || true

    if [ -f /root/sshx ]; then
        chmod +x /root/sshx
        echo "正在启动 /root/sshx ..."
        # 尝试用 script 模拟 TTY（部分环境需要）
        if command -v script >/dev/null 2>&1; then
            script -q -c "/root/sshx" /dev/null &
        else
            /root/sshx &
        fi
        SSHX_PID=$!
        echo "sshx 进程 PID: $SSHX_PID"
        sleep 5
        echo "当前进程列表:"
        ps aux | grep -E 'sshx|PID' || true
    else
        echo "错误：解压后未找到 /root/sshx 可执行文件"
        ls -la /root/
    fi
else
    echo "错误：下载失败"
fi

echo ""
echo "=== 当前完整日志内容 ==="
cat "$LOG_FILE" || true

echo ""
echo "========================================"
echo "=== 启动完成，容器将保持运行 ==="
echo "=== 请在 Railway Logs 中查看上方输出的分享链接 ==="
echo "=== 链接格式类似：https://sshx.io/s/xxxxx#xxxxx ==="
echo "========================================"

# 保持容器存活（同时持续输出日志）
while true; do
    sleep 30
    echo "[$(date)] 容器仍在运行，sshx 状态检查..."
    pgrep -a sshx || echo "sshx 进程未找到"
done
