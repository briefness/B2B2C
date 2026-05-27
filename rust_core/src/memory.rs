//! 内存安全模块
//! 
//! 提供安全的内存管理，确保敏感数据（如私钥）在使用完毕后被物理擦除。

use zeroize::Zeroize;
use rand::{rngs::OsRng, RngCore};

/// 安全的字节数组容器
/// 使用 Zeroize 宏在 drop 时自动清零内存
#[derive(Zeroize)]
#[zeroize(drop)]
pub struct SecureBytes {
    data: Vec<u8>,
}

impl SecureBytes {
    /// 从普通字节创建安全容器
    pub fn new(data: Vec<u8>) -> Self {
        Self { data }
    }

    /// 创建指定长度的安全随机字节
    pub fn random(len: usize) -> Result<Self, crate::error::WalletError> {
        let mut data = vec![0u8; len];
        OsRng.fill_bytes(&mut data);
        Ok(Self { data })
    }

    /// 获取不可变的字节引用
    pub fn as_slice(&self) -> &[u8] {
        &self.data
    }

    /// 获取可变字节引用
    pub fn as_mut_slice(&mut self) -> &mut [u8] {
        &mut self.data
    }

    /// 获取长度
    pub fn len(&self) -> usize {
        self.data.len()
    }

    /// 检查是否为空
    pub fn is_empty(&self) -> bool {
        self.data.is_empty()
    }

    /// 转换为十六进制字符串
    pub fn to_hex(&self) -> String {
        hex::encode(&self.data)
    }
}

impl From<Vec<u8>> for SecureBytes {
    fn from(data: Vec<u8>) -> Self {
        Self::new(data)
    }
}

impl AsRef<[u8]> for SecureBytes {
    fn as_ref(&self) -> &[u8] {
        &self.data
    }
}

/// 内存比较函数 (恒定时间)
/// 用于防止时序攻击
pub fn secure_compare(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    
    let mut result = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        result |= x ^ y;
    }
    
    result == 0
}

/// 安全的内存清零
/// 使用 zeroize 确保不被编译器优化掉
pub fn secure_zero(dest: &mut [u8]) {
    dest.zeroize();
}
