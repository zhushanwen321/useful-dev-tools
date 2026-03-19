#!/usr/bin/env python3
"""
重构脚本：移动 api/constant/constants.py 到 api/shared/constant/

方案：rope 移动文件 + 正则表达式修复导入

由于 rope.MoveModule 在跨层级移动时无法正确计算导入路径，
采用组合策略完成重构。
"""

import re
import sys
from pathlib import Path

# 使用本地修复版的 rope
ROPE_LOCAL = "/Users/zhushanwen/GitApp/rope"
sys.path.insert(0, ROPE_LOCAL)

from rope.base.project import Project
from rope.base.libutils import path_to_resource
from rope.refactor.move import MoveModule


# ============================================================================
# 导入路径修复规则
# ============================================================================

IMPORT_FIXES = [
    # 修复从 constant.constants 导入
    (
        r'from constant\.constants import',
        'from app.api.shared.constant.constants import'
    ),
    # 修复旧的 app.api.constant.constants 导入（rope 应该已处理，但作为保险）
    (
        r'from app\.api\.constant\.constants import',
        'from app.api.shared.constant.constants import'
    ),
    # 修复 import app.api.constant.constants 形式
    (
        r'import app\.api\.constant\.constants\s',
        'import app.api.shared.constant.constants '
    ),
]


def fix_imports_in_file(file_path: Path) -> bool:
    """修复单个文件中的导入路径，返回是否有修改"""
    content = file_path.read_text(encoding='utf-8')
    original_content = content

    for pattern, replacement in IMPORT_FIXES:
        content = re.sub(pattern, replacement, content)

    if content != original_content:
        file_path.write_text(content, encoding='utf-8')
        return True
    return False


def main():
    # 项目根目录
    project_root = Path("/Users/zhushanwen/Code/stock-data-crawler")

    # 创建项目
    project = Project(str(project_root), source_folders=["backend/app"])

    try:
        # 源模块路径
        source_module_path = "backend/app/api/constant/constants.py"

        # 目标目录
        target_dir = "backend/app/api/shared/constant"

        # 创建目标目录
        target_path = project_root / target_dir
        target_path.mkdir(parents=True, exist_ok=True)

        # 获取源资源
        source_resource = path_to_resource(project, source_module_path)

        # 获取目标目录资源
        target_folder = project.get_folder(target_dir)
        if target_folder is None:
            target_folder = project.root.create_folder(target_dir)

        print("=" * 60)
        print("步骤 1: 使用 rope 移动文件")
        print("=" * 60)

        # 创建移动重构对象
        mover = MoveModule(project, source_resource)

        # 获取变更
        changes = mover.get_changes(target_folder)

        # 执行变更
        project.do(changes)

        print(f"✅ 文件已移动: {source_module_path} -> {target_dir}/constants.py")

        print("\n" + "=" * 60)
        print("步骤 2: 修复导入路径")
        print("=" * 60)

        # 查找所有可能需要修复导入的 Python 文件
        # rope 变更列表中包含的文件
        fixed_files = []

        # 首先修复 rope 变更列表中的文件
        for change in changes.changes:
            if change.resource.path.endswith('.py'):
                file_path = project_root / change.resource.path
                if file_path.exists() and fix_imports_in_file(file_path):
                    fixed_files.append(change.resource.path)
                    print(f"  修复: {change.resource.path}")

        # 额外搜索可能包含错误导入的文件
        print("\n搜索其他可能需要修复的文件...")
        all_py_files = list((project_root / "backend").rglob("*.py"))

        for py_file in all_py_files:
            # 跳过已修复的文件
            rel_path = str(py_file.relative_to(project_root))
            if rel_path in fixed_files:
                continue

            # 检查是否包含错误的导入
            content = py_file.read_text(encoding='utf-8')
            if 'from constant.constants import' in content:
                if fix_imports_in_file(py_file):
                    fixed_files.append(rel_path)
                    print(f"  修复: {rel_path}")

        print(f"\n✅ 共修复 {len(fixed_files)} 个文件的导入路径")

        print("\n" + "=" * 60)
        print("步骤 3: 创建 __init__.py 文件")
        print("=" * 60)

        # 创建 __init__.py 保持包结构
        init_path = project_root / "backend/app/api/shared/__init__.py"
        if not init_path.exists():
            init_path.parent.mkdir(parents=True, exist_ok=True)
            init_path.write_text("# shared package\n")
            print(f"创建: {init_path}")

        init_const_path = project_root / "backend/app/api/shared/constant/__init__.py"
        if not init_const_path.exists():
            init_const_path.write_text("# constant package\n")
            print(f"创建: {init_const_path}")

        print("\n" + "=" * 60)
        print("步骤 4: 验证重构结果")
        print("=" * 60)

        # 验证目标文件存在
        target_file = project_root / target_dir / "constants.py"
        if target_file.exists():
            print(f"✅ 目标文件存在: {target_dir}/constants.py")
        else:
            print(f"❌ 目标文件不存在!")

        # 验证源文件已删除
        source_file = project_root / source_module_path
        if not source_file.exists():
            print(f"✅ 源文件已删除: {source_module_path}")
        else:
            print(f"⚠️  源文件仍然存在，请手动删除")

        # 检查是否还有错误的导入
        print("\n检查残留的错误导入...")
        remaining_errors = []
        for py_file in all_py_files:
            content = py_file.read_text(encoding='utf-8')
            if 'from constant.constants import' in content:
                remaining_errors.append(str(py_file.relative_to(project_root)))

        if remaining_errors:
            print(f"⚠️  仍有 {len(remaining_errors)} 个文件包含错误导入:")
            for err in remaining_errors:
                print(f"    {err}")
        else:
            print("✅ 未发现残留的错误导入")

        print("\n" + "=" * 60)
        print("✅ 重构完成！")
        print("=" * 60)
        print("\n建议：运行测试验证重构结果")
        print("  cd backend && uv run pytest")

    finally:
        project.close()


if __name__ == "__main__":
    main()
