#!/usr/bin/env bash
#================================================================
# FRP 服务端 (frps) 一键安装脚本 —— 安装到 ~/.varfrp 隐藏目录
# 适用：Debian/Ubuntu, CentOS/RHEL, Alpine, Fedora…
# 使用：curl -sL <脚本地址> | sudo bash
#----------------------------------------------------------------
# —— 配置区 —— （在此修改后上传到 GitHub，即可一键在各系统部署）
FRP_VERSION=""                    # 指定版本 (e.g. v0.62.1)，留空则自动拉取最新
INSTALL_DIR="${HOME}/.varfrp"     # 安装目录（隐藏）
BIND_PORT=39000                     # 控制通道 TCP 端口
BIND_UDP_PORT=39001                 # UDP 打洞端口
TOKEN="ChangeMeToAStrongToken123" # 连接 Token，请务必改成强随机串
ALLOW_PORTS="39501-39510"         # 允许映射的业务端口范围
TLS_ENABLE="true"                 # 是否启用 TLS 加密 (true/false)
# 若启用 TLS，证书会从下面两条 URL 拉取
TLS_CERT_URL="https://raw.githubusercontent.com/sdkeio32/linux_frp/main/frps.crt"
TLS_KEY_URL="https://raw.githubusercontent.com/sdkeio32/linux_frp/main/frps.key"
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

main(){
  [ "$EUID" -ne 0 ] && echo "请使用 root 或 sudo 运行此脚本" >&2 && exit 1

  # 如果目录已存在，则视为重装，删除旧目录
  if [ -d "$INSTALL_DIR" ]; then
    echo "ℹ️ 检测到已存在安装目录 $INSTALL_DIR，正在删除旧版本..."
    rm -rf "$INSTALL_DIR"
  fi

  # 如果已注册 systemd 服务，则停止、禁用并移除旧服务文件
  if systemctl list-unit-files | grep -Fq "frps.service"; then
    echo "ℹ️ 检测到已存在 frps.service，停止并禁用..."
    systemctl stop frps || true
    systemctl disable frps || true
    rm -f /etc/systemd/system/frps.service
    systemctl daemon-reload
  fi

  detect_arch

  # 版本处理
  if [ -z "${FRP_VERSION}" ]; then
    get_latest_version
  else
    echo "ℹ️ 使用指定版本：$FRP_VERSION"
  fi

  mkdir -p "$INSTALL_DIR"
  cd "$INSTALL_DIR"

  # 下载并解压
  pkg="frp_${FRP_VERSION#v}_linux_${frp_arch}.tar.gz"
  url="https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${pkg}"
  echo "⏳ 下载FRP：${url}"
  curl -sL "$url" -o "$pkg"
  tar zxvf "$pkg" --strip-components=1
  rm -f "$pkg"

  # TLS 证书：从 GitHub 仓库拉取固定证书
  if [ "$TLS_ENABLE" = "true" ]; then
    mkdir -p "$(dirname "$TLS_CERT")"
    echo "⏳ 拉取固定 TLS 证书..."
    curl -sL "$TLS_CERT_URL" -o "$TLS_CERT"
    curl -sL "$TLS_KEY_URL" -o "$TLS_KEY"
    echo "🔐 TLS 证书已拉取：$TLS_CERT + $TLS_KEY"
  fi

  # 生成 frps.ini
  cat > "$INSTALL_DIR/frps.ini" <<-EOF
[common]
bind_addr      = 0.0.0.0
bind_port      = $BIND_PORT
bind_udp_port  = $BIND_UDP_PORT
token          = $TOKEN
allow_ports    = $ALLOW_PORTS
EOF

  if [ "$TLS_ENABLE" = "true" ]; then
    cat >> "$INSTALL_DIR/frps.ini" <<-EOF

tls_enable     = true
tls_cert_file  = $TLS_CERT
tls_key_file   = $TLS_KEY
EOF
  fi

  # 安装可执行文件
  install -m 755 "$INSTALL_DIR/frps" /usr/local/bin/frps

  # 写入 systemd 单元
  cat > /etc/systemd/system/frps.service <<-EOF
[Unit]
Description=frp Server (frps)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c $INSTALL_DIR/frps.ini
Restart=on-failure
LimitNOFILE=65536
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

  # 启动并开机自启
  systemctl daemon-reload
  systemctl enable --now frps

  echo
  echo "🎉 FRP 服务端 安装完成！"
  echo "  • 配置文件：$INSTALL_DIR/frps.ini"
  echo "  • 日志目录：$INSTALL_DIR/frps.log"
  echo "  • 启动命令：systemctl status frps"
  echo
  echo "👉 后续自定义："
  echo "   编辑 $INSTALL_DIR/frps.ini，修改端口/Token/映射范围等，"
  echo "   然后执行：systemctl restart frps"
}

main "$@"
