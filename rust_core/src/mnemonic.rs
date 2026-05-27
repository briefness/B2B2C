//! 助记词管理模块
//! 
//! 使用 bip39 crate 实现标准 BIP39 助记词生成、验证和种子派生。

use bip39::{Mnemonic, Language};
use super::{error::{WalletError, Result}, memory::SecureBytes};

/// BIP39 助记词管理器
pub struct MnemonicManager;

/// 助记词强度枚举
#[derive(Debug, Clone, Copy)]
pub enum Strength {
    Bits128 = 128,  // 12 词
    Bits192 = 192,  // 18 词
    Bits256 = 256,  // 24 词
}

impl MnemonicManager {
    /// 生成随机助记词
    pub fn generate(strength: Strength) -> Result<Vec<String>> {
        let entropy_bytes = (strength as usize) / 8;
        let mut entropy = vec![0u8; entropy_bytes];
        
        // 使用 OsRng 生成安全随机熵
        use rand::{rngs::OsRng, RngCore};
        OsRng.fill_bytes(&mut entropy);
        
        let mnemonic = Mnemonic::from_entropy_in(Language::English, &entropy)
            .map_err(|e| WalletError::InvalidMnemonic(format!("助记词生成失败: {}", e)))?;
        
        let words: Vec<String> = mnemonic.words()
            .map(String::from)
            .collect();
        
        // 清零熵
        use zeroize::Zeroize;
        entropy.zeroize();
        
        Ok(words)
    }
    
    /// 从助记词导出种子 (BIP39 标准: PBKDF2-HMAC-SHA512, 2048 次迭代)
    pub fn to_seed(mnemonic: &[String], passphrase: &str) -> Result<SecureBytes> {
        Self::validate(mnemonic)?;
        
        let phrase = mnemonic.iter()
            .map(|w| w.trim().to_lowercase())
            .collect::<Vec<_>>()
            .join(" ");
        
        let mnemonic = Mnemonic::parse_in_normalized(Language::English, &phrase)
            .map_err(|e| WalletError::InvalidMnemonic(format!("助记词解析失败: {}", e)))?;
        
        // bip39 crate 内部使用标准 PBKDF2-HMAC-SHA512 (2048 次迭代)
        let seed = mnemonic.to_seed(passphrase);
        
        Ok(SecureBytes::new(seed.to_vec()))
    }
    
    /// 验证助记词有效性
    pub fn validate(mnemonic: &[String]) -> Result<()> {
        if mnemonic.is_empty() {
            return Err(WalletError::InvalidMnemonic("助记词不能为空".to_string()));
        }
        
        let word_count = mnemonic.len();
        if word_count != 12 && word_count != 18 && word_count != 24 {
            return Err(WalletError::InvalidMnemonic(
                format!("无效的助记词数量: {}. 应为 12、18 或 24", word_count)
            ));
        }
        
        let phrase = mnemonic.iter()
            .map(|w| w.trim().to_lowercase())
            .collect::<Vec<_>>()
            .join(" ");
        
        // bip39 crate 验证校验和 + 词表
        Mnemonic::parse_in_normalized(Language::English, &phrase)
            .map_err(|e| WalletError::InvalidMnemonic(format!("助记词无效: {}", e)))?;
        
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_generate_mnemonic_12() {
        let mnemonic = MnemonicManager::generate(Strength::Bits128).unwrap();
        assert_eq!(mnemonic.len(), 12);
        assert!(MnemonicManager::validate(&mnemonic).is_ok());
    }
    
    #[test]
    fn test_generate_mnemonic_24() {
        let mnemonic = MnemonicManager::generate(Strength::Bits256).unwrap();
        assert_eq!(mnemonic.len(), 24);
        assert!(MnemonicManager::validate(&mnemonic).is_ok());
    }
    
    #[test]
    fn test_validate_mnemonic() {
        // 使用 BIP39 标准测试向量 (校验和有效)
        let valid: Vec<String> = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split_whitespace().map(String::from).collect();
        assert!(MnemonicManager::validate(&valid).is_ok());
    }
    
    #[test]
    fn test_validate_invalid_mnemonic() {
        let invalid = vec!["invalidword".to_string(); 12];
        assert!(MnemonicManager::validate(&invalid).is_err());
    }
    
    #[test]
    fn test_to_seed_deterministic() {
        let mnemonic: Vec<String> = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split_whitespace().map(String::from).collect();
        
        let seed1 = MnemonicManager::to_seed(&mnemonic, "").unwrap();
        let seed2 = MnemonicManager::to_seed(&mnemonic, "").unwrap();
        
        assert_eq!(seed1.as_slice(), seed2.as_slice());
        assert_eq!(seed1.len(), 64); // 512-bit seed
    }
    
    #[test]
    fn test_to_seed_with_passphrase() {
        let mnemonic: Vec<String> = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split_whitespace().map(String::from).collect();
        
        let seed_no_pass = MnemonicManager::to_seed(&mnemonic, "").unwrap();
        let seed_with_pass = MnemonicManager::to_seed(&mnemonic, "my_password").unwrap();
        
        assert_ne!(seed_no_pass.as_slice(), seed_with_pass.as_slice());
    }
}
