//! 加密工具模块
//! 
//! 使用 aes-gcm 和 hmac crate 提供真正的 AES-GCM 加密和 HMAC 功能。

use super::{error::{WalletError, Result}, memory::SecureBytes};
use sha2::{Sha256, Sha512, Digest};
use hmac::{Hmac, Mac};
use aes_gcm::{
    Aes256Gcm,
    aead::{Aead, KeyInit},
};

/// AES-GCM 加密器
pub struct AesGcmEncryptor;

impl AesGcmEncryptor {
    /// 使用 AES-256-GCM 加密数据
    /// 
    /// # 参数
    /// - `key`: 256 位密钥 (32 字节)
    /// - `nonce`: 96 位随机数 (12 字节)
    /// - `plaintext`: 明文数据
    /// - `aad`: 附加认证数据 (可选) — 当前使用简化接口，AAD 未集成
    /// 
    /// # 返回
    /// 密文 + 认证标签 (标签附在密文末尾, 16 字节)
    pub fn encrypt(
        key: &[u8; 32],
        nonce: &[u8; 12],
        plaintext: &[u8],
        _aad: Option<&[u8]>,
    ) -> Result<Vec<u8>> {
        if plaintext.is_empty() {
            return Ok(Vec::new());
        }
        
        let cipher = Aes256Gcm::new(key.into());
        let nonce = aes_gcm::Nonce::from_slice(nonce);
        
        cipher.encrypt(nonce, plaintext)
            .map_err(|e| WalletError::CryptoError(format!("AES-GCM 加密失败: {}", e)))
    }
    
    /// 使用 AES-256-GCM 解密数据
    /// 
    /// 自动验证认证标签，标签不匹配则返回错误
    pub fn decrypt(
        key: &[u8; 32],
        nonce: &[u8; 12],
        ciphertext: &[u8],
        _aad: Option<&[u8]>,
    ) -> Result<Vec<u8>> {
        if ciphertext.is_empty() {
            return Ok(Vec::new());
        }
        
        // AES-GCM 密文至少需要 16 字节的认证标签
        if ciphertext.len() < 16 {
            return Err(WalletError::CryptoError("密文太短，缺少认证标签".to_string()));
        }
        
        let cipher = Aes256Gcm::new(key.into());
        let nonce = aes_gcm::Nonce::from_slice(nonce);
        
        cipher.decrypt(nonce, ciphertext)
            .map_err(|e| WalletError::CryptoError(format!("AES-GCM 解密失败 (认证标签验证不通过): {}", e)))
    }
}

/// HMAC-SHA256
pub struct HmacSha256;

impl HmacSha256 {
    /// 计算 HMAC-SHA256
    pub fn mac(key: &[u8], message: &[u8]) -> [u8; 32] {
        let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(key)
            .expect("HMAC can take key of any size");
        mac.update(message);
        
        let mut result = [0u8; 32];
        result.copy_from_slice(&mac.finalize().into_bytes());
        result
    }
    
    /// 验证 HMAC (恒定时间比较)
    pub fn verify(key: &[u8], message: &[u8], expected: &[u8; 32]) -> bool {
        let computed = Self::mac(key, message);
        super::memory::secure_compare(&computed, expected)
    }
}

/// HMAC-SHA512
pub struct HmacSha512;

impl HmacSha512 {
    /// 计算 HMAC-SHA512
    pub fn mac(key: &[u8], message: &[u8]) -> [u8; 64] {
        let mut mac = <Hmac<Sha512> as Mac>::new_from_slice(key)
            .expect("HMAC can take key of any size");
        mac.update(message);
        
        let mut result = [0u8; 64];
        result.copy_from_slice(&mac.finalize().into_bytes());
        result
    }
}

/// 加密工具集合
pub struct CryptoUtils;

impl CryptoUtils {
    /// 生成随机字节
    pub fn random_bytes(len: usize) -> Result<SecureBytes> {
        SecureBytes::random(len)
    }
    
    /// SHA256 哈希
    pub fn sha256(data: &[u8]) -> [u8; 32] {
        let mut hasher = Sha256::new();
        hasher.update(data);
        let result = hasher.finalize();
        let mut hash = [0u8; 32];
        hash.copy_from_slice(&result);
        hash
    }
    
    /// SHA512 哈希
    pub fn sha512(data: &[u8]) -> [u8; 64] {
        let mut hasher = Sha512::new();
        hasher.update(data);
        let result = hasher.finalize();
        let mut hash = [0u8; 64];
        hash.copy_from_slice(&result);
        hash
    }
    
    /// 生成 HMAC-SHA256 签名
    pub fn hmac_sha256(key: &[u8], data: &[u8]) -> [u8; 32] {
        HmacSha256::mac(key, data)
    }
    
    /// 验证 HMAC-SHA256 签名 (恒定时间)
    pub fn verify_hmac(key: &[u8], data: &[u8], signature: &[u8; 32]) -> bool {
        HmacSha256::verify(key, data, signature)
    }
    
    /// AES-256-GCM 加密
    pub fn encrypt_aes_gcm(
        key: &[u8; 32],
        nonce: &[u8; 12],
        plaintext: &[u8],
    ) -> Result<Vec<u8>> {
        AesGcmEncryptor::encrypt(key, nonce, plaintext, None)
    }
    
    /// AES-256-GCM 解密 (自动验证认证标签)
    pub fn decrypt_aes_gcm(
        key: &[u8; 32],
        nonce: &[u8; 12],
        ciphertext: &[u8],
    ) -> Result<Vec<u8>> {
        AesGcmEncryptor::decrypt(key, nonce, ciphertext, None)
    }
    
    /// 生成 Nonce (12 字节安全随机数)
    pub fn generate_nonce() -> Result<[u8; 12]> {
        let bytes = SecureBytes::random(12)?;
        let mut nonce = [0u8; 12];
        nonce.copy_from_slice(&bytes.as_slice()[..12]);
        Ok(nonce)
    }
    
    /// 字节数组转十六进制
    pub fn to_hex(data: &[u8]) -> String {
        hex::encode(data)
    }
    
    /// 十六进制转字节数组
    pub fn from_hex(hex_str: &str) -> Result<Vec<u8>> {
        let hex_str = hex_str.trim_start_matches("0x");
        hex::decode(hex_str)
            .map_err(|e| WalletError::EncodingError(format!("无效的十六进制: {}", e)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_aes_gcm_encrypt_decrypt() {
        let key = [0x42u8; 32];
        let nonce = [0x01u8; 12];
        let plaintext = b"Hello, AES-GCM!";
        
        let ciphertext = AesGcmEncryptor::encrypt(&key, &nonce, plaintext, None).unwrap();
        assert_ne!(&ciphertext[..plaintext.len()], plaintext);
        
        let decrypted = AesGcmEncryptor::decrypt(&key, &nonce, &ciphertext, None).unwrap();
        assert_eq!(&decrypted, plaintext);
    }
    
    #[test]
    fn test_aes_gcm_tamper_detection() {
        let key = [0x42u8; 32];
        let nonce = [0x01u8; 12];
        let plaintext = b"Tamper detection test";
        
        let mut ciphertext = AesGcmEncryptor::encrypt(&key, &nonce, plaintext, None).unwrap();
        
        // 篡改密文
        if !ciphertext.is_empty() {
            ciphertext[0] ^= 0xFF;
        }
        
        // 解密应失败 (认证标签不匹配)
        let result = AesGcmEncryptor::decrypt(&key, &nonce, &ciphertext, None);
        assert!(result.is_err());
    }
    
    #[test]
    fn test_aes_gcm_wrong_key() {
        let key1 = [0x42u8; 32];
        let key2 = [0x43u8; 32];
        let nonce = [0x01u8; 12];
        let plaintext = b"Wrong key test";
        
        let ciphertext = AesGcmEncryptor::encrypt(&key1, &nonce, plaintext, None).unwrap();
        let result = AesGcmEncryptor::decrypt(&key2, &nonce, &ciphertext, None);
        assert!(result.is_err());
    }
    
    #[test]
    fn test_hmac_sha256() {
        let key = b"test_key";
        let message = b"test_message";
        
        let mac1 = HmacSha256::mac(key, message);
        let mac2 = HmacSha256::mac(key, message);
        
        assert_eq!(mac1, mac2);
        assert!(HmacSha256::verify(key, message, &mac1));
    }
    
    #[test]
    fn test_hmac_sha256_different_keys() {
        let key1 = b"key1";
        let key2 = b"key2";
        let message = b"same_message";
        
        let mac1 = HmacSha256::mac(key1, message);
        let mac2 = HmacSha256::mac(key2, message);
        
        assert_ne!(mac1, mac2);
        assert!(!HmacSha256::verify(key2, message, &mac1));
    }
    
    #[test]
    fn test_hex_roundtrip() {
        let data = vec![0xDE, 0xAD, 0xBE, 0xEF];
        let hex_str = CryptoUtils::to_hex(&data);
        assert_eq!(hex_str, "deadbeef");
        
        let decoded = CryptoUtils::from_hex(&hex_str).unwrap();
        assert_eq!(decoded, data);
    }
    
    #[test]
    fn test_hex_with_0x_prefix() {
        let decoded = CryptoUtils::from_hex("0xdeadbeef").unwrap();
        assert_eq!(decoded, vec![0xDE, 0xAD, 0xBE, 0xEF]);
    }
}
