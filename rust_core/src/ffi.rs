//! FFI 接口模块
//! 
//! 定义供 Dart FFI 调用的 C-ABI 接口。
//! 所有函数签名保持向后兼容，确保 Dart 侧无需修改 bindings。

use crate::{
    mnemonic::{MnemonicManager, Strength},
    signing::TransactionSigner,
    key_derivation::{KeyDeriver, Bip44Path},
    crypto_utils::CryptoUtils,
};
use std::ffi::{CStr, CString};
use libc::{c_char, c_int};
use zeroize::Zeroize;

// ==================== 助记词 ====================

/// 生成助记词
/// 
/// # 参数
/// - `strength`: 强度 (128, 192, 256)
/// 
/// # 返回
/// 助记词字符串 (空格分隔)，调用方需通过 free_string 释放
#[no_mangle]
pub extern "C" fn generate_mnemonic(strength: c_int) -> *mut c_char {
    let strength = match strength {
        128 => Strength::Bits128,
        192 => Strength::Bits192,
        _ => Strength::Bits256,
    };
    
    match MnemonicManager::generate(strength) {
        Ok(words) => {
            let mnemonic = words.join(" ");
            match CString::new(mnemonic) {
                Ok(cs) => cs.into_raw(),
                Err(_) => std::ptr::null_mut(),
            }
        }
        Err(_) => std::ptr::null_mut(),
    }
}

/// 从助记词生成种子
/// 
/// # 返回
/// 种子 (64 字节十六进制字符串)，调用方需通过 free_string 释放
#[no_mangle]
pub extern "C" fn mnemonic_to_seed_hex(
    mnemonic_ptr: *const c_char,
    passphrase_ptr: *const c_char,
) -> *mut c_char {
    let mnemonic_str = unsafe {
        if mnemonic_ptr.is_null() {
            return std::ptr::null_mut();
        }
        CStr::from_ptr(mnemonic_ptr).to_string_lossy().into_owned()
    };
    
    let passphrase = unsafe {
        if passphrase_ptr.is_null() {
            return std::ptr::null_mut();
        }
        CStr::from_ptr(passphrase_ptr).to_string_lossy().into_owned()
    };
    
    let mnemonic: Vec<String> = mnemonic_str.split_whitespace().map(String::from).collect();
    
    match MnemonicManager::to_seed(&mnemonic, &passphrase) {
        Ok(seed) => {
            let hex = seed.to_hex();
            match CString::new(hex) {
                Ok(cs) => cs.into_raw(),
                Err(_) => std::ptr::null_mut(),
            }
        }
        Err(_) => std::ptr::null_mut(),
    }
}

/// 验证助记词
/// 
/// # 返回
/// 1 = 有效, 0 = 无效
#[no_mangle]
pub extern "C" fn validate_mnemonic(mnemonic_ptr: *const c_char) -> c_int {
    let mnemonic_str = unsafe {
        if mnemonic_ptr.is_null() {
            return 0;
        }
        CStr::from_ptr(mnemonic_ptr).to_string_lossy().into_owned()
    };
    
    let mnemonic: Vec<String> = mnemonic_str.split_whitespace().map(String::from).collect();
    
    match MnemonicManager::validate(&mnemonic) {
        Ok(_) => 1,
        Err(_) => 0,
    }
}

// ==================== 密钥派生 ====================

/// 从种子派生密钥
/// 
/// # 返回
/// 私钥 (32 字节十六进制字符串)，调用方需通过 free_string 释放
#[no_mangle]
pub extern "C" fn derive_key(
    seed_hex: *const c_char,
    path: *const c_char,
) -> *mut c_char {
    let seed_hex_str = unsafe {
        if seed_hex.is_null() || path.is_null() {
            return std::ptr::null_mut();
        }
        CStr::from_ptr(seed_hex).to_string_lossy().into_owned()
    };
    
    let path_str = unsafe {
        CStr::from_ptr(path).to_string_lossy().into_owned()
    };
    
    let seed = match CryptoUtils::from_hex(&seed_hex_str) {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    
    let bip44_path = match Bip44Path::from_string(&path_str) {
        Ok(p) => p,
        Err(_) => return std::ptr::null_mut(),
    };
    
    match KeyDeriver::derive_path(&seed, &bip44_path) {
        Ok(key) => {
            let private_key_hex = CryptoUtils::to_hex(&key.key);
            match CString::new(private_key_hex) {
                Ok(cs) => cs.into_raw(),
                Err(_) => std::ptr::null_mut(),
            }
        }
        Err(_) => std::ptr::null_mut(),
    }
}

/// 获取地址
/// 
/// # 返回
/// 以太坊地址字符串 (EIP-55 校验和格式)，调用方需通过 free_string 释放
#[no_mangle]
pub extern "C" fn derive_address(
    seed_hex: *const c_char,
    path: *const c_char,
) -> *mut c_char {
    let seed_hex_str = unsafe {
        if seed_hex.is_null() || path.is_null() {
            return std::ptr::null_mut();
        }
        CStr::from_ptr(seed_hex).to_string_lossy().into_owned()
    };
    
    let path_str = unsafe {
        CStr::from_ptr(path).to_string_lossy().into_owned()
    };
    
    let seed = match CryptoUtils::from_hex(&seed_hex_str) {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    
    let bip44_path = match Bip44Path::from_string(&path_str) {
        Ok(p) => p,
        Err(_) => return std::ptr::null_mut(),
    };
    
    match KeyDeriver::derive_path(&seed, &bip44_path) {
        Ok(key) => {
            let address = key.to_address();
            match CString::new(address) {
                Ok(cs) => cs.into_raw(),
                Err(_) => std::ptr::null_mut(),
            }
        }
        Err(_) => std::ptr::null_mut(),
    }
}

// ==================== 签名 ====================

/// 对交易签名
/// 
/// # 返回
/// 签名 (65 字节十六进制字符串: r || s || v)，调用方需通过 free_string 释放
#[no_mangle]
pub extern "C" fn sign_transaction(
    private_key_hex: *const c_char,
    message_hash_hex: *const c_char,
    chain_id: u64,
) -> *mut c_char {
    let private_key_str = unsafe {
        if private_key_hex.is_null() || message_hash_hex.is_null() {
            return std::ptr::null_mut();
        }
        CStr::from_ptr(private_key_hex).to_string_lossy().into_owned()
    };
    
    let message_hash_str = unsafe {
        CStr::from_ptr(message_hash_hex).to_string_lossy().into_owned()
    };
    
    let mut private_key_bytes = match CryptoUtils::from_hex(&private_key_str) {
        Ok(bytes) => {
            if bytes.len() != 32 {
                return std::ptr::null_mut();
            }
            bytes
        }
        Err(_) => return std::ptr::null_mut(),
    };
    
    let mut private_key = [0u8; 32];
    private_key.copy_from_slice(&private_key_bytes);
    // 立即清零临时缓冲区
    private_key_bytes.zeroize();
    
    let message_hash = match CryptoUtils::from_hex(&message_hash_str) {
        Ok(bytes) => {
            if bytes.len() != 32 {
                return std::ptr::null_mut();
            }
            let mut hash = [0u8; 32];
            hash.copy_from_slice(&bytes);
            hash
        }
        Err(_) => return std::ptr::null_mut(),
    };
    
    let chain_id_opt = if chain_id > 0 { Some(chain_id) } else { None };
    
    let result = match TransactionSigner::sign(&private_key, &message_hash, chain_id_opt) {
        Ok(sig) => {
            let sig_hex = sig.to_hex();
            match CString::new(sig_hex) {
                Ok(cs) => cs.into_raw(),
                Err(_) => std::ptr::null_mut(),
            }
        }
        Err(_) => std::ptr::null_mut(),
    };
    
    // 使用后清零私钥
    private_key.zeroize();
    
    result
}

// ==================== 加密工具 ====================

/// 计算 HMAC-SHA256
/// 
/// # 返回
/// HMAC (32 字节十六进制字符串)，调用方需通过 free_string 释放
#[no_mangle]
pub extern "C" fn compute_hmac(
    key_hex: *const c_char,
    message_hex: *const c_char,
) -> *mut c_char {
    let key_str = unsafe {
        if key_hex.is_null() || message_hex.is_null() {
            return std::ptr::null_mut();
        }
        CStr::from_ptr(key_hex).to_string_lossy().into_owned()
    };
    
    let message_str = unsafe {
        CStr::from_ptr(message_hex).to_string_lossy().into_owned()
    };
    
    let key = match CryptoUtils::from_hex(&key_str) {
        Ok(bytes) => bytes,
        Err(_) => return std::ptr::null_mut(),
    };
    
    let message = match CryptoUtils::from_hex(&message_str) {
        Ok(bytes) => bytes,
        Err(_) => return std::ptr::null_mut(),
    };
    
    let hmac = CryptoUtils::hmac_sha256(&key, &message);
    let hmac_hex = CryptoUtils::to_hex(&hmac);
    
    match CString::new(hmac_hex) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// 生成随机字节
/// 
/// # 返回
/// 随机字节 (十六进制字符串)，调用方需通过 free_string 释放
#[no_mangle]
pub extern "C" fn generate_random_bytes(len: c_int) -> *mut c_char {
    let bytes = match CryptoUtils::random_bytes(len as usize) {
        Ok(b) => b,
        Err(_) => return std::ptr::null_mut(),
    };
    
    let hex = bytes.to_hex();
    match CString::new(hex) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// SHA256 哈希
/// 
/// # 返回
/// 哈希 (32 字节十六进制字符串)，调用方需通过 free_string 释放
#[no_mangle]
pub extern "C" fn sha256_hash(data_hex: *const c_char) -> *mut c_char {
    let data_str = unsafe {
        if data_hex.is_null() {
            return std::ptr::null_mut();
        }
        CStr::from_ptr(data_hex).to_string_lossy().into_owned()
    };
    
    let data = match CryptoUtils::from_hex(&data_str) {
        Ok(bytes) => bytes,
        Err(_) => return std::ptr::null_mut(),
    };
    
    let hash = CryptoUtils::sha256(&data);
    let hash_hex = CryptoUtils::to_hex(&hash);
    
    match CString::new(hash_hex) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

// ==================== 内存管理 ====================

/// 通用字符串释放函数
/// 
/// 释放由 Rust 分配的 C 字符串内存
#[no_mangle]
pub unsafe extern "C" fn free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        // 先获取长度，清零内存，再释放
        let cs = CString::from_raw(ptr);
        let mut bytes = cs.into_bytes_with_nul();
        bytes.zeroize();
    }
}

/// 释放助记词字符串内存 (向后兼容别名)
#[no_mangle]
pub unsafe extern "C" fn free_mnemonic(ptr: *mut c_char) {
    free_string(ptr);
}

// ==================== 版本信息 ====================

/// 获取库版本
#[no_mangle]
pub extern "C" fn get_version() -> *mut c_char {
    CString::new("2.0.0").unwrap().into_raw()
}
