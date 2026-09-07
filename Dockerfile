# syntax=docker/dockerfile:1
#
# Railway / Docker 通用远程桌面镜像
#   OS      : Ubuntu 22.04 (Jammy)
#   Desktop : XFCE4
#   Protocol: RDP (xrdp + xorgxrdp)
#   VPN     : EasyTier (可选, --no-tun 模式, 不需要 TUN 设备)
#
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=Asia/Shanghai \
    RDP_USER=rdpuser \
    RDP_UID=1000 \
    RDP_PORT=3389

# ------------------------------------------------------------------
# 1) 基础系统包
# ------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg2 apt-utils locales tzdata \
      sudo dbus dbus-x11 xauth x11-utils \
      supervisor netcat-openbsd net-tools iputils-ping dnsutils \
      procps htop vim nano git unzip zip xclip xdg-utils \
      fonts-noto-cjk fonts-noto-color-emoji fonts-wqy-zenhei \
      thunar-archive-plugin file-roller gvfs \
      python3 python3-pip; \
    ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime; \
    echo "${TZ}" > /etc/timezone; \
    sed -i 's/^# *\(en_US.UTF-8\)/\1/; s/^# *\(zh_CN.UTF-8\)/\1/' /etc/locale.gen; \
    locale-gen; \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------
# 2) 桌面环境 + XRDP
# ------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      xrdp xorgxrdp xserver-xorg-core xserver-xorg-input-all \
      xfce4 xfce4-goodies xfce4-terminal xfce4-screenshooter; \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------
# 3) Google Chrome（下载失败不阻断构建）
# ------------------------------------------------------------------
RUN set -eux; \
    ARCH=$(dpkg --print-architecture); \
    if wget -q -O /tmp/chrome.deb "https://dl.google.com/linux/direct/google-chrome-stable_current_${ARCH}.deb"; then \
      apt-get update; \
      apt-get install -y /tmp/chrome.deb || echo "chrome deps missing, skipped"; \
      rm -f /tmp/chrome.deb; \
    fi; \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------
# 4) EasyTier（去中心化组网，用于私网接入）
#    优先下载固定版本，失败则回退到 latest 自动发现
# ------------------------------------------------------------------
#    EasyTier 属于可选组件：下载失败只告警，不让整个构建挂掉
#    （entrypoint.sh 检测不到 easytier-core 会自动跳过组网，RDP 照常可用）
ARG EASYTIER_VERSION=2.6.4
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) ET_ARCH=x86_64 ;; \
      arm64) ET_ARCH=aarch64 ;; \
      *)     ET_ARCH=x86_64 ;; \
    esac; \
    V="${EASYTIER_VERSION#v}"; \
    URL="https://github.com/EasyTier/EasyTier/releases/download/v${V}/easytier-linux-${ET_ARCH}-v${V}.zip"; \
    if ! curl -fsSL --retry 3 --retry-delay 2 -o /tmp/et.zip "$URL"; then \
      echo "[warn] 固定版本下载失败，回退到 latest"; \
      URL="$(curl -fsSL https://api.github.com/repos/EasyTier/EasyTier/releases/latest \
             | grep -o "https://[^\"]*linux-${ET_ARCH}-[^\"]*\.zip" | head -n1)"; \
      curl -fsSL --retry 3 -o /tmp/et.zip "$URL" || true; \
    fi; \
    if [ -s /tmp/et.zip ] && unzip -o -q /tmp/et.zip -d /tmp/et; then \
      find /tmp/et -type f -name 'easytier-core' -exec install -m 0755 {} /usr/local/bin/ \; ; \
      find /tmp/et -type f -name 'easytier-cli'  -exec install -m 0755 {} /usr/local/bin/ \; ; \
    else \
      echo "[warn] EasyTier 下载失败，本镜像不含 EasyTier，RDP 功能不受影响"; \
    fi; \
    rm -rf /tmp/et /tmp/et.zip; \
    easytier-core --version || true

# ------------------------------------------------------------------
# 5) 配置文件
# ------------------------------------------------------------------
COPY config/supervisord.conf      /etc/supervisor/supervisord.conf
COPY config/xrdp.ini              /etc/xrdp/xrdp.ini
COPY config/startwm.sh            /etc/xrdp/startwm.sh
COPY config/45-xrdp-desktop.pkla  /etc/polkit-1/localauthority/50-local.d/45-xrdp-desktop.pkla
COPY scripts/entrypoint.sh        /usr/local/bin/entrypoint.sh
COPY scripts/healthcheck.sh       /usr/local/bin/healthcheck.sh

# 注：ubuntu 基础镜像里的 /etc/machine-id 是 0 字节空文件，
# dbus-uuidgen --ensure 遇到"存在但内容非法"的文件会直接报错退出
# （UUID file should contain a hex string of length 32, not length 0），
# 所以必须先 rm 掉再生成，同时给 /var/lib/dbus/machine-id 做软链。
RUN set -eux; \
    chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh /etc/xrdp/startwm.sh; \
    mkdir -p /run/xrdp /var/log/xrdp /run/dbus /etc/easytier; \
    rm -f /etc/machine-id /var/lib/dbus/machine-id; \
    dbus-uuidgen --ensure=/etc/machine-id; \
    ln -sf /etc/machine-id /var/lib/dbus/machine-id

# 注意：不要写 VOLUME 指令 —— Railway 明确不支持 Dockerfile 里的 VOLUME，
# 会导致 "docker VOLUME ... is not supported, use Railway Volumes" 构建报错。
# 持久化请在平台上挂卷：
#   Railway : 项目画布 Ctrl/⌘+K → Volume → 选本服务 → Mount Path 填 /home
#   Docker  : docker-compose.yml 里已经有 rdp_home:/home（本地/自建环境保留）
# 挂载后 entrypoint.sh 会自动创建 /home/${RDP_USER} 并修正属主，空卷也能正常启动。

EXPOSE 3389

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
