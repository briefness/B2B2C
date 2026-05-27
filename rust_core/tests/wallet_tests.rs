//! B2B2C 钱包核心集成测试

use b2b2c_wallet_core::{MnemonicManager, Strength, KeyDeriver, Bip44Path, CryptoUtils};

#[test]
fn test_generate_mnemonic() {
    let mnemonic = MnemonicManager::generate(Strength::Bits128).unwrap();
    assert_eq!(mnemonic.len(), 12);
    println!("Generated mnemonic: {:?}", mnemonic);
}

#[test]
fn test_seed_derivation() {
    let mnemonic: Vec<String> = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        .split_whitespace().map(String::from).collect();
    
    let seed = MnemonicManager::to_seed(&mnemonic, "").unwrap();
    assert_eq!(seed.len(), 64);
    
    // 验证相同助记词产生相同种子
    let seed2 = MnemonicManager::to_seed(&mnemonic, "").unwrap();
    assert_eq!(seed.as_slice(), seed2.as_slice());
}

#[test]
fn test_key_derivation() {
    let mnemonic: Vec<String> = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        .split_whitespace().map(String::from).collect();
    
    let seed = MnemonicManager::to_seed(&mnemonic, "").unwrap();
    let path = Bip44Path::eth_default();
    
    let key = KeyDeriver::derive_path(seed.as_slice(), &path).unwrap();
    assert_eq!(key.key.len(), 32);
    
    let address = key.to_address();
    assert!(address.starts_with("0x"));
    assert_eq!(address.len(), 42);
    
    println!("Address: {}", address);
}

#[test]
fn test_crypto_utils() {
    let random = CryptoUtils::random_bytes(32).unwrap();
    assert_eq!(random.len(), 32);
    
    let hash = CryptoUtils::sha256(b"test");
    assert_eq!(hash.len(), 32);
    
    let hmac = CryptoUtils::hmac_sha256(b"key", b"message");
    assert_eq!(hmac.len(), 32);
}

#[test]
fn test_hex_conversion() {
    let data = vec![0xDE, 0xAD, 0xBE, 0xEF];
    let hex = CryptoUtils::to_hex(&data);
    assert_eq!(hex, "deadbeef");
    
    let decoded = CryptoUtils::from_hex("deadbeef").unwrap();
    assert_eq!(decoded, data);
}

#[test]
fn test_aes_gcm_roundtrip() {
    let key = [0x42u8; 32];
    let nonce = CryptoUtils::generate_nonce().unwrap();
    let plaintext = b"sensitive wallet data";
    
    let ciphertext = CryptoUtils::encrypt_aes_gcm(&key, &nonce, plaintext).unwrap();
    let decrypted = CryptoUtils::decrypt_aes_gcm(&key, &nonce, &ciphertext).unwrap();
    
    assert_eq!(&decrypted, plaintext);
}

#[test]
fn test_end_to_end_wallet_flow() {
    // 1. 生成助记词
    let mnemonic = MnemonicManager::generate(Strength::Bits128).unwrap();
    assert_eq!(mnemonic.len(), 12);
    
    // 2. 从助记词派生种子
    let seed = MnemonicManager::to_seed(&mnemonic, "").unwrap();
    assert_eq!(seed.len(), 64);
    
    // 3. 从种子派生密钥
    let path = Bip44Path::eth_default();
    let key = KeyDeriver::derive_path(seed.as_slice(), &path).unwrap();
    
    // 4. 获取地址
    let address = key.to_address();
    assert!(address.starts_with("0x"));
    assert_eq!(address.len(), 42);
    
    // 5. 签名交易
    let msg_hash = CryptoUtils::sha256(b"transfer 1 ETH");
    let sig = b2b2c_wallet_core::TransactionSigner::sign(&key.key, &msg_hash, Some(1)).unwrap();
    
    // 6. 恢复公钥验证
    let rec_id = sig.recovery_id(Some(1));
    let recovered_pubkey = b2b2c_wallet_core::TransactionSigner::recover_public_key(
        &msg_hash, &sig, rec_id
    ).unwrap();
    
    // 7. 验证签名
    let verified = b2b2c_wallet_core::TransactionSigner::verify(
        &recovered_pubkey, &msg_hash, &sig
    ).unwrap();
    assert!(verified);
    
    println!("E2E test passed! Address: {}", address);
}
