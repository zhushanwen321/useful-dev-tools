#!/usr/bin/env python3
"""从 Chrome Cookie 数据库读取智谱 bigmodel_token_production

首次运行时 macOS 会弹出 Keychain 授权对话框，点击「始终允许」后后续运行无需再次授权。
"""

import hashlib
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile

TOKEN_CACHE = os.path.expanduser("~/.claude/.zhipu_auth_token")
KEYCHAIN_TIMEOUT = 10  # 等待 Keychain 授权的最长时间（秒）


def get_chrome_key() -> bytes:
    """从 macOS Keychain 获取 Chrome Safe Storage 密钥，派生 AES 密钥"""
    try:
        result = subprocess.run(
            [
                "security",
                "find-generic-password",
                "-w",
                "-s",
                "Chrome Safe Storage",
            ],
            capture_output=True,
            text=True,
            timeout=KEYCHAIN_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError(
            "Keychain 授权超时，请在弹出的对话框中点击「始终允许」后重试"
        )

    if result.returncode != 0:
        raise RuntimeError(f"无法从 Keychain 获取 Chrome Safe Storage: {result.stderr}")

    password = result.stdout.strip().encode("utf-8")
    # Chrome on macOS: PBKDF2-HMAC-SHA1, salt="saltysalt", iterations=1003, keylen=16
    return hashlib.pbkdf2_hmac("sha1", password, b"saltysalt", 1003, dklen=16)


def decrypt_value(encrypted: bytes, key: bytes) -> str:
    """解密 Chrome cookie 值 (v10 格式, AES-128-CBC)"""
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

    if encrypted[:3] != b"v10":
        return encrypted.decode("utf-8", errors="replace")

    iv = b" " * 16
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
    decryptor = cipher.decryptor()
    decrypted = decryptor.update(encrypted[3:]) + decryptor.finalize()

    # PKCS7 去填充
    pad_len = decrypted[-1]
    if 0 < pad_len <= 16:
        decrypted = decrypted[:-pad_len]

    return decrypted.decode("utf-8", errors="replace")


def find_cookie_db() -> str:
    """查找 Chrome Cookie 数据库路径"""
    chrome_dir = os.path.expanduser(
        "~/Library/Application Support/Google/Chrome"
    )
    candidates = ["Default"]
    if os.path.isdir(chrome_dir):
        for name in sorted(os.listdir(chrome_dir)):
            if name.startswith("Profile"):
                candidates.append(name)

    for profile in candidates:
        cookie_path = os.path.join(chrome_dir, profile, "Cookies")
        if os.path.exists(cookie_path):
            return cookie_path

    raise FileNotFoundError("未找到 Chrome Cookie 数据库")


def get_token() -> str | None:
    """获取 bigmodel_token_production cookie 值"""
    cookie_db = find_cookie_db()
    key = get_chrome_key()

    # 复制到临时文件，避免 Chrome 锁定问题
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
        tmp_path = tmp.name
    shutil.copy2(cookie_db, tmp_path)

    try:
        conn = sqlite3.connect(tmp_path)
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT encrypted_value
            FROM cookies
            WHERE host_key LIKE '%%bigmodel.cn%%'
              AND name = 'bigmodel_token_production'
            ORDER BY creation_utc DESC
            LIMIT 1
            """
        )
        row = cursor.fetchone()
        conn.close()
    finally:
        os.unlink(tmp_path)

    if row and row[0]:
        return decrypt_value(row[0], key)

    return None


def save_token_cache(token: str) -> None:
    """将 token 写入缓存文件（权限 600）"""
    with open(TOKEN_CACHE, "w") as f:
        f.write(token)
    os.chmod(TOKEN_CACHE, 0o600)


def read_token_cache() -> str | None:
    """从缓存文件读取 token"""
    if not os.path.exists(TOKEN_CACHE):
        return None
    try:
        with open(TOKEN_CACHE) as f:
            return f.read().strip() or None
    except OSError:
        return None


if __name__ == "__main__":
    # 优先使用缓存
    cached = read_token_cache()
    if cached:
        print(cached)
        sys.exit(0)

    # 缓存不存在，尝试从 Chrome 读取
    try:
        token = get_token()
        if token:
            save_token_cache(token)
            print(token)
        else:
            print(
                "ERROR: 未找到 bigmodel_token_production cookie", file=sys.stderr
            )
            sys.exit(1)
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        print(f"请手动在终端运行: python3 {__file__}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
