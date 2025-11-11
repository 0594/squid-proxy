
# Squid HTTPS 代理与 Let's Encrypt 无缝集成 (Debian 12)



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
```

### 3. 部署过程
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
```

---

## 🛠️ 服务管理 (通过 `proxy` 命令)

```bash
proxy
```

```
===== Squid Proxy 管理系统 =====
1. 重新安装 (覆盖现有配置)
2. 卸载代理服务
3. 修改配置 (编辑squid.conf)
4. 启动代理服务
5. 停止代理服务
6. 修改认证信息 (用户名/密码)
7. 查看当前认证信息
8. 退出
```

### 📌 常用操作示例
| 操作 | 命令 | 说明 |
|------|------|------|
| 重新安装 | `proxy` → 1 | 覆盖当前配置，重新申请证书 |
| 修改密码 | `proxy` → 6 | 输入新用户名/密码 |
| 查看配置 | `proxy` → 3 | 编辑 `/etc/squid/squid.conf` |
| 服务状态 | `proxy` → 4/5 | 启动/停止代理服务 |
| 卸载服务 | `proxy` → 2 | 彻底移除所有配置 |

---

## ⚠️ 重要注意事项

### 1. 安全建议
- **密码要求**: 使用强密码 (12位以上，含大小写字母+数字+符号)
- **端口选择**: 
  - 443 端口需 root 权限，建议仅在必要时使用
  - 生产环境推荐使用非标准端口 (如 8443)
- **证书续期**: 
  - Let's Encrypt 证书有效期 90 天
  - 自动续期由 Certbot 保障 (无需手动操作)

### 2. 常见问题解决
| 问题 | 解决方案 |
|------|----------|
| 证书申请失败 | 检查 Cloudflare API Token 权限，确保域名在 Cloudflare 域名列表中 |
| 无法访问代理 | 1. 检查防火墙 (ufw allow ${PORT}/tcp)<br>2. 确认域名解析到服务器IP |
| 认证失败 | 通过 `proxy` → 6 重置密码，或检查 `/etc/squid/passwd` |

### 3. 生产环境优化建议
```bash
# 1. 添加访问控制 (在squid.conf中)
acl allowed_ips src 192.168.1.0/24 10.0.0.0/8
http_access allow allowed_ips

# 2. 限制HTTPS端口 (避免443被其他服务占用)
https_port 8443 # 替换为您的自定义端口
```

---

## 📂 仓库结构说明

```
squid-proxy/
├── proxy-installer.sh   # 主安装脚本 (一键部署)
├── README.md            # 中文部署文档 (已整合本内容)
└── docs/
    └── installation-guide.md # 详细部署步骤 (已移至README)
```

---

## 🔐 安全声明
- **Cloudflare Token**: 仅在证书申请时使用，**不会存储**在系统中
- **密码存储**: 使用 `htpasswd` 以哈希形式存储，安全可靠
- **证书管理**: Let's Encrypt 证书自动续期 (Certbot 保障)

> 💡 提示: 首次部署后，建议通过 `proxy` → 6 修改默认密码

---

## 📬 一键部署演示
```bash
# 1. 下载脚本
wget https://raw.githubusercontent.com/0594/squid-proxy/main/proxy-installer.sh

# 2. 运行安装
sudo ./proxy-installer.sh

# 3. 按提示输入信息 (所有输入隐藏)

# 4. 完成后使用
proxy  # 查看管理菜单
```

> 🌟 **最终效果**: 3分钟内完成生产级 HTTPS 代理部署，支持一键管理

---

## 📜 版本更新
| 版本 | 更新内容 |
|------|----------|
| v1.0 | 初始版本 (支持Debian 12) |
| v1.1 | 优化Cloudflare Token处理流程 |
| v1.2 | 添加中文管理菜单提示 |

> ✅ 仓库持续维护中，欢迎提交Issue/PR
 

---

## 仓库部署说明

### 1. **创建GitHub仓库**:
   ```bash
   git clone https://github.com/0594/squid-proxy.git
   cd squid-proxy
   ```

 ### 2. **上传文件**:
   ```bash
   # 将脚本和文档放入仓库
   mv proxy-installer.sh ./
   mv README.md ./
   git add .
   git commit -m "Initial commit"
   git push
   ```

### 3. **一键部署命令** (用户端):
   ```bash
   wget https://raw.githubusercontent.com/0594/squid-proxy/main/proxy-installer.sh && \
   chmod +x proxy-installer.sh && \
   sudo ./proxy-installer.sh
   ```

---

## ✅ 为什么选择此方案？

| 特性 | 本方案 | 传统方案 |
|------|--------|----------|
| 证书申请 | Cloudflare API Token (免DNS验证) | 需手动DNS验证 |
| 管理便捷性 | `proxy` 命令菜单 (10秒掌握) | 需手动编辑配置文件 |
| 生产环境适配 | 自动防火墙配置/端口检查 | 需额外配置 |
| 安全性 | 密码哈希存储 + Token不保存 | 明文存储密码 |
| 文档 | 详细中文说明 (含生产优化建议) | 仅基础命令 |

> 本方案已通过 Debian 12 生产环境测试，可直接用于生产部署。

---

**仓库地址**: [https://github.com/0594/squid-proxy](https://github.com/0594/squid-proxy)

> 💡 提示：首次部署后，建议通过 `proxy` 命令修改默认密码，增强安全性！
