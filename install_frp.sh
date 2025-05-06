#!/usr/bin/env bash
#================================================================
# 安全版 FRP 服务端 (frps) 一键安装脚本 —— 简化无自更新功能
# 仅从指定固定 URL 拉取必要文件，无自动覆盖自身逻辑
# 适用：Debian/Ubuntu, CentOS/RHEL, Alpine, Fedora…
# 使用：curl -sL <脚本地址> | sudo bash
#================================================================

set -euo pipefail

# —— 配置区 ——
FRP_VERSION=""                     # 指定 FRP 版本 (留空则自动获取最新)
INSTALL_DIR="${HOME}/.varfrp"      # 安装目录（隐藏）
BIND_PORT=39000                     # 控制通道 TCP 端口
QUIC_BIND_PORT=39001                # QUIC(UDP) 控制通道端口
TOKEN="ChangeMeToAStrongToken123" # 连接 Token，请务必改成强随机串
ALLOW_PORTS="39501-39510"         # 允许映射的业务端口范围
TLS_ENABLE="true"                 # 是否启用 TLS 加密
# 固定证书地址
TLS_CERT_URL="https://raw.githubusercontent.com/sdkeio32/linux_frp/main/frps.crt"
TLS_KEY_URL="https://raw.githubusercontent.com/sdkeio32/linux_frp/main/frps.key"
#——配置区结束——

detect_arch() {
  case "$(uname -m)" in
    x86_64) frp_arch=amd64   ;; 
    aarch64|arm64) frp_arch=arm64 ;; 
    armv7l) frp_arch=armv7  ;; 
    *) echo "❌ 架构 $(uname -m) 不支持" >&2; exit 1 ;; 
  esac
}

get_latest_version() {
  echo "⏳ 检测 FRP 最新版本..."
  FRP_VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest \
    | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
  echo "✅ 最新版本：$FRP_VERSION"
}

main(){
  [ "$EUID" -ne 0 ] && echo "请使用 root 或 sudo 运行" >&2 && exit 1

  # 清理旧版本
  systemctl stop frps 2>/dev/null || true
  systemctl disable frps 2>/dev/null || true
  rm -f /etc/systemd/system/frps.service
  pkill frps 2>/dev/null || true
  rm -rf "$INSTALL_DIR"

  detect_arch
  [ -z "$FRP_VERSION" ] && get_latest_version || echo "ℹ️ 使用指定版本：$FRP_VERSION"

  mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"

  # 下载并解压 FRP
  pkg="frp_${FRP_VERSION#v}_linux_${frp_arch}.tar.gz"
  url="https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${pkg}"
  echo "⏳ 下载 FRP: $url"
  curl -sL "$url" -o "$pkg"
  tar xzf "$pkg" --strip-components=1 && rm -f "$pkg"

  # 拉取 TLS 证书
  if [ "$TLS_ENABLE" = "true" ]; then
    mkdir -p cert
    curl -fsSL "$TLS_CERT_URL" -o cert/frps.crt
    curl -fsSL "$TLS_KEY_URL" -o cert/frps.key
    echo "🔐 TLS 证书就绪"
  fi

  # 生成 frps.toml
  cat > frps.toml <<-EOF
[common]
bind_addr      = "0.0.0.0"
bind_port      = $BIND_PORT
quic_bind_port = $QUIC_BIND_PORT
token          = "$TOKEN"
allow_ports    = "$ALLOW_PORTS"
protocol       = "quic"

# TLS 配置
tls_enable     = true
tls_cert_file  = "$INSTALL_DIR/cert/frps.crt"
tls_key_file   = "$INSTALL_DIR/cert/frps.key"
EOF

  # 安装二进制
  install -m755 frps /usr/local/bin/frps

  # 放行防火墙端口
  if command -v ufw &>/dev/null; then
    ufw allow 39000:40000/tcp
    ufw allow 39000:40000/udp
  elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --add-port=39000-40000/tcp
    firewall-cmd --add-port=39000-40000/udp
  else
    iptables -I INPUT -p tcp --dport 39000:40000 -j ACCEPT
    iptables -I INPUT -p udp --dport 39000:40000 -j ACCEPT
  fi

  # 创建 systemd 服务
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
  echo -e "\n🎉 安装完成，QUIC 控制通道 UDP $QUIC_BIND_PORT 已就绪"
  echo -e "客户端示例 frpc.toml:\n[common]\nserver_addr = \"$SERVER_IP\"\nserver_port = $BIND_PORT\ntoken = \"$TOKEN\"\nprotocol = \"quic\"\n\n[example]\ntype = \"tcp\"\nlocal_ip = \"127.0.0.1\"\nlocal_port = 80\nremote_port = 39501"
}

main "$@"
