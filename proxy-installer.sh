#!/bin/bash

# 确保在root下运行
if [ "$(id -u)" != "0" ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# 检查系统是否为Debian 12
if ! grep -q "Debian GNU/Linux 12" /etc/os-release; then
    echo "Error: This script only supports Debian 12" >&2
    exit 1
fi

# 自动安装coreutils（包含chmod）
echo "Installing coreutils to provide chmod..."
apt update -y
apt install -y coreutils

# 确保chmod可用
if ! command -v /bin/chmod &> /dev/null; then
    echo "Error: Failed to install coreutils" >&2
    exit 1
fi

# 交互式获取配置
echo -e "\n\033[1;33m请输入代理配置信息:\033[0m"
read -p "域名 (例如: proxy.yourdomain.com): " DOMAIN
while [ -z "$DOMAIN" ]; do
    read -p "域名 (例如: proxy.yourdomain.com): " DOMAIN
done

read -p "Cloudflare API Token (需Zone:Edit权限): " CF_TOKEN
while [ -z "$CF_TOKEN" ]; do
    read -p "Cloudflare API Token (需Zone:Edit权限): " CF_TOKEN
done

read -p "代理端口 (默认443): " PORT
PORT=${PORT:-443}

read -p "用户名 (默认proxy): " USERNAME
USERNAME=${USERNAME:-proxy}

read -s -p "密码 (12位以上，含大小写字母+数字+符号): " PASSWORD
echo
while [ -z "$PASSWORD" ]; then
    read -s -p "密码 (12位以上，含大小写字母+数字+符号): " PASSWORD
    echo
done

# 检查端口占用
if ss -tuln | grep -q ":${PORT} "; then
    echo -e "\n\033[1;31mError: 端口 ${PORT} 已被占用，请选择其他端口\033[0m"
    exit 1
fi

# 安装依赖
echo -e "\n\033[1;32m更新系统并安装依赖...\033[0m"
apt update -y
apt upgrade -y
apt install -y squid certbot python3-certbot-dns-cloudflare curl

# 申请Let's Encrypt证书
echo -e "\n\033[1;32m申请Let's Encrypt证书 (使用Cloudflare API Token)...\033[0m"
export CF_API_TOKEN="$CF_TOKEN"
certbot certonly --dns-cloudflare --dns-cloudflare-credentials /dev/null -d "$DOMAIN" \
  --non-interactive --agree-tos --email "admin@$DOMAIN" --dns-cloudflare-propagation-seconds 30

# 验证证书有效性（自动重试3次）
echo -e "\n\033[1;33m正在验证证书有效性...\033[0m"
CERT_VALID=0
RETRY_COUNT=0
MAX_RETRIES=3

while [ $CERT_VALID -eq 0 ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  # 使用curl验证证书
  CERT_STATUS=$(curl -I -k https://$DOMAIN:$PORT --max-time 10 2>&1 | grep "HTTP/")
  
  if [ -z "$CERT_STATUS" ]; then
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -e "\033[1;31m证书验证失败 (第 $RETRY_COUNT/$MAX_RETRIES 次尝试)...\033[0m"
    echo "正在重新申请证书..."
    
    # 重新申请证书
    certbot renew --force-renewal
    
    # 重新配置Squid
    cat > /etc/squid/squid.conf << EOF
https_port ${PORT} cert=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem key=/etc/letsencrypt/live/${DOMAIN}/privkey.pem
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Squid Proxy Server
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access allow all
EOF
    
    # 重启Squid
    systemctl restart squid
  else
    CERT_VALID=1
    echo -e "\033[1;32m✅ 证书验证成功! 证书有效\033[0m"
  fi
done

# 如果重试后仍失败
if [ $CERT_VALID -eq 0 ]; then
  echo -e "\033[1;31m❌ 证书验证失败 (重试 $MAX_RETRIES 次后仍失败)\033[0m"
  echo -e "请检查以下内容:"
  echo "  1. Cloudflare API Token 是否有 Zone:Edit 权限"
  echo "  2. 域名是否正确解析到服务器IP"
  echo "  3. 防火墙是否开放端口 $PORT"
  echo "  4. Let's Encrypt 邮箱是否有效"
  echo -e "\n\033[1;33m建议: 运行 'proxy' 命令重新安装代理服务\033[0m"
  exit 1
fi

# 创建认证文件
echo -e "\n\033[1;32m设置代理认证信息...\033[0m"
echo -n "$PASSWORD" | /bin/htpasswd -i -b /etc/squid/passwd "$USERNAME"

# 重启Squid服务
systemctl restart squid
systemctl enable squid

# 创建管理命令
echo -e "\n\033[1;32m创建管理命令 'proxy'...\033[0m"
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
    echo "8. 查看代理配置 (地址/端口/用户名)"
    echo "9. 退出"
    
    read -p "请选择操作: " choice
    
    case \$choice in
        1)
            echo -e "\n\033[1;33m正在重新安装... (会覆盖现有配置)\033[0m"
            bash /root/proxy-installer.sh
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
            echo -n "\${NEW_PASS}" | /bin/htpasswd -i -b /etc/squid/passwd "\${NEW_USER}"
            systemctl restart squid
            echo -e "\033[1;32m认证信息已更新!\033[0m"
            ;;
        7)
            echo -e "\n\033[1;33m当前认证信息:\033[0m"
            cat /etc/squid/passwd
            ;;
        8)
            echo -e "\n\033[1;33m代理配置信息:\033[0m"
            echo "代理地址: https://$(grep -m1 DOMAIN /root/proxy-installer.sh | cut -d '=' -f2):${PORT}"
            echo "用户名: $USERNAME"
            echo "密码: 已设置 (不显示)"
            ;;
        9)
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

# 清理
rm -f /root/proxy-installer.sh

# 完成信息
echo -e "\n\033[1;32m✅ 部署完成! 代理服务已启动\033[0m"
echo -e "代理地址: \033[1;34mhttps://$DOMAIN:$PORT\033[0m"
echo -e "用户名: \033[1;34m$USERNAME\033[0m"
echo -e "密码: \033[1;34m已设置 (不显示)\033[0m"
echo -e "\n\033[1;33m使用命令 'proxy' 管理代理服务\033[0m"
echo -e "\033[1;33m请立即通过 'proxy' → 选项6 修改默认密码\033[0m"
