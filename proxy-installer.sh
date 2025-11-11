#!/bin/bash

# 检查是否为root用户
if [ "$(id -u)" != "0" ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# 检查系统是否为Debian 12
if ! grep -q "Debian GNU/Linux 12" /etc/os-release; then
    echo "Error: This script only supports Debian 12" >&2
    exit 1
fi

# 更新系统并安装依赖
echo "Updating system and installing dependencies..."
apt update -y
apt upgrade -y
apt install -y squid certbot python3-certbot-dns-cloudflare curl

# 获取用户输入
echo -e "\n\033[1;36m=== 请按提示输入以下信息（所有输入将隐藏显示） ===\033[0m"
read -p "1. 域名 (e.g. proxy.example.com): " DOMAIN
read -s -p "2. Cloudflare API Token (需Zone:Edit权限): " CF_TOKEN
echo
read -p "3. 代理端口 (默认443): " PORT
PORT=${PORT:-443}
read -p "4. Let's Encrypt邮箱: " EMAIL
read -p "5. 代理用户名 (默认proxy): " USERNAME
USERNAME=${USERNAME:-proxy}
read -s -p "6. 代理密码: " PASSWORD
echo

# 检查端口占用
if ss -tuln | grep -q ":${PORT} "; then
    echo -e "\n\033[1;31mError: 端口 ${PORT} 已被占用，请选择其他端口\033[0m"
    exit 1
fi

# 申请Let's Encrypt证书
echo -e "\n\033[1;32m申请Let's Encrypt证书 (使用Cloudflare API Token)...\033[0m"
export CF_API_TOKEN="$CF_TOKEN"
certbot certonly --dns-cloudflare --dns-cloudflare-credentials /dev/null -d "$DOMAIN" \
  --non-interactive --agree-tos --email "$EMAIL" --dns-cloudflare-propagation-seconds 30

# 备份Squid配置
cp /etc/squid/squid.conf /etc/squid/squid.conf.bak

# 配置Squid HTTPS代理
echo -e "\n\033[1;32m配置Squid HTTPS代理...\033[0m"
cat > /etc/squid/squid.conf << EOF
# HTTPS代理配置
https_port ${PORT} cert=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem key=/etc/letsencrypt/live/${DOMAIN}/privkey.pem

# 基础认证配置
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Squid Proxy Server
acl authenticated proxy_auth REQUIRED
http_access allow authenticated

# 允许所有请求（生产环境建议添加ACL限制）
http_access allow all
EOF

# 创建认证文件
echo -e "\n\033[1;32m设置代理认证信息...\033[0m"
echo -n "${PASSWORD}" | htpasswd -i -b /etc/squid/passwd "${USERNAME}"

# 重启Squid服务
systemctl restart squid
systemctl enable squid

# 创建管理命令
echo -e "\n\033[1;32m创建管理命令 'proxy'...\033[0m"
SCRIPT_PATH=$(realpath "$0")
cat > /usr/local/bin/proxy << EOF
#!/bin/bash

# 检查root权限
if [ "\$(id -u)" != "0" ]; then
    echo "Error: This command must be run as root" >&2
    exit 1
fi

# 管理菜单
while true; do
    clear
    echo -e "\033[1;34m===== Squid Proxy 管理系统 =====\033[0m"
    echo "1. 重新安装 (覆盖现有配置)"
    echo "2. 卸载代理服务"
    echo "3. 修改配置 (编辑squid.conf)"
    echo "4. 启动代理服务"
    echo "5. 停止代理服务"
    echo "6. 修改认证信息 (用户名/密码)"
    echo "7. 查看当前认证信息"
    echo "8. 退出"
    
    read -p "请选择操作: " choice
    
    case \$choice in
        1)
            echo -e "\n\033[1;33m正在重新安装... (会覆盖现有配置)\033[0m"
            bash "$SCRIPT_PATH"
            exit
            ;;
        2)
            echo -e "\n\033[1;31m卸载代理服务 (将删除所有配置)...\033[0m"
            systemctl stop squid
            rm -f /etc/squid/squid.conf
            rm -f /etc/squid/passwd
            rm -f /etc/squid/squid.conf.bak
            apt remove -y squid certbot
            rm -f /usr/local/bin/proxy
            echo -e "\033[1;32m卸载完成! 服务已停止并移除所有配置\033[0m"
            ;;
        3)
            echo -e "\n\033[1;33m正在打开配置文件: /etc/squid/squid.conf\033[0m"
            nano /etc/squid/squid.conf
            systemctl restart squid
            ;;
        4)
            systemctl start squid
            echo -e "\033[1;32m代理服务已启动\033[0m"
            ;;
        5)
            systemctl stop squid
            echo -e "\033[1;32m代理服务已停止\033[0m"
            ;;
        6)
            read -p "输入新用户名: " NEW_USER
            read -s -p "输入新密码: " NEW_PASS
            echo
            echo -n "\${NEW_PASS}" | htpasswd -i -b /etc/squid/passwd "\${NEW_USER}"
            systemctl restart squid
            echo -e "\033[1;32m认证信息已更新!\033[0m"
            ;;
        7)
            echo -e "\n\033[1;33m当前认证信息:\033[0m"
            cat /etc/squid/passwd
            ;;
        8)
            echo -e "\033[1;32m退出管理菜单\033[0m"
            exit
            ;;
        *)
            echo -e "\033[1;31m无效选项，请重新输入\033[0m"
            ;;
    esac
    sleep 1
done
EOF
chmod +x /usr/local/bin/proxy

# 完成信息
echo -e "\n\033[1;32m✅ 部署完成! 代理服务已启动\033[0m"
echo -e "访问地址: \033[1;34mhttps://${DOMAIN}:${PORT}\033[0m"
echo -e "用户名: \033[1;34m${USERNAME}\033[0m"
echo -e "密码: \033[1;34m${PASSWORD}\033[0m"
echo -e "\n\033[1;33m使用命令 'proxy' 管理代理服务\033[0m"
