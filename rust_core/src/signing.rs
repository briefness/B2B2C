//! 交易签名模块
//! 
//! 使用 secp256k1 crate 实现真实的 ECDSA 椭圆曲线签名。

use super::error::{WalletError, Result};
use secp256k1::{Secp256k1, SecretKey, PublicKey, Message};
use secp256k1::ecdsa::{RecoverableSignature, RecoveryId};

/// 交易签名器
pub struct TransactionSigner;

impl TransactionSigner {
    /// 对交易数据进行 ECDSA 签名
    /// 
    /// # 参数
    /// - `private_key`: 私钥 (32 字节)
    /// - `message_hash`: 交易消息的哈希 (32 字节)
    /// - `chain_id`: 链 ID (用于 EIP-155 重放保护)
    /// 
    /// # 返回
    /// 签名的 R, S, V 值
    pub fn sign(
        private_key: &[u8; 32],
        message_hash: &[u8; 32],
        chain_id: Option<u64>,
    ) -> Result<Signature> {
        let secp = Secp256k1::new();
        
        let secret_key = SecretKey::from_slice(private_key)
            .map_err(|e| WalletError::SigningFailed(format!("无效的私钥: {}", e)))?;
        
        let message = Message::from_digest_slice(message_hash)
            .map_err(|e| WalletError::SigningFailed(format!("无效的消息哈希: {}", e)))?;
        
        // secp256k1 crate 内部使用 RFC 6979 确定性 K 值
        let recoverable_sig = secp.sign_ecdsa_recoverable(&message, &secret_key);
        let (recovery_id, sig_data) = recoverable_sig.serialize_compact();
        
        let mut r = [0u8; 32];
        let mut s = [0u8; 32];
        r.copy_from_slice(&sig_data[..32]);
        s.copy_from_slice(&sig_data[32..64]);
        
        // 计算 V 值
        let rec_id = recovery_id.to_i32() as u8;
        let v = if let Some(cid) = chain_id {
            // EIP-155: v = recovery_id + chain_id * 2 + 35
            (rec_id as u64 + cid * 2 + 35) as u8
        } else {
            // Legacy: v = recovery_id + 27
            rec_id + 27
        };
        
        Ok(Signature { r, s, v })
    }
    
    /// 验证 ECDSA 签名
    pub fn verify(
        public_key: &[u8; 64],
        message_hash: &[u8; 32],
        signature: &Signature,
    ) -> Result<bool> {
        let secp = Secp256k1::new();
        
        // 构造未压缩公钥 (0x04 || X || Y)
        let mut uncompressed = [0u8; 65];
        uncompressed[0] = 0x04;
        uncompressed[1..].copy_from_slice(public_key);
        
        let pubkey = PublicKey::from_slice(&uncompressed)
            .map_err(|e| WalletError::SigningFailed(format!("无效的公钥: {}", e)))?;
        
        let message = Message::from_digest_slice(message_hash)
            .map_err(|e| WalletError::SigningFailed(format!("无效的消息哈希: {}", e)))?;
        
        // 构造 DER 格式签名
        let mut sig_bytes = [0u8; 64];
        sig_bytes[..32].copy_from_slice(&signature.r);
        sig_bytes[32..].copy_from_slice(&signature.s);
        
        let ecdsa_sig = secp256k1::ecdsa::Signature::from_compact(&sig_bytes)
            .map_err(|e| WalletError::SigningFailed(format!("无效的签名格式: {}", e)))?;
        
        match secp.verify_ecdsa(&message, &ecdsa_sig, &pubkey) {
            Ok(()) => Ok(true),
            Err(_) => Ok(false),
        }
    }
    
    /// ECDSA 恢复公钥
    pub fn recover_public_key(
        message_hash: &[u8; 32],
        signature: &Signature,
        recovery_id: u8,
    ) -> Result<[u8; 64]> {
        let secp = Secp256k1::new();
        
        let message = Message::from_digest_slice(message_hash)
            .map_err(|e| WalletError::SigningFailed(format!("无效的消息哈希: {}", e)))?;
        
        let rec_id = RecoveryId::from_i32(recovery_id as i32)
            .map_err(|e| WalletError::SigningFailed(format!("无效的恢复 ID: {}", e)))?;
        
        let mut sig_bytes = [0u8; 64];
        sig_bytes[..32].copy_from_slice(&signature.r);
        sig_bytes[32..].copy_from_slice(&signature.s);
        
        let recoverable_sig = RecoverableSignature::from_compact(&sig_bytes, rec_id)
            .map_err(|e| WalletError::SigningFailed(format!("无效的可恢复签名: {}", e)))?;
        
        let recovered_key = secp.recover_ecdsa(&message, &recoverable_sig)
            .map_err(|e| WalletError::SigningFailed(format!("公钥恢复失败: {}", e)))?;
        
        let uncompressed = recovered_key.serialize_uncompressed();
        let mut public_key = [0u8; 64];
        public_key.copy_from_slice(&uncompressed[1..]); // 去掉 0x04 前缀
        
        Ok(public_key)
    }
}

/// 签名结构
#[derive(Debug, Clone)]
pub struct Signature {
    pub r: [u8; 32],
    pub s: [u8; 32],
    pub v: u8,
}

impl Signature {
    /// 编码为字节
    pub fn to_bytes(&self) -> [u8; 65] {
        let mut bytes = [0u8; 65];
        bytes[0..32].copy_from_slice(&self.r);
        bytes[32..64].copy_from_slice(&self.s);
        bytes[64] = self.v;
        bytes
    }
    
    /// 编码为十六进制字符串
    pub fn to_hex(&self) -> String {
        hex::encode(self.to_bytes())
    }
    
    /// 从十六进制解码
    pub fn from_hex(hex_str: &str) -> Result<Self> {
        let bytes = hex::decode(hex_str)
            .map_err(|_| WalletError::EncodingError("无效的十六进制编码".to_string()))?;
        
        if bytes.len() != 65 {
            return Err(WalletError::EncodingError(
                format!("签名长度应为 65 字节, 实际为 {} 字节", bytes.len())
            ));
        }
        
        let mut r = [0u8; 32];
        let mut s = [0u8; 32];
        r.copy_from_slice(&bytes[0..32]);
        s.copy_from_slice(&bytes[32..64]);
        
        Ok(Self {
            r,
            s,
            v: bytes[64],
        })
    }
    
    /// 获取恢复 ID (从 V 值提取)
    pub fn recovery_id(&self, chain_id: Option<u64>) -> u8 {
        if let Some(cid) = chain_id {
            // EIP-155: recovery_id = v - chain_id * 2 - 35
            ((self.v as u64).saturating_sub(cid * 2 + 35)) as u8
        } else {
            // Legacy: recovery_id = v - 27
            self.v.saturating_sub(27)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Sha256, Digest};
    
    fn test_keypair() -> ([u8; 32], [u8; 64]) {
        let secp = Secp256k1::new();
        let private_key: [u8; 32] = [
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
            0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
            0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20,
        ];
        let secret = SecretKey::from_slice(&private_key).unwrap();
        let public = PublicKey::from_secret_key(&secp, &secret);
        let uncompressed = public.serialize_uncompressed();
        let mut pubkey = [0u8; 64];
        pubkey.copy_from_slice(&uncompressed[1..]);
        (private_key, pubkey)
    }
    
    #[test]
    fn test_sign_and_verify() {
        let (private_key, public_key) = test_keypair();
        let message = b"Hello, Ethereum!";
        let hash = Sha256::digest(message);
        let mut msg_hash = [0u8; 32];
        msg_hash.copy_from_slice(&hash);
        
        let signature = TransactionSigner::sign(&private_key, &msg_hash, None).unwrap();
        let verified = TransactionSigner::verify(&public_key, &msg_hash, &signature).unwrap();
        assert!(verified);
    }
    
    #[test]
    fn test_sign_with_chain_id() {
        let (private_key, _) = test_keypair();
        let msg_hash = [0xab; 32];
        
        let sig = TransactionSigner::sign(&private_key, &msg_hash, Some(1)).unwrap();
        // EIP-155: v = rec_id + 1 * 2 + 35 = rec_id + 37
        assert!(sig.v >= 37);
    }
    
    #[test]
    fn test_recover_public_key() {
        let (private_key, public_key) = test_keypair();
        let msg_hash = [0xcd; 32];
        
        let sig = TransactionSigner::sign(&private_key, &msg_hash, None).unwrap();
        let rec_id = sig.recovery_id(None);
        let recovered = TransactionSigner::recover_public_key(&msg_hash, &sig, rec_id).unwrap();
        
        assert_eq!(recovered, public_key);
    }
    
    #[test]
    fn test_deterministic_signature() {
        let (private_key, _) = test_keypair();
        let msg_hash = [0xef; 32];
        
        let sig1 = TransactionSigner::sign(&private_key, &msg_hash, Some(1)).unwrap();
        let sig2 = TransactionSigner::sign(&private_key, &msg_hash, Some(1)).unwrap();
        
        assert_eq!(sig1.r, sig2.r);
        assert_eq!(sig1.s, sig2.s);
        assert_eq!(sig1.v, sig2.v);
    }
    
    #[test]
    fn test_signature_hex_roundtrip() {
        let (private_key, _) = test_keypair();
        let msg_hash = [0x42; 32];
        
        let sig = TransactionSigner::sign(&private_key, &msg_hash, None).unwrap();
        let hex_str = sig.to_hex();
        let decoded = Signature::from_hex(&hex_str).unwrap();
        
        assert_eq!(sig.r, decoded.r);
        assert_eq!(sig.s, decoded.s);
        assert_eq!(sig.v, decoded.v);
    }
}
