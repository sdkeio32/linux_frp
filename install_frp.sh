#!/usr/bin/env bash
#================================================================
# FRP 服务端 卸载脚本 —— 停用并删除所有 frp 相关内容
# 适用：Debian/Ubuntu, CentOS/RHEL, Alpine, Fedora…
# 使用：curl -sL <脚本地址> | sudo bash
#================================================================

set -euo pipefail

echo "ℹ️ 正在卸载所有 frp 相关内容…"

# 1. 停止并禁用 systemd 服务
if systemctl list-unit-files | grep -q '^frps\.service'; then
  echo "⏹️ 停止 frps.service"
  systemctl stop frps || true
  echo "🔒 禁用 frps.service"
  systemctl disable frps || true
  echo "🗑️ 删除 /etc/systemd/system/frps.service"
  rm -f /etc/systemd/system/frps.service
  systemctl daemon-reload
fi

# 2. 停止并禁用 frpc (if used)
if systemctl list-unit-files | grep -q '^frpc\.service'; then
  echo "⏹️ 停止 frpc.service"
  systemctl stop frpc || true
  echo "🔒 禁用 frpc.service"
  systemctl disable frpc || true
  echo "🗑️ 删除 /etc/systemd/system/frpc.service"
  rm -f /etc/systemd/system/frpc.service
  systemctl daemon-reload
fi

# 3. 杀掉所有正在运行的 frps/frpc 进程
echo "⚔️ 杀掉所有 frps/frpc 进程"
pkill -f frps || true
pkill -f frpc || true

# 4. 删除可执行文件
echo "🗑️ 删除 /usr/local/bin/frps"
rm -f /usr/local/bin/frps
echo "🗑️ 删除 /usr/local/bin/frpc"
rm -f /usr/local/bin/frpc

# 5. 删除安装目录
if [ -d "${HOME}/.varfrp" ]; then
  echo "🗑️ 删除安装目录 ${HOME}/.varfrp"
  rm -rf "${HOME}/.varfrp"
fi

# 6. 删除日志文件
echo "🗑️ 删除 /var/log/frps.log"
rm -f /var/log/frps.log || true
echo "🗑️ 删除 /var/log/frpc.log"
rm -f /var/log/frpc.log || true

# 7. 清理防火墙规则（如果是 ufw/firewall-cmd/iptables 添加的范围规则）
echo "🧹 清理防火墙规则（如存在）"
if command -v ufw &>/dev/null; then
  ufw delete allow 39000:40000/tcp || true
  ufw delete allow 39000:40000/udp || true
fi
if command -v firewall-cmd &>/dev/null; then
  firewall-cmd --remove-port=39000-40000/tcp || true
  firewall-cmd --remove-port=39000-40000/udp || true
fi
# 对 iptables 规则，需手动调整索引或使用 iptables-save/restore
# 提示用户手动清理
echo "⚠️ 若使用 iptables 手动添加规则，请检查并删除对应 INPUT 规则："
echo "   iptables -L INPUT --line-numbers | grep '39000:40000'"

echo "✅ FRP 已全部卸载完成！"
