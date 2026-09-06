FROM debian:latest

# 安装必要工具
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates tar && \
    rm -rf /var/lib/apt/lists/*

# 工作目录
WORKDIR /root

# 启动脚本：下载、解压、后台运行 sshx 并记录日志，然后保持容器存活
COPY start.sh /root/start.sh
RUN chmod +x /root/start.sh

CMD ["/root/start.sh"]
