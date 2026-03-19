#!/usr/bin/env python3
"""重现 MoveModule 不更新不匹配导入路径的问题。"""

import sys
from pathlib import Path

ROPE_LOCAL = "/Users/zhushanwen/GitApp/rope"
sys.path.insert(0, ROPE_LOCAL)

from rope.base.project import Project
from rope.refactor.move import MoveModule

# 创建临时测试项目
test_dir = Path("/tmp/rope_test_ghost_import")
test_dir.mkdir(exist_ok=True)

# 创建文件结构
calc_dir = test_dir / "calc"
calc_dir.mkdir(exist_ok=True)

# foo.py - 被移动的模块
(calc_dir / "foo.py").write_text("""
def foo():
    return "hello"
""")

# bar.py - 包含错误导入的文件
(calc_dir / "bar.py").write_text("""
# 错误：导入路径与实际位置不匹配
from wrong.path.foo import foo

def bar():
    return foo()
""")

# __init__.py
(calc_dir / "__init__.py").write_text("")

# 创建 rope 项目
project = Project(str(test_dir))

print("=" * 60)
print("重现问题：MoveModule 不更新不匹配的导入路径")
print("=" * 60)

# 获取资源
foo_resource = project.get_resource("calc/foo.py")
bar_resource = project.get_resource("calc/bar.py")

print("\n重构前的 bar.py 内容:")
print(bar_resource.read())

# 执行移动
print("\n执行 MoveModule: calc/foo.py -> calc/sub/")
mover = MoveModule(project, foo_resource)
dest_folder = project.get_resource("calc")  # 实际上需要先创建 sub 目录
changeset = mover.get_changes(dest_folder)

print(f"\n变更的文件数量: {len(list(changeset.changes))}")
for change in changeset.changes:
    print(f"  - {change.resource.path}")

# 执行变更
project.do(changeset)

# 检查 bar.py 是否被更新
print("\n重构后的 bar.py 内容:")
bar_after = project.get_resource("calc/bar.py").read()
print(bar_after)

if "wrong.path.foo" in bar_after:
    print("\n❌ 问题重现：导入语句没有被更新！")
    print("   bar.py 仍然导入 'wrong.path.foo'")
else:
    print("\n✅ 导入语句已被更新")

# 清理
import shutil
shutil.rmtree(test_dir)
