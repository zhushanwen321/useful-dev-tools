"""
使用 rope 将 completeness providers 移动到 domain/supporting 目录

只移动 provider 文件，不移动 __init__.py（因为目标目录已存在）

使用方法:
    cd /Users/zhushanwen/Code/stock-data-crawler
    python .refactor/20260316-110500-move-providers-to-supporting.py --dry-run
    python .refactor/20260316-110500-move-providers-to-supporting.py
"""

import sys
from pathlib import Path

# 使用本地修复版的 rope
ROPE_LOCAL = "/Users/zhushanwen/GitApp/rope"
sys.path.insert(0, ROPE_LOCAL)

from rope.base.project import Project
from rope.refactor.move import MoveModule


def main():
    project_path = Path("/Users/zhushanwen/Code/stock-data-crawler")
    project = Project(project_path)

    # 定义文件移动映射: 源文件路径 -> 目标目录路径（不包含 __init__.py）
    moves = {
        # Collection providers -> backend/app/domain/supporting/collection/
        "backend/app/infra/completeness/providers/collection/daily_indicator_provider.py":
            "backend/app/domain/supporting/collection",
        "backend/app/infra/completeness/providers/collection/daily_trading_provider.py":
            "backend/app/domain/supporting/collection",
        "backend/app/infra/completeness/providers/collection/financial_reports_provider.py":
            "backend/app/domain/supporting/collection",
        "backend/app/infra/completeness/providers/collection/industry_provider.py":
            "backend/app/domain/supporting/collection",
        "backend/app/infra/completeness/providers/collection/margin_detail_provider.py":
            "backend/app/domain/supporting/collection",
        "backend/app/infra/completeness/providers/collection/money_flow_provider.py":
            "backend/app/domain/supporting/collection",
        "backend/app/infra/completeness/providers/collection/north_money_hold_provider.py":
            "backend/app/domain/supporting/collection",
        "backend/app/infra/completeness/providers/collection/stock_info_provider.py":
            "backend/app/domain/supporting/collection",
        "backend/app/infra/completeness/providers/collection/sw_index_provider.py":
            "backend/app/domain/supporting/collection",
        "backend/app/infra/completeness/providers/collection/trade_calendar_provider.py":
            "backend/app/domain/supporting/collection",

        # Calculation providers -> backend/app/domain/supporting/calculation/
        "backend/app/infra/completeness/providers/calculation/financial_factor_provider.py":
            "backend/app/domain/supporting/calculation",
        "backend/app/infra/completeness/providers/calculation/industry_valuation_provider.py":
            "backend/app/domain/supporting/calculation",
        "backend/app/infra/completeness/providers/calculation/market_sentiment_provider.py":
            "backend/app/domain/supporting/calculation",
        "backend/app/infra/completeness/providers/calculation/market_valuation_provider.py":
            "backend/app/domain/supporting/calculation",
        "backend/app/infra/completeness/providers/calculation/technical_indicator_provider.py":
            "backend/app/domain/supporting/calculation",
    }

    dry_run = "--dry-run" in sys.argv

    print(f"{'[预览模式] ' if dry_run else ''}开始移动 {len(moves)} 个 provider 文件...")
    print("-" * 60)

    # 检查所有源文件是否存在
    for src in moves.keys():
        src_path = project_path / src
        if not src_path.exists():
            print(f"⚠️  源文件不存在: {src}")
            return

    # 检查所有目标目录是否存在且是包
    for dest_dir in set(moves.values()):
        dest_path = project_path / dest_dir
        if not dest_path.exists():
            print(f"⚠️  目标目录不存在: {dest_dir}")
            return
        init_py = dest_path / "__init__.py"
        if not init_py.exists():
            print(f"⚠️  目标不是包: {dest_dir} (缺少 __init__.py)")
            return

    # 执行移动
    for i, (src, dest_dir) in enumerate(moves.items(), 1):
        print(f"\n[{i}/{len(moves)}] {Path(src).name}")
        print(f"  源: {src}")
        print(f"  目标目录: {dest_dir}")

        try:
            resource = project.get_resource(src)
            mover = MoveModule(project, resource)

            # 获取目标目录资源
            dest_resource = project.get_resource(dest_dir)

            # 使用 get_changes 获取变更，然后执行
            changes = mover.get_changes(dest_resource)

            if dry_run:
                changed = list(changes.get_changed_resources())
                print(f"  ✓ 预览完成 (将修改 {len(changed)} 个文件)")
                for change in changed[:3]:
                    print(f"      - {change.path}")
                if len(changed) > 3:
                    print(f"      - ... 还有 {len(changed) - 3} 个文件")
            else:
                changes.do()
                changed = list(changes.get_changed_resources())
                print(f"  ✓ 移动完成 (修改了 {len(changed)} 个文件)")

        except Exception as e:
            print(f"  ✗ 失败: {e}")
            import traceback
            traceback.print_exc()
            if not dry_run:
                print("  提示: 使用 --dry-run 查看预览")
                return

    print("\n" + "=" * 60)
    if dry_run:
        print("预览完成。移除 --dry-run 参数以执行实际移动。")
    else:
        print("所有文件移动完成！")
        print("\n后续步骤:")
        print("1. 检查导入是否正确更新")
        print("2. 运行测试: cd backend && uv run pytest")
        print("3. 如有问题，使用 git checkout 撤销")


if __name__ == "__main__":
    main()
