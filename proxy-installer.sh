#!/bin/bash
# Squid HTTPS Proxy Installer with Cloudflare Global API Key
# Supports Debian/Ubuntu

if [ "$(id -u)" != "0" ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Check OS compatibility
if ! grep -Eiq "(Debian|Ubuntu)" /etc/os-release; then
    echo "Error: Only Debian/Ubuntu are supported." >&2
    exit 1
fi

echo "Updating system and installing dependencies..."
apt update -y
apt install -y squid certbot python3-certbot-dns-cloudflare curl jq

echo "===== Squid HTTPS Proxy Setup ====="
read -p "1. Domain (e.g. proxy.example.com): " DOMAIN
while [[ -z "$DOMAIN" ]]; do
    read -p "Domain cannot be empty: " DOMAIN
done

read -p "2. Email for Let's Encrypt: " EMAIL
while [[ -z "$EMAIL" ]]; do
    read -p "Email cannot be empty: " EMAIL
done

echo "3. Cloudflare account email:"
read CF_EMAIL

echo "4. Cloudflare Global API Key (https://dash.cloudflare.com/profile/api-tokens):"
read -s CF_API_KEY
echo

read -p "5. Proxy username: " PROXY_USER
while [[ -z "$PROXY_USER" ]]; do
    read -p "Username cannot be empty: " PROXY_USER
done

read -s -p "6. Proxy password: " PROXY_PASS
echo
read -s -p "Confirm password: " PROXY_PASS2
echo
if [[ "$PROXY_PASS" != "$PROXY_PASS2" ]]; then
    echo "Error: Passwords do not match." >&2
    exit 1
fi

# Get Zone ID using Global API Key
echo "Fetching Cloudflare Zone ID for $DOMAIN..."
ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
    -H "X-Auth-Email: $CF_EMAIL" \
    -H "X-Auth-Key: $CF_API_KEY" \
    -H "Content-Type: application/json")

ZONE_ID=$(echo "$ZONE_RESPONSE" | jq -r '.result[0].id')
if [[ -z "$ZONE_ID" ]] || [[ "$ZONE_ID" == "null" ]]; then
    echo "Error: Failed to get Zone ID. Check domain and Global API Key permissions." >&2
    exit 1
fi

# Create Cloudflare credentials file for certbot
mkdir -p /root/.secrets
CLOUDFLARE_INI="/root/.secrets/cloudflare.ini"
cat > "$CLOUDFLARE_INI" <<EOF
dns_cloudflare_email = $CF_EMAIL
dns_cloudflare_api_key = $CF_API_KEY
EOF
chmod 600 "$CLOUDFLARE_INI"

# Request certificate with retry
echo "Requesting Let's Encrypt certificate (up to 3 attempts)..."
CERT_SUCCESS=false
for i in {1..3}; do
    if certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$CLOUDFLARE_INI" \
        --dns-cloudflare-propagation-seconds 60 \
        -d "$DOMAIN" \
        --email "$EMAIL" \
        --agree-tos \
        --non-interactive \
        --quiet; then
        CERT_SUCCESS=true
        break
    else
        echo "Attempt $i failed. Retrying in 10 seconds..."
        sleep 10
    fi
done

if [[ "$CERT_SUCCESS" != "true" ]]; then
    echo "Error: Certificate issuance failed after 3 attempts." >&2
    exit 1
fi

# Configure Squid
SQUID_CONF="/etc/squid/squid.conf"
cp "$SQUID_CONF" "${SQUID_CONF}.bak.$(date +%s)"

cat > "$SQUID_CONF" <<EOF
acl SSL_ports port 443
acl Safe_ports port 80 443
acl CONNECT method CONNECT

http_port 443 ssl-bump cert=/etc/letsencrypt/live/$DOMAIN/fullchain.pem key=/etc/letsencrypt/live/$DOMAIN/privkey.pem
https_port 443 ssl-bump cert=/etc/letsencrypt/live/$DOMAIN/fullchain.pem key=/etc/letsencrypt/live/$DOMAIN/privkey.pem

auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic children 5
auth_param basic realm "Squid Proxy"
auth_param basic credentialsttl 2 hours
acl authenticated_users proxy_auth REQUIRED
http_access allow authenticated_users
http_access deny all

ssl_bump server-first all
cache_mgr admin@$DOMAIN
cache_effective_user squid
cache_effective_group squid
EOF

# Set up authentication
apt install -y apache2-utils
htpasswd -b -c /etc/squid/passwd "$PROXY_USER" "$PROXY_PASS"
chown root:squid /etc/squid/passwd
chmod 640 /etc/squid/passwd

# Restart Squid
systemctl restart squid
systemctl enable squid

# Create management command
cat > /usr/local/bin/proxy << 'EOF'
#!/bin/bash
case "$1" in
    uninstall)
        systemctl stop squid
        systemctl disable squid
        apt remove -y squid certbot python3-certbot-dns-cloudflare apache2-utils
        rm -rf /etc/squid /etc/letsencrypt/live/*/ /root/.secrets/cloudflare.ini /usr/local/bin/proxy
        echo "Squid proxy uninstalled."
        ;;
    change-pass)
        read -p "New username: " USER
        read -s -p "New password: " PASS
        echo
        read -s -p "Confirm: " PASS2
        echo
        if [[ "$PASS" != "$PASS2" ]]; then
            echo "Passwords mismatch."
            exit 1
        fi
        htpasswd -b -c /etc/squid/passwd "$USER" "$PASS"
        chown root:squid /etc/squid/passwd
        chmod 640 /etc/squid/passwd
        systemctl restart squid
        echo "Password updated."
        ;;
    restart)
        systemctl restart squid
        echo "Squid restarted."
        ;;
    config)
        echo "Reconfigure: Edit /etc/squid/squid.conf manually, then run 'proxy restart'"
        ;;
    *)
        echo "Usage: proxy [change-pass|restart|uninstall|config]"
        ;;
esac
EOF

chmod +x /usr/local/bin/proxy

# Final notice
echo
echo -e "\033[1;32m✅ Installation completed!\033[0m"
echo "Proxy URL: https://$DOMAIN:443"
echo "Username: $PROXY_USER"
echo "Password: [hidden]"

echo
echo -e "\033[1;31m!!! SECURITY WARNING !!!\033[0m"
echo "You MUST change the default password immediately."
echo "Run this command now:"
echo "  proxy change-pass"
echo
read -p "Press Enter after changing your password... " -r
