//! B2B2C 虚拟币钱包核心加密库
//! 
//! 本模块提供安全的加密功能，包括：
//! - BIP39 助记词生成
//! - BIP44 HD 钱包派生
//! - Secp256k1 椭圆曲线签名
//! - AES-256-GCM 加密
//! - 内存安全 (Zeroize 自动擦除)

pub mod error;
pub mod mnemonic;
pub mod key_derivation;
pub mod signing;
pub mod crypto_utils;
pub mod memory;

pub use error::{WalletError, Result};
pub use mnemonic::{MnemonicManager, Strength};
pub use key_derivation::{KeyDeriver, Bip44Path, ExtendedKey};
pub use signing::{TransactionSigner, Signature};
pub use crypto_utils::CryptoUtils;
pub use memory::SecureBytes;

// 导出 C-ABI 接口
pub mod ffi;
