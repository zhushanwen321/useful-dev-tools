---
category: tool-config
created: 2026-03-20
tags: [pyright, config, hook]
---

# Pyright 配置文件位置

## 场景

当项目同时有 Git Hook 和 Pyright 类型检查时，配置文件位置导致 Hook 无法正确读取配置。

## 问题

`pyrightconfig.json` 位于 `backend/` 子目录，但 Git Hook 脚本在项目根目录运行 `pyright` 命令，导致：

1. Pyright 使用默认配置（更严格）而非项目配置
2. 配置的 `typeCheckingMode: "basic"` 和 `warning` 级别未生效
3. Hook 报告大量本应为 warning 的类型问题

## 选项

1. **修改 Hook 脚本切换目录**
   - 在 Hook 中 `cd backend` 后再运行 `pyright`
   - 优点：配置文件位置不变
   - 缺点：需要修改受保护的 Hook 源文件

2. **移动配置文件到项目根目录**
   - 将 `pyrightconfig.json` 移至项目根目录
   - 修改 `include: ["backend"]`
   - 优点：Hook 无需修改，配置可被正确读取
   - 缺点：配置文件与源码分离

3. **使用 `--level error` 选项**
   - 修改 Hook 脚本使用 `pyright --level error`
   - 优点：只检查 errors，忽略 warnings
   - 缺点：需要修改 Hook 脚本

## 选择

**选项 2**：移动配置文件到项目根目录

```json
{
  "include": ["backend"],
  "exclude": ["**/__pycache__", "**/node_modules", "**/.venv", "tests", "alembic", "scripts"],
  "pythonVersion": "3.12",
  "typeCheckingMode": "basic",
  "reportMissingImports": "warning",
  // ... 其他 warning 级别配置
}
```

## 理由

1. **最小改动**：只需移动文件并修改 `include` 路径
2. **兼容性好**：不依赖修改 Hook 脚本（受保护文件）
3. **配置集中**：项目根目录是配置文件的标准位置
4. **CI/CD 一致**：本地和 CI 环境都在根目录运行，行为一致

## 相关文件

- 提交: f0ab34f, f2f59a6
- 变更: backend/pyrightconfig.json → pyrightconfig.json
