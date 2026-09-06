FROM debian:latest

# 安装必要工具（curl + 解压 + 可能用到的工具）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl ca-certificates tar gzip coreutils util-linux && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /root

# 复制启动脚本
COPY start.sh /root/start.sh
RUN chmod +x /root/start.sh

# 确保日志目录存在
RUN mkdir -p /root

CMD ["/root/start.sh"]
