# wireguard-management

WireGuard VPN 用户管理工具，支持自动分配 IP、生成密钥对、生成客户端配置文件。

## 注意事项
* 需要在服务器中开启相应端口的 UDP 转发
* 脚本需要 root 权限运行
* 从 Windows 上传脚本到 Linux 后，需先转换换行符：`sed -i 's/\r$//' *.sh`

## 环境准备
```bash
# Ubuntu 24.04
sudo apt update && sudo apt install -y wireguard resolvconf jq
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf

# 可选，二维码工具
sudo apt install -y qrencode
```

## 快速开始

### 拷贝 `config.json` 文件
```bash
cp config.json.example config.json
```

### 配置 `config.json` 内容
```json
{
    "server_ip": "10.0.8.1",
    "public_ip": "填入可用的公网IP",
    "max_users": 200,
    "wg_conf_path": "/etc/wireguard/wg0.conf",
    "peers_db_path": "./.peers.db",
    "listen_port": "51820"
}
```

| 字段 | 说明 |
|------|------|
| `server_ip` | WireGuard 内网网段 IP（一般不用改） |
| `public_ip` | 服务器公网 IP（**必填**，否则客户端无法连接） |
| `max_users` | 最大用户数（默认 200） |
| `wg_conf_path` | WireGuard 配置文件路径 |
| `peers_db_path` | 用户数据库路径 |
| `listen_port` | WireGuard 监听端口 |

### 添加账号
```bash
sudo bash add-peer.sh <用户名>

# 示例
sudo bash add-peer.sh alice
sudo bash add-peer.sh bob
```

**用户名规则**：3-20 字符，仅允许字母、数字、下划线 `_`、连字符 `-`

### 删除账号
```bash
sudo bash remove-peer.sh <用户名>

# 示例
sudo bash remove-peer.sh alice
```

## 查看 wg 状态

```bash
sudo wg show
```

## conf 文件生成二维码

```bash
qrencode -t ansiutf8 < clients/client.conf
```

## 文件结构

```
wireguard-management/
├── add-peer.sh              # 添加用户脚本
├── remove-peer.sh           # 删除用户脚本
├── config.json              # 配置文件（需自行创建，不提交到 Git）
├── config.json.example      # 配置文件示例
├── .peers.db                # 用户数据库（自动生成，不提交到 Git）
├── clients/                 # 客户端配置目录（自动生成，不提交到 Git）
│   ├── alice.conf
│   └── bob.conf
└── README.md
```
