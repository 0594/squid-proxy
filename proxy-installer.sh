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

# 获取用户输入（从标准输入读取）
DOMAIN=$(grep "DOMAIN=" squid-proxy-config | cut -d '=' -f2)
CF_TOKEN=$(grep "CF_TOKEN=" squid-proxy-config | cut -d '=' -f2)
PORT=$(grep "PORT=" squid-proxy-config | cut -d '=' -f2)
PORT=${PORT:-443}
EMAIL=$(grep "EMAIL=" squid-proxy-config | cut -d '=' -f2)
USERNAME=$(grep "USERNAME=" squid-proxy-config | cut -d '=' -f2)
USERNAME=${USERNAME:-proxy}
PASSWORD=$(grep "PASSWORD=" squid-proxy-config | cut -d '=' -f2)

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

# 验证证书有效性（自动重试机制）
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
    echo "8. 查看代理配置 (地址/端口/用户名)"
    echo "9. 退出"
    
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
            echo -e "\n\033[1;33m代理配置信息:\033[0m"
            echo "代理地址: https://$(grep -m1 DOMAIN squid-proxy-config | cut -d '=' -f2):${PORT}"
            echo "用户名: $(grep -m1 USERNAME squid-proxy-config | cut -d '=' -f2)"
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

# 清理配置文件
rm -f squid-proxy-config

# 完成信息
echo -e "\n\033[1;32m✅ 部署完成! 代理服务已启动\033[0m"
echo -e "代理地址: \033[1;34mhttps://$(grep -m1 DOMAIN squid-proxy-config | cut -d '=' -f2):${PORT}\033[0m"
echo -e "用户名: \033[1;34m$(grep -m1 USERNAME squid-proxy-config | cut -d '=' -f2)\033[0m"
echo -e "密码: \033[1;34m已设置 (不显示)\033[0m"
echo -e "\n\033[1;33m使用命令 'proxy' 管理代理服务\033[0m"
