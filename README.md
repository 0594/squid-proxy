# Squid HTTPS 代理与 Let's Encrypt 无缝集成 (Debian 12)

![Squid Proxy](https://avatars.githubusercontent.com/u/363029?s=200&v=4)

> 一键部署 HTTPS 代理服务，支持 Cloudflare API Token 申请证书，带认证管理菜单，适用于生产环境。

## 📌 仓库说明
- **仓库地址**: [https://github.com/0594/squid-proxy](https://github.com/0594/squid-proxy)
- **系统要求**: Debian 12 (仅支持此版本)
- **功能亮点**:
  - 无缝集成 Let's Encrypt + Cloudflare API Token 证书申请
  - 支持自定义代理端口、用户名/密码
  - 一键部署后通过 `proxy` 命令管理服务
  - 详细中文部署文档
  - 适用于生产环境的稳定配置

---

## 🔧 快速部署指南

### 1. 准备工作
- 确保已配置 Cloudflare DNS (A记录指向服务器IP)
- 获取 Cloudflare API Token (需 **Zone:Edit** 权限)
  > 📌 获取路径: Cloudflare → Dashboard → My Profile → API Tokens → Create Token

### 2. 一键安装
```bash
# 下载安装脚本
wget https://raw.githubusercontent.com/0594/squid-proxy/main/proxy-installer.sh

# 赋予执行权限
chmod +x proxy-installer.sh

# 运行安装 (需要root权限)
sudo ./proxy-installer.sh

### 3.部署过程
```bash
=== 请按提示输入以下信息（所有输入将隐藏显示） ===
1. 域名 (e.g. proxy.example.com): proxy.yourdomain.com
2. Cloudflare API Token (需Zone:Edit权限): YOUR_CLOUDFLARE_TOKEN
3. 代理端口 (默认443): 443
4. Let's Encrypt邮箱: admin@yourdomain.com
5. 代理用户名 (默认proxy): proxy
6. 代理密码: your_strong_password

✅ 部署完成! 代理服务已启动
访问地址: https://proxy.yourdomain.com:443
用户名: proxy
密码: your_strong_password

使用命令 'proxy' 管理代理服务

