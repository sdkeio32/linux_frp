#!/usr/bin/env bash
#================================================================
# FRP 服务端 (frps) 一键安装脚本 —— 使用 QUIC 控制通道（UDP 39501）
# 控制端口调整到 39500–39501 范围，放行 39000–40000 端口
# 适用：Debian/Ubuntu, CentOS/RHEL, Alpine, Fedora…
# 使用：curl -sL <脚本地址> | sudo bash
#----------------------------------------------------------------
# —— 配置区 ——
FRP_VERSION=""                     # 指定版本 (留空自动拉取最新)
INSTALL_DIR="${HOME}/.varfrp"      # 安装目录（隐藏）
BIND_PORT=39500                    # QUIC 控制通道 TCP 端口（fallback）
BIND_UDP_PORT=39501                # QUIC 控制通道 UDP 端口
TOKEN="ChangeMeToAStrongToken123"  # 连接 Token，请务必改成强随机串
ALLOW_PORTS="39502-39510"          # 允许映射的业务端口范围
PROTOCOL="quic"                    # 控制协议：quic（基于 UDP 的 QUIC）
TLS_ENABLE="true"                  # 必需启用 TLS (wss/quic 必须)
# TLS 证书拉取 URL，请替换为你的域名证书
TLS_CERT_URL="https://your.domain.com/fullchain.pem"
TLS_KEY_URL="https://your.domain.com/privkey.pem"
TLS_CERT="${INSTALL_DIR}/cert/frps.crt"
TLS_KEY="${INSTALL_DIR}/cert/frps.key"
# —— 配置区结束 ——
#================================================================

set -euo pipefail

detect_arch(){
  case "$(uname -m)" in
    x86_64)    frp_arch=amd64 ;;
    aarch64|arm64) frp_arch=arm64 ;;
    armv7l)    frp_arch=armv7 ;;
    *) echo "❌ 当前架构 $(uname -m) 不支持" >&2; exit 1 ;;
  esac
}

get_latest_version(){
  echo "⏳ 检测 FRP 最新版本..."
  FRP_VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest \
    | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
  echo "✅ 最新版本：$FRP_VERSION"
}

fetch_single(){
  local url=$1 dest=$2
  curl -fSL "$url" -o "$dest"
}

main(){
  [ "$EUID" -ne 0 ] && echo "请使用 root 或 sudo 运行此脚本" >&2 && exit 1

  # 停止并清理旧服务
  systemctl is-active --quiet frps && systemctl stop frps
  if systemctl list-unit-files | grep -Fq frps.service; then
    systemctl disable frps
    rm -f /etc/systemd/system/frps.service
    systemctl daemon-reload
  fi
  pkill frps || true
  rm -rf "$INSTALL_DIR"

  detect_arch
  [ -z "$FRP_VERSION" ] && get_latest_version || echo "ℹ️ 使用指定版本：$FRP_VERSION"

  mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"

  # 下载并解压 FRP
  pkg="frp_${FRP_VERSION#v}_linux_${frp_arch}.tar.gz"
  echo "⏳ 下载 FRP: https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${pkg}"
  curl -sL "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${pkg}" -o "$pkg"
  tar xzf "$pkg" --strip-components=1 && rm -f "$pkg"

  # 拉取 TLS 证书
  if [ "$TLS_ENABLE" = "true" ]; then
    mkdir -p "$(dirname "$TLS_CERT")"
    fetch_single "$TLS_CERT_URL" "$TLS_CERT"
    fetch_single "$TLS_KEY_URL"  "$TLS_KEY"
    echo "🔐 TLS 证书拉取完成"
  fi

  # 生成 frps.toml（QUIC 控制通道）
  cat > frps.toml <<-EOF
[common]
bind_addr      = "0.0.0.0"
bind_port      = $BIND_PORT
quic_bind_port = $BIND_UDP_PORT
token          = "$TOKEN"
allow_ports    = "$ALLOW_PORTS"
protocol       = "$PROTOCOL"

tls_enable     = true
tls_cert_file  = "$TLS_CERT"
tls_key_file   = "$TLS_KEY"
EOF

  # 安装可执行文件
  install -m755 frps /usr/local/bin/frps

  # 放行防火墙端口 39000-40000（立即生效，无需重启）
  if command -v ufw >/dev/null; then
    ufw allow 39000:40000/tcp
    ufw allow 39000:40000/udp
  elif command -v firewall-cmd >/dev/null; then
    firewall-cmd --add-port=39000-40000/tcp
    firewall-cmd --add-port=39000-40000/udp
  else
    iptables -I INPUT -p tcp --dport 39000:40000 -j ACCEPT
    iptables -I INPUT -p udp --dport 39000:40000 -j ACCEPT
  fi

  # 创建 systemd 服务并启动
  cat > /etc/systemd/system/frps.service <<-EOF
[Unit]
Description=FRP Server (frps)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c $INSTALL_DIR/frps.toml
Restart=on-failure
LimitNOFILE=65536
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now frps

  # 输出客户端示例
  SERVER_IP=$(curl -s https://api.ipify.org)
  echo -e "\n🎉 安装完成，QUIC 控制通道已监听 UDP $BIND_UDP_PORT！"
  echo "• 配置：$INSTALL_DIR/frps.toml"
  echo "• 日志：$INSTALL_DIR/frps.log"
  echo "• 服务状态：systemctl status frps"
  echo -e "\n👉 客户端 frpc.toml 例子（复制到 Windows）：\n[common]\nserver_addr = \"$SERVER_IP\"\nserver_port = $BIND_PORT\ntoken = \"$TOKEN\"\nprotocol = \"$PROTOCOL\"\n\n[example]\ntype = \"tcp\"\nlocal_ip = \"127.0.0.1\"\nlocal_port = 39502\nremote_port = 39502\n"
}

main "$@"
