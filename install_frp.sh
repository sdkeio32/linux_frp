#!/usr/bin/env bash
#================================================================
# FRP 服务端 (frps) 一键安装脚本 —— 安装到 ~/.varfrp 隐藏目录
# 适用：Debian/Ubuntu, CentOS/RHEL, Alpine, Fedora…
# 使用：curl -sL <脚本地址> | sudo bash
#----------------------------------------------------------------
# —— 配置区 —— （在此修改后上传到 GitHub，即可一键在各系统部署）
FRP_VERSION=""                     # 指定版本 (e.g. v0.62.1)，留空则自动拉取最新
INSTALL_DIR="${HOME}/.varfrp"      # 安装目录（隐藏）
BIND_PORT=39000                      # 控制通道 TCP 端口
BIND_UDP_PORT=39001                  # UDP 打洞端口
TOKEN="ChangeMeToAStrongToken123"  # 连接 Token，请务必改成强随机串
ALLOW_PORTS="39501-39510"          # 允许映射的业务端口范围
TLS_ENABLE="true"                  # 是否启用 TLS 加密 (true/false)
# 若启用 TLS，证书会从下面两条 URL 拉取，优先 main 分支，失败则尝试 master
TLS_CERT_URL_MAIN="https://raw.githubusercontent.com/sdkeio32/linux_frp/main/frps.crt"
TLS_KEY_URL_MAIN="https://raw.githubusercontent.com/sdkeio32/linux_frp/main/frps.key"
TLS_CERT_URL_MASTER="https://raw.githubusercontent.com/sdkeio32/linux_frp/master/frps.crt"
TLS_KEY_URL_MASTER="https://raw.githubusercontent.com/sdkeio32/linux_frp/master/frps.key"
TLS_CERT="${INSTALL_DIR}/cert/frps.crt"
TLS_KEY="${INSTALL_DIR}/cert/frps.key"
# —— 配置区结束 ——
#================================================================

set -euo pipefail

# 检测 CPU 架构，映射 FRP 下载包名
detect_arch(){
  arch=$(uname -m)
  case "$arch" in
    x86_64) frp_arch=amd64 ;;
    aarch64|arm64) frp_arch=arm64 ;;
    armv7l) frp_arch=armv7 ;;
    *) echo "❌ 当前架构 $arch 不受支持" >&2; exit 1 ;;
  esac
}

# 拉取最新 Release Tag
get_latest_version(){
  echo "⏳ 检测 FRP 最新版本..."
  FRP_VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest \
    | grep '"tag_name"' | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')
  echo "✅ 最新版本：$FRP_VERSION"
}

# 下载证书，支持 main/master 分支
fetch_cert(){
  local url_main=$1 url_master=$2 dest=$3
  if curl -fSL "$url_main" -o "$dest"; then return; fi
  echo "⚠️ 从 main 分支下载失败，尝试 master 分支..."
  curl -fSL "$url_master" -o "$dest"
}

main(){
  [ "$EUID" -ne 0 ] && echo "请使用 root 或 sudo 运行此脚本" >&2 && exit 1

  # 重装清理
  if [ -d "$INSTALL_DIR" ]; then
    echo "ℹ️ 检测到已存在安装目录 $INSTALL_DIR，正在删除旧版本..."
    rm -rf "$INSTALL_DIR"
  fi
  # 清理旧服务
  if systemctl list-unit-files | grep -Fq "frps.service"; then
    echo "ℹ️ 停止并移除旧的 frps.service..."
    systemctl stop frps || true
    systemctl disable frps || true
    rm -f /etc/systemd/system/frps.service
    systemctl daemon-reload
  fi

  detect_arch
  [ -z "${FRP_VERSION}" ] && get_latest_version || echo "ℹ️ 使用指定版本：$FRP_VERSION"

  mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"

  # 下载并解压
  pkg="frp_${FRP_VERSION#v}_linux_${frp_arch}.tar.gz"
  url="https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${pkg}"
  echo "⏳ 下载 FRP：${url}"
  curl -sL "$url" -o "$pkg"
  tar zxvf "$pkg" --strip-components=1
  rm -f "$pkg"

  # 拉取 TLS 证书
  if [ "$TLS_ENABLE" = "true" ]; then
    mkdir -p "$(dirname "$TLS_CERT")"
    echo "⏳ 拉取 TLS 证书..."
    fetch_cert "$TLS_CERT_URL_MAIN" "$TLS_CERT_URL_MASTER" "$TLS_CERT"
    fetch_cert "$TLS_KEY_URL_MAIN"  "$TLS_KEY_URL_MASTER"  "$TLS_KEY"
    echo "🔐 已下载 TLS 证书和私钥"
  fi

  # 生成 frps.toml
  cat > "$INSTALL_DIR/frps.toml" <<-EOF
[common]
bind_addr = "0.0.0.0"
bind_port = $BIND_PORT
bind_udp_port = $BIND_UDP_PORT
token = "$TOKEN"
allow_ports = "$ALLOW_PORTS"
# 优先使用 UDP，当 UDP 不可用时回退到 TCP
protocol = "udp"
EOF

  if [ "$TLS_ENABLE" = "true" ]; then
    cat >> "$INSTALL_DIR/frps.toml" <<-EOF

tls_enable = true
tls_cert_file = "$TLS_CERT"
tls_key_file = "$TLS_KEY"
EOF
  fi

  # 安装可执行文件
  install -m 755 "$INSTALL_DIR/frps" /usr/local/bin/frps

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

  echo -e "\n🎉 FRP 服务端 安装完成！"
  echo "  • 配置文件：$INSTALL_DIR/frps.toml"
  echo "  • 日志目录：$INSTALL_DIR/frps.log"
  echo "  • 启动命令：systemctl status frps"
  echo
  echo "👉 客户端 (frpc) 示例配置文件内容："
  cat <<-EOT
# frpc.toml 示例
[common]
server_addr = "<服务器IP>"
server_port = $BIND_PORT
token = "$TOKEN"
protocol = "udp"

[example]
type = "tcp"
local_ip = "127.0.0.1"
local_port = 80
remote_port = 39501
EOT
}

main "$@"
