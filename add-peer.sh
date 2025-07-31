#!/bin/bash
# add-peer.sh - 为 WireGuard 添加用户（通过 config.json）

CONFIG_FILE="config.json"
PEERS_DB_PATH="./.peers.db"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Configuration file 'config.json' not found!" >&2
  echo "💡 Please create it based on 'config.json.example':" >&2
  echo "   cp config.json.example config.json" >&2
  echo "   edit config.json with your values (server_ip, public_ip, etc.)" >&2
  exit 1
fi

# 使用 jq 解析 JSON（需安装 jq）
if ! command -v jq &> /dev/null; then
  echo "❌ Missing 'jq' tool. Please install it:" >&2
  echo "   sudo apt install -y jq" >&2
  exit 1
fi

SERVER_IP=$(jq -r '.server_ip' "$CONFIG_FILE")
PUBLIC_IP=$(jq -r '.public_ip' "$CONFIG_FILE")
MAX_USERS=$(jq -r '.max_users' "$CONFIG_FILE")
WG_CONF_PATH=$(jq -r '.wg_conf_path' "$CONFIG_FILE")
PEERS_DB_PATH=$(jq -r '.peers_db_path' "$CONFIG_FILE")
LISTEN_PORT=$(jq -r '.listen_port' "$CONFIG_FILE")

# 自动提取 IP_PREFIX
if [ -z "$IP_PREFIX" ] || [ "$IP_PREFIX" = "null" ]; then
  IP_PREFIX=$(echo "$SERVER_IP" | sed 's/\.[0-9]*$//')
fi

# 校验 SERVER_IP 是否合法
if ! [[ "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ SERVER_IP 格式不合法（应为 IPv4）: $SERVER_IP"
  exit 1
fi

# 校验 PUBLIC_IP 是否合法
if ! [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ PUBLIC_IP 格式不合法（应为 IPv4）: $PUBLIC_IP"
  exit 1
fi

# === 主逻辑 ===
PEER_NAME=$1
if [ -z "$PEER_NAME" ]; then
  echo "Usage: $0 <peer-name>"
  exit 1
fi

# === 确保 wg0.conf 存在，不存在则创建基础配置 ===
if ! sudo -u root test -f "$WG_CONF_PATH"; then
  echo "⚠️ $WG_CONF_PATH not found. Creating it with basic interface config..." >&2

  # 创建目录（如果不存在）
  mkdir -p "$(dirname "$WG_CONF_PATH")"

  # 生成密钥对
  PRIVATE_KEY_SERVER=$(wg genkey)
  PUBLIC_KEY_SERVER=$(echo "$PRIVATE_KEY_SERVER" | wg pubkey)

  # 写入基础配置（Server IP + ListenPort）
    sudo tee -a "$WG_CONF_PATH" <<EOF >/dev/null
[Interface]
Address = $SERVER_IP/24
ListenPort = $LISTEN_PORT
PrivateKey = $PRIVATE_KEY_SERVER

# Allow forwarding (required for NAT)
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

  echo "✅ Created $WG_CONF_PATH with default interface." >&2
fi

# === 确保 .peers.db 存在 ===
if [ ! -f "$PEERS_DB_PATH" ]; then
  echo "⚠️ $PEERS_DB_PATH not found. Creating empty db..." >&2
  touch "$PEERS_DB_PATH"
  echo "✅ Created $PEERS_DB_PATH." >&2
fi

# 检查用户名是否合规（正则匹配）
if ! [[ "$PEER_NAME" =~ ^[a-zA-Z0-9_-]{3,20}$ ]]; then
  echo "❌ Username '$PEER_NAME' is invalid!" >&2
  echo "   ✅ Must be 3–20 chars long" >&2
  echo "   ✅ Only letters, numbers, underscore '_', and hyphen '-' allowed" >&2
  echo "   ❌ No spaces, special chars (@, #, /)" >&2
  exit 1
fi

# 检查是否已存在该用户名
if grep -q "^$PEER_NAME=" "$PEERS_DB_PATH"; then
  echo "❌ 用户 '$PEER_NAME' 已存在！"
  exit 1
fi

# 检查是否达到上限
COUNT=$(wc -l < "$PEERS_DB_PATH" 2>/dev/null || echo 0)
if [ "$COUNT" -ge "$MAX_USERS" ]; then
  echo "❌ 用户数量已达上限 ($MAX_USERS)！"
  exit 1
fi

# === 从 .peers.db 中找到第一个空闲 IP ===
IP_PREFIX="${IP_PREFIX:-$(echo "$SERVER_IP" | sed 's/\.[0-9]*$//')}"

# 获取所有已用 IP 并排序（去重）
USED_IPS=$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$PEERS_DB_PATH" 2>/dev/null | sort -n | uniq)

# 如果没有用户，直接返回 2（1 是服务器）
if [ -z "$USED_IPS" ]; then
  NEXT_IP="2"
else
  # 找到第一个缺失的数字（从 2 开始）
  for i in $(seq 2 254); do
    if ! echo "$USED_IPS" | grep -q "\.$i$"; then
      NEXT_IP="$i"
      break
    fi
  done
fi

# 如果找不到空闲 IP（超过 254），报错
if [ -z "$NEXT_IP" ] || [ "$NEXT_IP" -gt 254 ]; then
  echo "❌ No available IP in range (10.0.0.2–10.0.0.254)!" >&2
  exit 1
fi

IP="${IP_PREFIX}.${NEXT_IP}"

# 生成密钥对
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
PRESHARED_KEY=$(wg genpsk)

# 追加到主配置文件
sudo tee -a "$WG_CONF_PATH" <<EOF >/dev/null

# $PEER_NAME
[Peer]
PublicKey = $PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = $IP/32
EOF

# 重新加载配置
sudo wg-quick down wg0
sudo wg-quick up wg0

# 记录到数据库
echo "$PEER_NAME=$IP" >> "$PEERS_DB_PATH"

# === 保存客户端配置到本地 clients/ 目录 ===
CLIENTS_DIR="./clients"
mkdir -p "$CLIENTS_DIR"

CLIENT_CONF_PATH="$CLIENTS_DIR/$PEER_NAME.conf"

cat > "$CLIENT_CONF_PATH" <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $IP/32
DNS = 8.8.8.8

# $PEER_NAME
[Peer]
PublicKey = $(sudo cat $WG_CONF_PATH | grep PrivateKey | head -n1 |  cut -d' ' -f3 | wg pubkey)
PresharedKey = $PRESHARED_KEY
Endpoint = $PUBLIC_IP:$LISTEN_PORT
AllowedIPs = ${IP_PREFIX}.0/24
PersistentKeepalive = 25
EOF

echo "✅ Client config saved to: $CLIENT_CONF_PATH"
