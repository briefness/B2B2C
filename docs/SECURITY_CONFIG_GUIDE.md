# 安全配置指南

## 1. SSL Pinning 证书配置

### 获取服务器证书哈希

```bash
# 安装证书 (如果需要)
brew install openssl

# 获取 API 服务器证书哈希
echo | openssl s_client -servername api.b2b2c-wallet.com -connect api.b2b2c-wallet.com:443 2>/dev/null | openssl x509 -fingerprint -sha256 -noout

# 获取 WebSocket 服务器证书哈希
echo | openssl s_client -servername ws.b2b2c-wallet.com -connect ws.b2b2c-wallet.com:443 2>/dev/null | openssl x509 -fingerprint -sha256 -noout
```

### 示例输出

```
sha256//xYzABC123...
```

**注意**：去掉冒号，只保留哈希值，添加 `sha256/` 前缀。

### 配置环境变量

```bash
# 在 CI/CD 或部署环境中设置
export API_CERT_HASH="sha256/你的API证书哈希"
export WS_CERT_HASH="sha256/你的WS证书哈希"
export API_CERT_HASH_BACKUP="sha256/备用API证书哈希"
export WS_CERT_HASH_BACKUP="sha256/备用WS证书哈希"
```

---

## 2. HMAC 密钥配置

### 生成 HMAC 密钥

```bash
# 生成 64 字符的随机密钥 (hex 编码)
openssl rand -hex 32

# 示例输出
# 8f4e9b2c3a1d5e7f8c2b4a9d6e1f3c5b7a8d4e2f6c8b1a4d7e3f9c2b5a8d1e3
```

### 配置环境变量

```bash
export HMAC_KEY="8f4e9b2c3a1d5e7f8c2b4a9d6e1f3c5b7a8d4e2f6c8b1a4d7e3f9c2b5a8d1e3"
```

---

## 3. B2B 配置签名公钥

### B2B 后台配置

1. 登录 B 端管理后台
2. 进入「安全设置」→「配置签名」
3. 生成或导入 secp256k1 密钥对
4. 导出公钥

### 公钥格式

公钥应为 65 字节的十六进制字符串 (压缩格式为 33 字节):

```
04 + 64字节公钥X坐标
```

或压缩格式:

```
02/03 + 32字节公钥X坐标
```

### 配置环境变量

```bash
export B2B_CONFIG_PUBLIC_KEY="04你的64字节公钥..."
```

---

## 4. 生产环境部署示例

### Dockerfile 或 CI/CD 配置

```yaml
# docker-compose.prod.yml
environment:
  - API_CERT_HASH=sha256/你的API证书哈希
  - WS_CERT_HASH=sha256/你的WS证书哈希
  - API_CERT_HASH_BACKUP=sha256/备用API证书哈希
  - WS_CERT_HASH_BACKUP=sha256/备用WS证书哈希
  - HMAC_KEY=你的HMAC密钥
  - B2B_CONFIG_PUBLIC_KEY=你的B2B公钥
```

### GitHub Secrets 配置

```
API_CERT_HASH: sha256/你的API证书哈希
WS_CERT_HASH: sha256/你的WS证书哈希
HMAC_KEY: 你的HMAC密钥
B2B_CONFIG_PUBLIC_KEY: 你的B2B公钥
```

---

## 5. 配置验证

### 本地测试

```bash
# 启动应用后检查日志
flutter run -d <device>

# 检查日志输出
# [SSL Pinning] Certificate validation: passed
# [Security] Config signature verified
```

### 生产环境验证

1. **SSL Pinning**：使用 Charles/Fiddler 尝试抓包，应失败
2. **HMAC**：修改请求参数，应被服务端拒绝
3. **配置签名**：修改配置文件，应被客户端拒绝

---

## 6. 证书轮换流程

当证书即将过期时:

1. 在服务器部署新证书
2. 将新证书哈希添加到 `backup_certificates`
3. 部署应用更新
4. 确认新证书正常工作
5. 移除旧证书哈希
6. 可选：添加新备用证书

---

## 7. 紧急情况处理

### 证书哈希错误导致无法连接

如果生产环境出现 SSL 验证失败:

1. 临时设置 `allow_self_signed: true` (仅开发环境)
2. 检查证书哈希配置
3. 确认 DNS 解析正确
4. 确认证书未过期

### 泄露应对

如果 HMAC 密钥泄露:

1. 立即在服务器端禁用该密钥
2. 生成新密钥
3. 更新所有客户端配置
4. 考虑紧急版本发布
