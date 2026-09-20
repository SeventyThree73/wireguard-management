#!/bin/bash
# remove-peer.sh - 删除 WireGuard 用户（通过 config.json）

CONFIG_FILE="config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Configuration file 'config.json' not found!" >&2
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "❌ Missing 'jq' tool. Please install it: sudo apt install -y jq" >&2
  exit 1
fi

WG_CONF_PATH=$(jq -r '.wg_conf_path' "$CONFIG_FILE")
PEERS_DB_PATH=$(jq -r '.peers_db_path' "$CONFIG_FILE")

# === 主逻辑 ===
PEER_NAME=$1
if [ -z "$PEER_NAME" ]; then
  echo "Usage: $0 <peer-name>"
  exit 1
fi

# 校验用户名格式
if ! [[ "$PEER_NAME" =~ ^[a-zA-Z0-9_-]{3,20}$ ]]; then
  echo "❌ Username '$PEER_NAME' is invalid!" >&2
  exit 1
fi

# 检查用户是否存在于 peers.db
if [ ! -f "$PEERS_DB_PATH" ] || ! grep -q "^$PEER_NAME=" "$PEERS_DB_PATH"; then
  echo "❌ 用户 '$PEER_NAME' 不存在！" >&2
  exit 1
fi

# 从 .peers.db 中取出该用户的 IP（用于提示）
USER_IP=$(grep "^$PEER_NAME=" "$PEERS_DB_PATH" | cut -d'=' -f2)

# === 1. 从 wg0.conf 中移除对应的 [Peer] 块 ===
if [ -f "$WG_CONF_PATH" ]; then
  # 用 awk 精确删除：从 "# PEER_NAME" 注释行开始，直到下一个 "# xxx" 注释行之前
  TMP_CONF=$(mktemp)
  sudo awk -v marker="# $PEER_NAME" '
    $0 == marker { skip=1; next }
    skip && /^# [a-zA-Z0-9_-]+$/ { skip=0 }
    !skip { print }
  ' "$WG_CONF_PATH" > "$TMP_CONF"

  # 清理可能产生的连续多个空行（保留最多一个）
  awk 'NF { empties=0 } !NF { empties++; if (empties<=1) print }' "$TMP_CONF" > "${TMP_CONF}.2"
  mv "${TMP_CONF}.2" "$TMP_CONF"

  sudo cp "$TMP_CONF" "$WG_CONF_PATH"
  rm -f "$TMP_CONF"
  echo "✅ 已从 $WG_CONF_PATH 移除 [Peer] $PEER_NAME"
else
  echo "⚠️ $WG_CONF_PATH 不存在，跳过服务端配置修改"
fi

# === 2. 从 .peers.db 中移除记录 ===
sed -i "/^$PEER_NAME=/d" "$PEERS_DB_PATH"
echo "✅ 已从 $PEERS_DB_PATH 移除记录 ($PEER_NAME=$USER_IP)"

# === 3. 删除客户端配置文件（如存在） ===
CLIENT_CONF="./clients/$PEER_NAME.conf"
if [ -f "$CLIENT_CONF" ]; then
  rm -f "$CLIENT_CONF"
  echo "✅ 已删除客户端配置 $CLIENT_CONF"
fi

# === 4. 重启 WireGuard 使配置生效 ===
if systemctl is-active --quiet wg-quick@wg0 2>/dev/null || [ -f /etc/wireguard/wg0.conf ]; then
  echo "🔄 重启 WireGuard..."
  sudo wg-quick down wg0 2>/dev/null
  sudo wg-quick up wg0 2>/dev/null
  echo "✅ WireGuard 已重启"
fi

echo ""
echo "🎉 用户 '$PEER_NAME' 已彻底删除。"

