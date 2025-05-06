#!/usr/bin/env bash
#================================================================
# FRP 服务端 (frps) 一键安装脚本 —— 安装到 ~/.varfrp 隐藏目录
# 适用：Debian/Ubuntu, CentOS/RHEL, Alpine, Fedora…
# 使用：curl -sL <脚本地址> | sudo bash
#----------------------------------------------------------------
# —— 配置区 ——
FRP_VERSION=""                     # 指定版本 (留空则自动拉取最新)
INSTALL_DIR="${HOME}/.varfrp"      # 安装目录（隐藏）
BIND_PORT=39000                    # 控制通道 TCP 端口
BIND_UDP_PORT=39001                # KCP(UDP) 控制通道端口
TOKEN="ChangeMeToAStrongToken123"  # 连接 Token，请务必改成强随机串
ALLOW_PORTS="39501-39510"          # 允许映射的业务端口范围
PROTOCOL="kcp"                     # 控制通道协议（tcp/kcp/quic/ws），kcp 优先使用 UDP
TLS_ENABLE="true"                  # 是否启用 TLS 加密 (true/false)
# TLS 证书拉取 URL
TLS_CERT_URL_MAIN="https://raw.githubusercontent.com/sdkeio32/linux_frp/main/frps.crt"
TLS_KEY_URL_MAIN="https://raw.githubusercontent.com/sdkeio32/linux_frp/main/frps.key"
TLS_CERT_URL_MASTER="https://raw.githubusercontent.com/sdkeio32/linux_frp/master/frps.crt"
TLS_KEY_URL_MASTER="https://raw.githubusercontent.com/sdkeio32/linux_frp/master/frps.key"
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

fetch_cert(){
  local m=$1 M=$2 d=$3
  if curl -fSL "$m" -o "$d"; then return; fi
  echo "⚠️ 从 main 分支下载失败，尝试 master..."
  curl -fSL "$M" -o "$d"
}

main(){
  [ "$EUID" -ne 0 ] && echo "请使用 root 或 sudo 运行此脚本" >&2 && exit 1

  # 获取服务器公网 IP
  SERVER_IP=$(curl -s https://api.ipify.org)

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

  # 下载并解压
  pkg="frp_${FRP_VERSION#v}_linux_${frp_arch}.tar.gz"
  echo "⏳ 下载 FRP：https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${pkg}"
  curl -sL "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${pkg}" -o "$pkg"
  tar xzf "$pkg" --strip-components=1 && rm -f "$pkg"

  # 拉取 TLS 证书
  if [ "$TLS_ENABLE" = "true" ]; then
    mkdir -p "$(dirname "$TLS_CERT")"
    fetch_cert "$TLS_CERT_URL_MAIN" "$TLS_CERT_URL_MASTER" "$TLS_CERT"
    fetch_cert "$TLS_KEY_URL_MAIN"  "$TLS_KEY_URL_MASTER"  "$TLS_KEY"
    echo "🔐 TLS 证书下载完成"
  fi

  # 生成 frps.toml
  cat > frps.toml <<-EOF
[common]
bind_addr     = "0.0.0.0"
bind_port     = $BIND_PORT
kcp_bind_port = $BIND_UDP_PORT
token         = "$TOKEN"
allow_ports   = "$ALLOW_PORTS"
protocol      = "$PROTOCOL"
EOF
  if [ "$TLS_ENABLE" = "true" ]; then
    cat >> frps.toml <<-EOF

tls_enable     = true
tls_cert_file  = "$TLS_CERT"
tls_key_file   = "$TLS_KEY"
EOF
  fi

  # 安装并注册服务
  install -m755 frps /usr/local/bin/frps
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

  echo -e "\n🎉 FRP 服务端 安装完成！"
  echo "  • 配置文件：$INSTALL_DIR/frps.toml"
  echo "  • 日志目录：$INSTALL_DIR/frps.log"
  echo "  • 启动命令：systemctl status frps"
  echo -e "\n👉 客户端示例 frpc.toml:\n[common]\nserver_addr = \"$SERVER_IP\"\nserver_port = $BIND_PORT\ntoken = \"$TOKEN\"\nprotocol = \"$PROTOCOL\"\n\n[example]\ntype = \"tcp\"\nlocal_ip = \"127.0.0.1\"\nlocal_port = 39501\nremote_port = 39501"
}

main "$@"
