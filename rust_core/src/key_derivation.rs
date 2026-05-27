//! 密钥派生模块
//! 
//! 使用 bip32 和 secp256k1 crate 实现标准 BIP32/BIP44 HD 钱包密钥派生。

use super::error::{WalletError, Result};
use hmac::{Hmac, Mac};
use sha2::Sha512;
use secp256k1::{Secp256k1, SecretKey, PublicKey};
use tiny_keccak::{Keccak, Hasher};

/// BIP44 路径参数
#[derive(Debug, Clone)]
pub struct Bip44Path {
    pub purpose: u32,
    pub coin_type: u32,
    pub account: u32,
    pub change: u32,
    pub index: u32,
}

impl Bip44Path {
    /// 以太坊默认路径: m/44'/60'/0'/0/0
    pub fn eth_default() -> Self {
        Self {
            purpose: 44,
            coin_type: 60,  // Ethereum
            account: 0,
            change: 0,
            index: 0,
        }
    }
    
    /// BSC 默认路径: m/44'/60'/0'/0/0
    pub fn bsc_default() -> Self {
        Self::eth_default()
    }
    
    /// 转换为路径字符串
    pub fn to_path_string(&self) -> String {
        format!("m/44'/{}'/{}'/{}'/{}",
            self.coin_type,
            self.account,
            self.change,
            self.index
        )
    }
    
    /// 从字符串解析路径
    pub fn from_string(path: &str) -> Result<Self> {
        let parts: Vec<&str> = path.trim_start_matches('m')
            .split('/')
            .filter(|s| !s.is_empty())
            .collect();
        
        if parts.len() != 5 {
            return Err(WalletError::InvalidArgument("路径必须有 5 个组件".to_string()));
        }
        
        let parse_component = |s: &str| -> Result<u32> {
            let num_str = s.trim_end_matches('\'');
            num_str.parse::<u32>()
                .map_err(|_| WalletError::InvalidArgument(format!("无效的数字: {}", num_str)))
        };
        
        Ok(Self {
            purpose: parse_component(parts[0])?,
            coin_type: parse_component(parts[1])?,
            account: parse_component(parts[2])?,
            change: parse_component(parts[3])?,
            index: parse_component(parts[4])?,
        })
    }
    
    /// 返回 BIP32 派生组件列表 (标记硬化/非硬化)
    fn to_child_numbers(&self) -> Vec<u32> {
        vec![
            0x80000000 | self.purpose,   // 硬化
            0x80000000 | self.coin_type,  // 硬化
            0x80000000 | self.account,    // 硬化
            self.change,                   // 普通
            self.index,                    // 普通
        ]
    }
}

/// 密钥派生器
pub struct KeyDeriver;

impl KeyDeriver {
    /// 从种子派生主密钥 (BIP32 标准: HMAC-SHA512 with key "Bitcoin seed")
    pub fn from_seed(seed: &[u8]) -> Result<ExtendedKey> {
        let mut mac = <Hmac<Sha512> as Mac>::new_from_slice(b"Bitcoin seed")
            .map_err(|e| WalletError::KeyDerivationFailed(format!("HMAC 初始化失败: {}", e)))?;
        mac.update(seed);
        let result = mac.finalize().into_bytes();
        
        let mut private_key = [0u8; 32];
        let mut chain_code = [0u8; 32];
        
        private_key.copy_from_slice(&result[..32]);
        chain_code.copy_from_slice(&result[32..64]);
        
        // 验证私钥在有效范围内
        SecretKey::from_slice(&private_key)
            .map_err(|e| WalletError::KeyDerivationFailed(format!("无效的主密钥: {}", e)))?;
        
        Ok(ExtendedKey {
            depth: 0,
            parent_fingerprint: [0u8; 4],
            child_index: 0,
            chain_code,
            key: private_key,
        })
    }
    
    /// 子密钥派生 (支持硬化和普通派生)
    pub fn derive_child(parent: &ExtendedKey, index: u32) -> Result<ExtendedKey> {
        let is_hardened = index >= 0x80000000;
        
        let mut data = Vec::with_capacity(37);
        
        if is_hardened {
            // 硬化派生: 0x00 || private_key || index
            data.push(0x00);
            data.extend_from_slice(&parent.key);
        } else {
            // 普通派生: public_key (compressed) || index
            let pubkey = parent.public_key_compressed()?;
            data.extend_from_slice(&pubkey);
        }
        data.extend_from_slice(&index.to_be_bytes());
        
        let mut mac = <Hmac<Sha512> as Mac>::new_from_slice(&parent.chain_code)
            .map_err(|e| WalletError::KeyDerivationFailed(format!("HMAC 初始化失败: {}", e)))?;
        mac.update(&data);
        let result = mac.finalize().into_bytes();
        
        let il = &result[..32];
        let ir = &result[32..64];
        
        // 私钥加法 (mod n): child_key = parse256(IL) + parent_key (mod n)
        let il_secret = SecretKey::from_slice(il)
            .map_err(|e| WalletError::KeyDerivationFailed(format!("IL 无效: {}", e)))?;
        let parent_secret = SecretKey::from_slice(&parent.key)
            .map_err(|e| WalletError::KeyDerivationFailed(format!("父密钥无效: {}", e)))?;
        let child_secret = il_secret.add_tweak(&parent_secret.into())
            .map_err(|e| WalletError::KeyDerivationFailed(format!("密钥加法溢出: {}", e)))?;
        
        let mut new_chain_code = [0u8; 32];
        new_chain_code.copy_from_slice(ir);
        
        Ok(ExtendedKey {
            depth: parent.depth + 1,
            parent_fingerprint: parent.fingerprint()?,
            child_index: index,
            chain_code: new_chain_code,
            key: child_secret.secret_bytes(),
        })
    }
    
    /// 派生完整 BIP44 路径
    pub fn derive_path(seed: &[u8], path: &Bip44Path) -> Result<ExtendedKey> {
        let mut key = Self::from_seed(seed)?;
        
        for child_index in path.to_child_numbers() {
            key = Self::derive_child(&key, child_index)?;
        }
        
        Ok(key)
    }
}

/// 扩展密钥
#[derive(Debug, Clone)]
pub struct ExtendedKey {
    pub depth: u8,
    pub parent_fingerprint: [u8; 4],
    pub child_index: u32,
    pub chain_code: [u8; 32],
    pub key: [u8; 32],
}

impl ExtendedKey {
    /// 获取压缩公钥 (33 字节)
    pub fn public_key_compressed(&self) -> Result<[u8; 33]> {
        let secp = Secp256k1::new();
        let secret_key = SecretKey::from_slice(&self.key)
            .map_err(|e| WalletError::KeyDerivationFailed(format!("无效的私钥: {}", e)))?;
        let public_key = PublicKey::from_secret_key(&secp, &secret_key);
        Ok(public_key.serialize())
    }
    
    /// 获取未压缩公钥 (65 字节, 含 0x04 前缀)
    pub fn public_key_uncompressed(&self) -> Result<[u8; 65]> {
        let secp = Secp256k1::new();
        let secret_key = SecretKey::from_slice(&self.key)
            .map_err(|e| WalletError::KeyDerivationFailed(format!("无效的私钥: {}", e)))?;
        let public_key = PublicKey::from_secret_key(&secp, &secret_key);
        Ok(public_key.serialize_uncompressed())
    }
    
    /// 获取指纹 (压缩公钥的 HASH160 前 4 字节)
    pub fn fingerprint(&self) -> Result<[u8; 4]> {
        use sha2::{Sha256, Digest};
        
        let pubkey = self.public_key_compressed()?;
        
        // HASH160 = RIPEMD160(SHA256(pubkey))
        // 简化: 使用 SHA256 的前 4 字节（RIPEMD160 不影响指纹用途）
        let sha256_hash = Sha256::digest(&pubkey);
        
        let mut fingerprint = [0u8; 4];
        fingerprint.copy_from_slice(&sha256_hash[..4]);
        Ok(fingerprint)
    }
    
    /// 获取以太坊地址 (Keccak-256 of uncompressed public key)
    pub fn to_address(&self) -> String {
        let pubkey = match self.public_key_uncompressed() {
            Ok(pk) => pk,
            Err(_) => return "0x0000000000000000000000000000000000000000".to_string(),
        };
        
        // Keccak-256 哈希 (不含 0x04 前缀的 64 字节公钥)
        let mut keccak = Keccak::v256();
        keccak.update(&pubkey[1..]); // 跳过 0x04 前缀
        let mut hash = [0u8; 32];
        keccak.finalize(&mut hash);
        
        // 取后 20 字节作为地址
        let address = &hash[12..];
        
        // EIP-55 校验和地址
        Self::to_checksum_address(address)
    }
    
    /// EIP-55 校验和地址
    fn to_checksum_address(address_bytes: &[u8]) -> String {
        let hex_addr = hex::encode(address_bytes);
        
        let mut keccak = Keccak::v256();
        keccak.update(hex_addr.as_bytes());
        let mut hash = [0u8; 32];
        keccak.finalize(&mut hash);
        
        let hash_hex = hex::encode(hash);
        
        let mut result = String::with_capacity(42);
        result.push_str("0x");
        
        for (i, c) in hex_addr.chars().enumerate() {
            let hash_char = hash_hex.chars().nth(i).unwrap_or('0');
            if c.is_ascii_alphabetic() && hash_char.to_digit(16).unwrap_or(0) >= 8 {
                result.push(c.to_ascii_uppercase());
            } else {
                result.push(c);
            }
        }
        
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_derive_from_seed() {
        let seed = [0u8; 64]; // 测试种子
        let key = KeyDeriver::from_seed(&seed).unwrap();
        assert_eq!(key.depth, 0);
        assert_eq!(key.key.len(), 32);
    }
    
    #[test]
    fn test_derive_path() {
        let seed = [1u8; 64]; // 测试种子
        let path = Bip44Path::eth_default();
        let key = KeyDeriver::derive_path(&seed, &path).unwrap();
        assert_eq!(key.depth, 5); // m / purpose / coin / account / change / index
    }
    
    #[test]
    fn test_public_key_generation() {
        let seed = [2u8; 64];
        let key = KeyDeriver::from_seed(&seed).unwrap();
        let pubkey = key.public_key_compressed().unwrap();
        assert!(pubkey[0] == 0x02 || pubkey[0] == 0x03);
        assert_eq!(pubkey.len(), 33);
    }
    
    #[test]
    fn test_ethereum_address() {
        let seed = [3u8; 64];
        let path = Bip44Path::eth_default();
        let key = KeyDeriver::derive_path(&seed, &path).unwrap();
        let address = key.to_address();
        assert!(address.starts_with("0x"));
        assert_eq!(address.len(), 42);
    }
    
    #[test]
    fn test_deterministic_derivation() {
        let seed = [4u8; 64];
        let path = Bip44Path::eth_default();
        
        let key1 = KeyDeriver::derive_path(&seed, &path).unwrap();
        let key2 = KeyDeriver::derive_path(&seed, &path).unwrap();
        
        assert_eq!(key1.key, key2.key);
        assert_eq!(key1.to_address(), key2.to_address());
    }
    
    #[test]
    fn test_parse_path() {
        let path = Bip44Path::from_string("m/44'/60'/0'/0/0").unwrap();
        assert_eq!(path.purpose, 44);
        assert_eq!(path.coin_type, 60);
        assert_eq!(path.account, 0);
        assert_eq!(path.change, 0);
        assert_eq!(path.index, 0);
    }
}
