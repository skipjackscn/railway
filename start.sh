#!/bin/bash
set -e

echo "=== 开始下载并运行 sshx ===" | tee /root/log.log

# 下载
curl -L https://sshx.s3.amazonaws.com/sshx-x86_64-unknown-linux-musl.tar.gz -o /root/sshx.tar.gz

# 解压
tar xvf /root/sshx.tar.gz -C /root/

# 后台运行并重定向输出（推荐写法，避免你原命令的重定向问题）
/root/sshx > /root/log.log 2>&1 &

# 等待几秒让 sshx 输出链接
sleep 3

echo "=== 当前日志内容 ==="
cat /root/log.log

echo "=== sshx 已在后台运行，容器保持存活 ==="
# 保持容器不退出（Railway 需要一个前台进程）
tail -f /root/log.log
