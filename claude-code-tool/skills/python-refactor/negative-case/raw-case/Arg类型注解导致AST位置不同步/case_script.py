"""
触发问题的重构脚本

尝试对包含类型注解的 Python 文件执行重构操作
"""

import sys
from pathlib import Path

# 使用本地修复版的 rope
ROPE_LOCAL = "/Users/zhushanwen/GitApp/rope"
sys.path.insert(0, ROPE_LOCAL)

from rope.base.project import Project
from rope.base.libutils import path_to_resource
from rope.refactor.rename import Rename


def main():
    """执行重构操作"""
    # 创建项目
    project_root = Path(__file__).parent / "case_src"
    project = Project(str(project_root))

    try:
        # 获取示例文件
        resource = path_to_resource(project, "example.py")

        # 尝试重命名函数 process_data -> process_items
        # 这个操作会触发 AST 解析，从而暴露 _arg 方法的问题
        renamer = Rename(project, resource, offset=None)

        # 获取可重命名的名称
        # 注意：这里需要找到 process_data 函数的位置
        source = resource.read()
        offset = source.find("def process_data")
        if offset == -1:
            print("ERROR: Cannot find process_data function")
            return

        # 使用正确的偏移量
        renamer = Rename(project, resource, offset=offset)

        # 获取变更预览
        changes = renamer.get_changes("process_items")
        print("Changes preview:")
        for change in changes.changes:
            print(f"  {change}")

        print("\nRefactoring completed successfully!")

    except Exception as e:
        print(f"ERROR: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
    finally:
        project.close()


if __name__ == "__main__":
    main()
