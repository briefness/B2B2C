//! 错误类型定义

use thiserror::Error;

/// 钱包核心错误类型
#[derive(Error, Debug)]
pub enum WalletError {
    #[error("助记词无效: {0}")]
    InvalidMnemonic(String),
    
    #[error("种子派生失败: {0}")]
    KeyDerivationFailed(String),
    
    #[error("签名失败: {0}")]
    SigningFailed(String),
    
    #[error("加密/解密失败: {0}")]
    CryptoError(String),
    
    #[error("内存操作失败: {0}")]
    MemoryError(String),
    
    #[error("无效参数: {0}")]
    InvalidArgument(String),
    
    #[error("随机数生成失败")]
    RandomGenerationFailed,
    
    #[error("编码错误: {0}")]
    EncodingError(String),
}

/// 结果类型别名
pub type Result<T> = std::result::Result<T, WalletError>;

impl From<WalletError> for String {
    fn from(err: WalletError) -> String {
        err.to_string()
    }
}
