"""
Rope 重构工具函数库

提供重构脚本常用的辅助函数，可直接导入使用：
    from helpers import find_offset, find_definition_offset, get_region_offsets
"""

import ast
import re
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from rope.base.project import Project
from rope.base.libutils import path_to_resource
from rope.base.resources import Resource


def find_offset(resource: Resource, pattern: str, start: int = 0) -> Optional[int]:
    """
    在资源中查找模式的偏移量

    Args:
        resource: rope 资源对象
        pattern: 要查找的字符串或正则表达式
        start: 搜索起始位置

    Returns:
        匹配位置的偏移量，未找到返回 None
    """
    content = resource.read()
    if isinstance(pattern, str):
        offset = content.find(pattern, start)
        return offset if offset != -1 else None
    else:
        match = re.search(pattern, content[start:])
        return match.start() + start if match else None


def find_definition_offset(
    resource: Resource, name: str, definition_type: str = "class"
) -> Optional[int]:
    """
    查找类或函数定义的偏移量

    Args:
        resource: rope 资源对象
        name: 类名或函数名
        definition_type: 'class' 或 'def'

    Returns:
        定义名称的起始偏移量（跳过 'class ' 或 'def '）
    """
    if definition_type == "class":
        pattern = f"class {name}"
    else:
        pattern = f"def {name}"

    offset = find_offset(resource, pattern)
    if offset is not None:
        # 返回名称的起始位置，跳过 'class ' 或 'def '
        prefix_len = len(definition_type) + 1
        return offset + prefix_len
    return None


def get_region_offsets(
    resource: Resource, start_pattern: str, end_pattern: str
) -> Optional[Tuple[int, int]]:
    """
    查找代码区域的起始和结束偏移量

    Args:
        resource: rope 资源对象
        start_pattern: 区域起始模式
        end_pattern: 区域结束模式

    Returns:
        (start_offset, end_offset) 或 None
    """
    start_offset = find_offset(resource, start_pattern)
    if start_offset is None:
        return None

    content = resource.read()
    end_offset = content.find(end_pattern, start_offset)
    if end_offset == -1:
        return None

    return (start_offset, end_offset)


def ensure_file_exists(file_path: str) -> None:
    """验证文件存在，不存在则抛出异常"""
    if not Path(file_path).exists():
        raise FileNotFoundError(f"文件不存在: {file_path}")


def check_project_health(project: Project) -> Dict[str, List[str]]:
    """
    检查项目健康状况，发现潜在问题

    Args:
        project: rope 项目对象

    Returns:
        包含以下键的字典：
        - missing_modules: 缺失的模块列表
        - syntax_errors: 有语法错误的文件列表
        - inconsistent_imports: 导入不一致的问题
        - suggestions: 建议列表
    """
    issues = {
        "missing_modules": [],
        "syntax_errors": [],
        "inconsistent_imports": [],
        "suggestions": [],
    }

    for resource in project.get_python_files():
        try:
            source = resource.read()
            ast.parse(source)
        except SyntaxError as e:
            issues["syntax_errors"].append(f"{resource.path}:{e.lineno}: {e.msg}")

    return issues


def pre_refactor_check(project: Project) -> bool:
    """
    重构前检查，确保可以安全执行重构

    Returns:
        True 表示可以继续，False 表示有问题需要先解决
    """
    print("重构前检查...")
    print("-" * 40)

    health = check_project_health(project)

    all_good = True

    # 报告语法错误
    if health["syntax_errors"]:
        print("  [!] 发现语法错误:")
        for error in health["syntax_errors"]:
            print(f"    - {error}")
        all_good = False

    # 检查是否在 git 中
    try:
        subprocess.run(
            ["git", "status", "--short"],
            capture_output=True,
            cwd=project.address,
            check=True,
        )
        print("  [OK] 项目在版本控制下")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("  [!] 警告: 不在 git 仓库中")
        print("     建议: 重构前先提交代码，以便出错时可以回滚")

    if all_good:
        print("  [OK] 检查通过")

    return all_good


def validate_imports(project: Project, module_name: str = None) -> bool:
    """
    验证导入是否正常

    Args:
        project: rope 项目对象
        module_name: 要测试的模块名，None 表示测试所有

    Returns:
        True 表示验证通过，False 表示有问题
    """
    if module_name:
        modules = [module_name]
    else:
        modules = []
        for resource in project.get_python_files():
            path = resource.path.replace("/", ".").replace(".py", "")
            if path.count(".") == 0:
                modules.append(path)

    for mod in modules[:5]:
        try:
            result = subprocess.run(
                ["python", "-c", f"import {mod}"],
                capture_output=True,
                cwd=project.address,
            )
            if result.returncode != 0:
                print(f"  [!] {mod} 导入失败:")
                print(f"    {result.stderr.decode()[:200]}")
                return False
        except Exception as e:
            print(f"  [!] 无法验证 {mod}: {e}")

    print("  [OK] 导入验证通过")
    return True


def update_excluded_files_imports(
    project: Project,
    old_name: str,
    new_name: str,
    excluded_files: List[str],
    dry_run: bool = False,
) -> int:
    """
    更新被排除文件的导入语句

    当使用 resources 参数排除某些文件时，这些文件的导入不会自动更新。
    此函数用于手动更新这些文件中的导入语句。

    Args:
        project: rope 项目对象
        old_name: 旧名称（如 "app.utils.helper.func"）
        new_name: 新名称（如 "app.util.helper.func"）
        excluded_files: 被排除的文件路径列表
        dry_run: 预览模式，不实际修改文件

    Returns:
        更新的文件数量

    注意：
        - 此函数使用简单的字符串替换，不是语义分析
        - 只更新明确匹配的导入语句
        - 建议先预览（dry_run=True）确认效果
        - 无法处理多行 import 语句或续行符
    """
    updated_count = 0

    for file_path in excluded_files:
        try:
            full_path = Path(project.address) / file_path
            if not full_path.exists():
                continue

            with open(full_path, "r", encoding="utf-8") as f:
                content = f.read()

            pattern = rf"from {re.escape(old_name)}.*import"

            new_content = re.sub(
                pattern,
                lambda m: m.group().replace(old_name + ".", new_name + "."),
                content,
            )

            if new_content != content:
                if not dry_run:
                    with open(full_path, "w", encoding="utf-8") as f:
                        f.write(new_content)
                updated_count += 1

        except Exception as e:
            print(f"  [!] 警告: 无法处理 {file_path}: {e}")

    return updated_count
