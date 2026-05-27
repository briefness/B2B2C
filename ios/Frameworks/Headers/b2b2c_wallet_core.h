#ifndef B2B2C_WALLET_CORE_H
#define B2B2C_WALLET_CORE_H

#include <stdint.h>

// 助记词
char* generate_mnemonic(int32_t strength);
char* mnemonic_to_seed_hex(const char* mnemonic, const char* passphrase);
int32_t validate_mnemonic(const char* mnemonic);

// 密钥派生
char* derive_key(const char* seed_hex, const char* path);
char* derive_address(const char* seed_hex, const char* path);

// 签名
char* sign_transaction(const char* private_key_hex, const char* message_hash_hex, uint64_t chain_id);

// 加密工具
char* compute_hmac(const char* key_hex, const char* message_hex);
char* generate_random_bytes(int32_t len);
char* sha256_hash(const char* data_hex);

// 内存管理
void free_string(char* ptr);
void free_mnemonic(char* ptr);

// 版本
char* get_version(void);

#endif
