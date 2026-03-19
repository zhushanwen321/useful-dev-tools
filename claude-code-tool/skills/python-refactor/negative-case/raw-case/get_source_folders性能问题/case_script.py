#!/usr/bin/env python3
"""
性能分析脚本：分析 rope MoveModule.get_changes 的性能瓶颈

问题：get_changes 在 606 个文件的项目中执行需要 53 秒
"""

import sys
import shutil
import time
import cProfile
import pstats
import io
from pathlib import Path
from contextlib import contextmanager

from rope.base.project import Project
from rope.refactor.move import MoveModule


@contextmanager
def timer(name, indent=0):
    """计时上下文管理器"""
    prefix = "  " * indent
    t0 = time.perf_counter()
    yield
    elapsed = time.perf_counter() - t0
    print(f"{prefix}{name}: {elapsed:.3f}s")


def analyze_get_changes_detail(project, mover, target, resources, indent=1):
    """详细分析 get_changes 内部各步骤的耗时"""
    prefix = "  " * indent

    total_files = len(resources)
    files_with_occurrences = 0

    time_occurs = 0
    time_get_pymodule = 0
    time_change_module = 0

    print(f"{prefix}分析 {total_files} 个文件...")

    for i, resource in enumerate(resources):
        if i % 100 == 0:
            print(f"{prefix}  进度: {i}/{total_files}")

        t0 = time.perf_counter()
        occurs = mover.tools.occurs_in_module(resource=resource)
        t1 = time.perf_counter()
        time_occurs += (t1 - t0)

        if occurs:
            files_with_occurrences += 1
            t0 = time.perf_counter()
            pymodule = project.get_pymodule(resource)
            t1 = time.perf_counter()
            time_get_pymodule += (t1 - t0)

            t0 = time.perf_counter()
            source = mover._change_occurrences_in_module(target, resource=resource)
            t1 = time.perf_counter()
            time_change_module += (t1 - t0)

    print(f"{prefix}结果:")
    print(f"{prefix}  有引用的文件: {files_with_occurrences}/{total_files}")
    print(f"{prefix}  occurs_in_module 总耗时: {time_occurs:.3f}s")
    print(f"{prefix}  get_pymodule 总耗时: {time_get_pymodule:.3f}s")
    print(f"{prefix}  change_module 总耗时: {time_change_module:.3f}s")


def profile_single_move(project, module_path, target_dir, scoped_resources):
    """对单个模块进行性能分析"""
    module_name = Path(module_path).stem
    print(f"\n模块: {module_name}.py")

    source = project.get_resource(module_path)
    target = project.get_resource(target_dir)
    mover = MoveModule(project, source)

    # 详细分析
    print("\n详细分析 get_changes:")
    analyze_get_changes_detail(project, mover, target, scoped_resources)

    # cProfile 分析
    print("\n完整 get_changes 调用（cProfile 分析）:")
    profiler = cProfile.Profile()
    profiler.enable()
    t0 = time.perf_counter()
    change = mover.get_changes(target, resources=scoped_resources)
    t1 = time.perf_counter()
    profiler.disable()

    print(f"  实际耗时: {t1-t0:.3f}s")

    s = io.StringIO()
    ps = pstats.Stats(profiler, stream=s).sort_stats('cumulative')
    ps.print_stats(20)
    print("\n  cProfile 结果（按累计时间排序，前20个）:")
    for line in s.getvalue().split('\n')[:30]:
        if line.strip():
            print(f"    {line}")


def main():
    # 修改为你的项目路径
    project_root = Path("/path/to/your/project")

    # 清理缓存
    ropedir = project_root / ".ropeproject"
    if ropedir.exists():
        shutil.rmtree(ropedir)

    project = Project(str(project_root))

    # 限制扫描范围
    app_folder = project.get_resource("backend/app")
    scoped_resources = get_python_files_in_folder(app_folder)
    print(f"扫描范围: {len(scoped_resources)} 个 Python 文件\n")

    module_path = "path/to/module.py"
    target_dir = "path/to/target"

    profile_single_move(project, module_path, target_dir, scoped_resources)
    project.close()


if __name__ == "__main__":
    main()
