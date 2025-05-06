#!/usr/bin/env bash
set -e

# 只允许 root 运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 或 sudo 权限运行此脚本"
  exit 1
fi

# 1. 检测并安装 curl、tar
echo "检测并安装 curl、tar……"
if   command -v apt-get   >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl tar
elif command -v yum       >/dev/null 2>&1; then
    yum install -y curl tar
elif command -v dnf       >/dev/null 2>&1; then
    dnf install -y curl tar
elif command -v apk       >/dev/null 2>&1; then
    apk add --no-cache curl tar
elif command -v pacman    >/dev/null 2>&1; then
    pacman -Sy --noconfirm curl tar
elif command -v zypper    >/dev/null 2>&1; then
    zypper --non-interactive install curl tar
else
    echo "Unsupported package manager. 请手动安装 curl 和 tar 后重试。"
    exit 1
fi

# 2. 在 /opt 下创建隐藏目录 .varfrp 并设置权限
OPT_DIR="/opt"
FRP_DIR="$OPT_DIR/.varfrp"
echo "创建目录 $FRP_DIR 并设置权限……"
mkdir -p "$FRP_DIR"
chown root:root "$FRP_DIR"
chmod 755 "$FRP_DIR"

# 3. 拉取最新版本的 FRP 并解压到 $FRP_DIR
echo "检测 CPU 架构……"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)   TARGET_ARCH="amd64" ;;
  aarch64)  TARGET_ARCH="arm64" ;;
  armv7l)   TARGET_ARCH="arm"   ;;
  i386|i686)TARGET_ARCH="386"   ;;
  *)        TARGET_ARCH="amd64" ;;
esac

echo "获取 FRP 最新版本下载链接……"
DOWNLOAD_URL=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest \
  | grep "browser_download_url.*linux_${TARGET_ARCH}\.tar\.gz" \
  | head -n1 | cut -d '"' -f4)

if [ -z "$DOWNLOAD_URL" ]; then
  echo "无法获取 FRP 最新版本下载链接，退出。"
  exit 1
fi

echo "下载并解压 FRP 到 $FRP_DIR ……"
curl -fsSL "$DOWNLOAD_URL" -o /tmp/frp.tar.gz
tar -xzf /tmp/frp.tar.gz -C "$FRP_DIR" --strip-components=1
rm -f /tmp/frp.tar.gz

# 4. 生成或替换 frps.toml
echo "生成 frps.toml 配置文件……"
cat > "$FRP_DIR/frps.toml" << 'EOF'
bindPort = 39501
kcpBindPort = 39501

# 认证方式和令牌
auth.method = "token"
auth.token = "6F36@565%742#E97B57B0!F7BBAB4C0C7%E83002%C80A%06205#219%BBCC36DC19!5354A8%502039081724F8B%FBC71BF37093F114BEF2290E6F8&40D%64A32B3"

allowPorts = [
  { start = 39000, end = 40000 },
  { single = 20568 }
]
EOF
chown root:root "$FRP_DIR/frps.toml"
chmod 644 "$FRP_DIR/frps.toml"

# 5. 配置 systemd 服务
if command -v systemctl >/dev/null 2>&1; then
  echo "创建 systemd 单元文件 /etc/systemd/system/frps.service ……"
  cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=FRP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$FRP_DIR
ExecStart=$FRP_DIR/frps -c $FRP_DIR/frps.toml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

  echo "重载 systemd 并启用、启动 frps 服务……"
  systemctl daemon-reload
  systemctl enable frps
  systemctl restart frps
  echo "FRP 服务已启动，并设置为开机自启，故障将自动重启。"
else
  echo "未检测到 systemd，请手动配置开机自启（例如在 /etc/rc.local 中添加启动命令）。"
fi

echo "=============================="
echo "FRP 安装及配置完成！"
echo "监控日志：journalctl -u frps -f"
