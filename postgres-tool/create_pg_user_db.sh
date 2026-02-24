#!/bin/sh

# 跟踪已执行的步骤（用于回滚）- 使用逗号分隔的字符串
COMPLETED_STEPS=""

# 记录步骤
record_step() {
    if [ -z "$COMPLETED_STEPS" ]; then
        COMPLETED_STEPS="$1"
    else
        COMPLETED_STEPS="$COMPLETED_STEPS,$1"
    fi
}

# 检查步骤是否已记录
has_step() {
    echo "$COMPLETED_STEPS" | grep -q ",$1," || echo "$COMPLETED_STEPS" | grep -q "^$1," || echo "$COMPLETED_STEPS" | grep -q ",$1$" || [ "$COMPLETED_STEPS" = "$1" ]
}

# 清理函数（用于回滚）
cleanup() {
    echo ""
    echo "========================================"
    echo "开始回滚操作..."
    echo "========================================"

    # 回滚用户
    if has_step "user"; then
        echo "删除用户 $NEW_USER..."
        su - postgres -c "psql -p $PG_PORT -c \"DROP USER IF EXISTS $NEW_USER;\"" 2>/dev/null || true
    fi

    # 回滚数据库
    if has_step "db"; then
        echo "删除数据库 $NEW_DB..."
        su - postgres -c "psql -p $PG_PORT -c \"DROP DATABASE IF EXISTS $NEW_DB;\"" 2>/dev/null || true
    fi

    # 回滚权限
    if has_step "db_privileges"; then
        echo "撤销数据库权限..."
        su - postgres -c "psql -p $PG_PORT -c \"REVOKE ALL PRIVILEGES ON DATABASE $NEW_DB FROM $NEW_USER;\"" 2>/dev/null || true
    fi

    if has_step "table_privileges"; then
        echo "撤销表权限..."
        su - postgres -c "psql -p $PG_PORT -c \"REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM $NEW_USER;\"" 2>/dev/null || true
    fi

    if has_step "sequence_privileges"; then
        echo "撤销序列权限..."
        su - postgres -c "psql -p $PG_PORT -c \"REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM $NEW_USER;\"" 2>/dev/null || true
    fi

    if has_step "function_privileges"; then
        echo "撤销函数权限..."
        su - postgres -c "psql -p $PG_PORT -c \"REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public FROM $NEW_USER;\"" 2>/dev/null || true
    fi

    if has_step "default_table_privileges"; then
        echo "撤销默认表权限..."
        su - postgres -c "psql -p $PG_PORT -c \"ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM $NEW_USER;\"" 2>/dev/null || true
    fi

    if has_step "default_sequence_privileges"; then
        echo "撤销默认序列权限..."
        su - postgres -c "psql -p $PG_PORT -c \"ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM $NEW_USER;\"" 2>/dev/null || true
    fi

    if has_step "default_function_privileges"; then
        echo "撤销默认函数权限..."
        su - postgres -c "psql -p $PG_PORT -c \"ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM $NEW_USER;\"" 2>/dev/null || true
    fi

    echo "回滚完成"
}

# 错误处理函数
handle_error() {
    error_msg="$1"
    echo ""
    echo "========================================"
    echo "错误：$error_msg"
    echo "========================================"
    echo "请选择操作："
    echo "  1) 立刻退出"
    echo "  2) 回滚之前的步骤 + 退出"
    echo "  3) 继续下一步"
    echo ""
    printf "请输入选项 (1/2/3): "
    read -r choice

    case "$choice" in
        1)
            echo "立刻退出"
            exit 1
            ;;
        2)
            cleanup
            exit 1
            ;;
        3)
            echo "继续下一步..."
            return 0
            ;;
        *)
            echo "无效选择，默认为立刻退出"
            exit 1
            ;;
    esac
}

# PostgreSQL 端口（默认 5432）
PG_PORT="5432"

# 检查是否以 root 用户运行
if [ "$USER" != "root" ]; then
    echo "错误：请以 root 用户运行此脚本"
    exit 1
fi

# 提示输入 PostgreSQL 端口
echo "请输入 PostgreSQL 端口（直接回车使用默认值 5432）："
read -r INPUT_PORT
if [ -n "$INPUT_PORT" ]; then
    PG_PORT="$INPUT_PORT"
fi
echo "使用端口：$PG_PORT"

# 检查 PostgreSQL 是否运行
echo "检查 PostgreSQL 服务状态..."
if ! su - postgres -c "psql -p $PG_PORT -c 'SELECT 1;'" > /dev/null 2>&1; then
    handle_error "PostgreSQL 服务未运行或无法连接 (端口: $PG_PORT)"
fi
echo "PostgreSQL 服务正常"

# 提示输入新用户名
echo ""
echo "请输入要创建的 PostgreSQL 用户名："
read -r NEW_USER

# 检查用户名是否为空
if [ -z "$NEW_USER" ]; then
    handle_error "用户名不能为空"
fi

# 检查用户名是否以 "pg_" 开头（保留前缀）
case "$NEW_USER" in
    pg_*)
        handle_error "用户名不能以 'pg_' 开头，这是 PostgreSQL 保留前缀"
        ;;
esac

# 检查用户名是否包含非法字符
case "$NEW_USER" in
    *[!a-zA-Z0-9_]*)
        handle_error "用户名只能包含字母、数字和下划线"
        ;;
    *)
        first_char="$(echo "$NEW_USER" | cut -c1)"
        case "$first_char" in
            [0-9])
                handle_error "用户名必须以字母或下划线开头"
                ;;
        esac
        ;;
esac

# 提示输入密码
echo "请输入用户密码："
read -r -s NEW_PASSWORD
echo ""

# 检查密码是否为空
if [ -z "$NEW_PASSWORD" ]; then
    handle_error "密码不能为空"
fi

# 确认密码
echo "请再次输入密码确认："
read -r -s CONFIRM_PASSWORD
echo ""

if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
    handle_error "两次输入的密码不一致"
fi

# 定义数据库名（与用户名相同）
NEW_DB="$NEW_USER"

# 检查用户是否已存在
echo "检查用户是否已存在..."
if su - postgres -c "psql -p $PG_PORT -c \"SELECT 1 FROM pg_roles WHERE rolname='$NEW_USER';\"" | grep -q "1"; then
    handle_error "用户 '$NEW_USER' 已存在"
fi
echo "用户不存在，可以创建"

# 检查数据库是否已存在
echo "检查数据库是否已存在..."
if su - postgres -c "psql -p $PG_PORT -c \"SELECT 1 FROM pg_database WHERE datname='$NEW_DB';\"" | grep -q "1"; then
    handle_error "数据库 '$NEW_DB' 已存在"
fi
echo "数据库不存在，可以创建"

# ========== 开始创建步骤 ==========

# 步骤 1: 创建用户
echo ""
echo "========== 步骤 1/9: 创建用户 =========="
if su - postgres -c "psql -p $PG_PORT -c \"CREATE USER $NEW_USER WITH PASSWORD '$NEW_PASSWORD';\"" 2>&1; then
    record_step "user"
    echo "用户创建成功"
else
    handle_error "创建用户失败"
fi

# 步骤 2: 创建数据库
echo ""
echo "========== 步骤 2/9: 创建数据库 =========="
if su - postgres -c "psql -p $PG_PORT -c \"CREATE DATABASE $NEW_DB OWNER $NEW_USER;\"" 2>&1; then
    record_step "db"
    echo "数据库创建成功"
else
    handle_error "创建数据库失败"
fi

# 步骤 3: 授予数据库权限
echo ""
echo "========== 步骤 3/9: 授予数据库权限 =========="
if su - postgres -c "psql -p $PG_PORT -c \"GRANT ALL PRIVILEGES ON DATABASE $NEW_DB TO $NEW_USER;\"" 2>&1; then
    record_step "db_privileges"
    echo "数据库权限授予成功"
else
    handle_error "授予数据库权限失败"
fi

# 步骤 4: 授予表权限
echo ""
echo "========== 步骤 4/9: 授予表权限 =========="
if su - postgres -c "psql -p $PG_PORT -c \"GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $NEW_USER;\"" 2>&1; then
    record_step "table_privileges"
    echo "表权限授予成功"
else
    handle_error "授予表权限失败"
fi

# 步骤 5: 授予序列权限
echo ""
echo "========== 步骤 5/9: 授予序列权限 =========="
if su - postgres -c "psql -p $PG_PORT -c \"GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $NEW_USER;\"" 2>&1; then
    record_step "sequence_privileges"
    echo "序列权限授予成功"
else
    handle_error "授予序列权限失败"
fi

# 步骤 6: 授予函数权限
echo ""
echo "========== 步骤 6/9: 授予函数权限 =========="
if su - postgres -c "psql -p $PG_PORT -c \"GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO $NEW_USER;\"" 2>&1; then
    record_step "function_privileges"
    echo "函数权限授予成功"
else
    handle_error "授予函数权限失败"
fi

# 步骤 7: 设置默认表权限
echo ""
echo "========== 步骤 7/9: 设置默认表权限 =========="
if su - postgres -c "psql -p $PG_PORT -c \"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $NEW_USER;\"" 2>&1; then
    record_step "default_table_privileges"
    echo "默认表权限设置成功"
else
    handle_error "设置默认表权限失败"
fi

# 步骤 8: 设置默认序列权限
echo ""
echo "========== 步骤 8/9: 设置默认序列权限 =========="
if su - postgres -c "psql -p $PG_PORT -c \"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $NEW_USER;\"" 2>&1; then
    record_step "default_sequence_privileges"
    echo "默认序列权限设置成功"
else
    handle_error "设置默认序列权限失败"
fi

# 步骤 9: 设置默认函数权限
echo ""
echo "========== 步骤 9/9: 设置默认函数权限 =========="
if su - postgres -c "psql -p $PG_PORT -c \"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO $NEW_USER;\"" 2>&1; then
    record_step "default_function_privileges"
    echo "默认函数权限设置成功"
else
    handle_error "设置默认函数权限失败"
fi

# 完成
echo ""
echo "========================================"
echo "操作完成！所有步骤执行成功！"
echo "========================================"
echo "创建的用户：$NEW_USER"
echo "创建的数据库：$NEW_DB"
echo "PostgreSQL 端口：$PG_PORT"
echo ""
echo "连接方式示例："
echo "  psql -h localhost -p $PG_PORT -U $NEW_USER -d $NEW_DB"
