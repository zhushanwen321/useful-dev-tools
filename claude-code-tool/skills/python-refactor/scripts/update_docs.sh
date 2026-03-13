#!/usr/bin/env bash
# Rope 文档更新脚本
# 从 GitHub 下载最新的 rope 文档

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$SKILL_DIR/references/rope-docs"
TEMP_DIR=$(mktemp -d)
REPO_URL="https://github.com/python-rope/rope.git"

echo -e "${GREEN}=== Rope 文档更新脚本 ===${NC}"
echo ""

# 清理函数
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        echo -e "${YELLOW}清理临时目录...${NC}"
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# 1. 克隆仓库到临时目录
echo -e "${GREEN}[1/4]${NC} 克隆 rope 仓库..."
echo "  仓库: $REPO_URL"
echo "  临时目录: $TEMP_DIR"

if ! git clone --depth 1 --single-branch --branch master "$REPO_URL" "$TEMP_DIR" 2>/dev/null; then
    echo -e "${RED}错误: 克隆仓库失败${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 克隆成功${NC}"
echo ""

# 2. 检查文档目录是否存在
echo -e "${GREEN}[2/4]${NC} 检查文档目录..."
DOC_SOURCE_DIR="$TEMP_DIR/docs"

if [ ! -d "$DOC_SOURCE_DIR" ]; then
    echo -e "${YELLOW}警告: docs 目录不存在，尝试查找其他文档位置...${NC}"
    # 检查可能的文档位置
    for alt_dir in "doc" "documentation" "readthedocs"; do
        if [ -d "$TEMP_DIR/$alt_dir" ]; then
            DOC_SOURCE_DIR="$TEMP_DIR/$alt_dir"
            echo -e "${GREEN}找到文档目录: $alt_dir${NC}"
            break
        fi
    done

    if [ ! -d "$DOC_SOURCE_DIR" ]; then
        # 如果没有找到 docs 目录，获取整个 README 作为文档
        echo -e "${YELLOW}未找到独立文档目录，将复制 README 和主要源文件${NC}"
        DOC_SOURCE_DIR="$TEMP_DIR"
    fi
fi
echo -e "${GREEN}✓ 文档目录: $DOC_SOURCE_DIR${NC}"
echo ""

# 3. 删除旧文档
echo -e "${GREEN}[3/4]${NC} 删除旧文档..."
if [ -d "$DOCS_DIR" ]; then
    echo "  删除: $DOCS_DIR"
    rm -rf "$DOCS_DIR"
fi
echo -e "${GREEN}✓ 旧文档已删除${NC}"
echo ""

# 4. 复制新文档
echo -e "${GREEN}[4/4]${NC} 复制新文档..."
mkdir -p "$DOCS_DIR"

# 复制文档内容
if [ -d "$DOC_SOURCE_DIR" ] && [ "$DOC_SOURCE_DIR" != "$TEMP_DIR" ]; then
    cp -r "$DOC_SOURCE_DIR"/* "$DOCS_DIR/"
else
    # 复制 README 和其他重要文件
    for file in README.rst README.md CONTRIBUTING.rst CHANGELOG.rst; do
        if [ -f "$TEMP_DIR/$file" ]; then
            cp "$TEMP_DIR/$file" "$DOCS_DIR/"
        fi
    done
    # 复制源代码作为参考
    mkdir -p "$DOCS_DIR/source"
    cp -r "$TEMP_DIR/rope"/* "$DOCS_DIR/source/" 2>/dev/null || true
fi

# 添加说明文件
cat > "$DOCS_DIR/README.md" << 'EOF'
# Rope 文档

本目录包含从 rope 官方仓库下载的文档。

## 在线文档

- 官方文档 (Read the Docs): https://rope.readthedocs.io/
- GitHub 仓库: https://github.com/python-rope/rope

## 本地文件

- `overview.rst` - Rope 概述
- `library.rst` - 使用 Rope 作为库
- `config.rst` - 配置说明
- `source/` - rope 源代码（参考）

## 更新文档

运行更新脚本：
```bash
bash scripts/update_docs.sh
```
EOF

# 统计文件数量
FILE_COUNT=$(find "$DOCS_DIR" -type f | wc -l)
echo -e "${GREEN}✓ 文档已复制 ($FILE_COUNT 个文件)${NC}"
echo ""

# 完成
echo -e "${GREEN}=== 文档更新完成 ===${NC}"
echo "  文档位置: $DOCS_DIR"
echo ""
echo "在线文档链接:"
echo "  - https://rope.readthedocs.io/"
echo "  - https://github.com/python-rope/rope"
