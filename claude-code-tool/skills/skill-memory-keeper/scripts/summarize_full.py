#!/usr/bin/env python3
"""
Skill Memory Keeper - 完整总结脚本
总结所有记录，归档并清理memory
"""

import json
from datetime import datetime
from pathlib import Path
from collections import Counter
from record import SkillMemoryRecorder


class SkillMemoryFullSummarizer:
    """完整总结所有记录并归档"""

    def __init__(self, base_path=None):
        if base_path is None:
            base_path = Path(__file__).parent.parent / "memory"
        self.base_path = Path(base_path)
        self.recorder = SkillMemoryRecorder(base_path)

    def generate_full_summary(self, skill_name, dimension="user"):
        """
        为指定skill生成完整总结

        Args:
            skill_name: 技能名称
            dimension: 维度

        Returns:
            总结报告内容和路径
        """
        # 获取所有记录
        all_records = self.recorder.get_all_records(skill_name, dimension)

        if not all_records:
            return None, f"{skill_name} 没有记录"

        # 分析所有记录
        stats = self._analyze_all_records(all_records)

        # 生成完整报告
        summary = self._format_full_summary(skill_name, dimension, stats, all_records)

        # 保存归档
        archive_dir = self.base_path / dimension / "archive" / skill_name
        archive_dir.mkdir(parents=True, exist_ok=True)

        date_str = datetime.now().strftime("%Y-%m-%d")
        archive_file = archive_dir / f"summary-{date_str}.md"

        with open(archive_file, 'w', encoding='utf-8') as f:
            f.write(summary)

        return summary, str(archive_file)

    def _analyze_all_records(self, records):
        """分析所有记录数据"""
        total = len(records)

        # 按类型统计
        type_counter = Counter(r.get("issue_type", "其他") for r in records)

        # 按严重程度统计
        severity_counter = Counter(r.get("severity", "minor") for r in records)

        # 时间范围
        timestamps = [r.get("timestamp", "") for r in records if r.get("timestamp")]
        period_start = min(timestamps)[:10] if timestamps else "未知"
        period_end = max(timestamps)[:10] if timestamps else "未知"

        # 获取问题索引
        issues_summary = self.recorder.get_issues_summary(records[0].get("skill_name", ""), records[0].get("dimension", "user"))

        # 生成核心改进建议
        key_improvements = self._generate_key_improvements(records, issues_summary)

        return {
            "total": total,
            "period_start": period_start,
            "period_end": period_end,
            "type_distribution": dict(type_counter),
            "severity_distribution": dict(severity_counter),
            "issues_summary": issues_summary,
            "key_improvements": key_improvements
        }

    def _generate_key_improvements(self, records, issues_summary):
        """生成核心改进建议（用于更新SKILL.md）"""
        improvements = []

        if not issues_summary:
            return improvements

        # 获取高频问题
        top_issues = issues_summary.get("issues", [])[:5]

        for issue in top_issues:
            if issue["count"] >= 3 or issue["severity"] == "critical":
                improvements.append({
                    "issue": issue["summary"],
                    "count": issue["count"],
                    "severity": issue["severity"],
                    "suggestion": self._issue_to_suggestion(issue)
                })

        return improvements

    def _issue_to_suggestion(self, issue):
        """将问题转换为改进建议"""
        issue_type = issue.get("type", "")
        summary = issue.get("summary", "")

        # 根据问题类型生成建议
        if issue_type == "体验":
            return f"优化用户体验：{summary}。建议添加配置选项或改进输出格式。"
        elif issue_type == "错误":
            return f"修复错误：{summary}。需要检查相关代码逻辑。"
        elif issue_type == "性能":
            return f"优化性能：{summary}。建议分析性能瓶颈并优化。"
        elif issue_type == "功能":
            return f"增强功能：{summary}。可能需要添加新功能或改进现有功能。"
        else:
            return f"改进：{summary}"

    def _format_full_summary(self, skill_name, dimension, stats, records):
        """格式化完整总结"""
        date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        summary = f"""# {skill_name} 完整总结报告

**归档日期**: {date}
**维度**: {dimension}
**统计周期**: {stats['period_start']} 至 {stats['period_end']}
**总记录数**: {stats['total']}

## 核心改进

基于本次总结，建议对 SKILL.md 进行以下更新：

"""

        # 添加核心改进
        if stats["key_improvements"]:
            for i, imp in enumerate(stats["key_improvements"], 1):
                summary += f"{i}. **{imp['issue']}**\n"
                summary += f"   - 出现次数: {imp['count']}\n"
                summary += f"   - 严重程度: {imp['severity']}\n"
                summary += f"   - 建议: {imp['suggestion']}\n\n"
        else:
            summary += "本次总结未发现需要立即改进的问题。\n\n"

        # 添加问题统计
        summary += "## 问题统计\n\n"

        summary += "### 类型分布\n"
        total = stats['total']
        for issue_type, count in stats["type_distribution"].items():
            percent = round(count / total * 100, 1) if total > 0 else 0
            summary += f"- {issue_type}: {count} ({percent}%)\n"

        summary += "\n### 严重程度分布\n"
        for severity, count in stats["severity_distribution"].items():
            summary += f"- {severity}: {count}\n"

        # 添加问题详情
        if stats["issues_summary"] and stats["issues_summary"].get("issues"):
            summary += "\n## 问题详情\n\n"
            summary += "| ID | 问题描述 | 类型 | 次数 | 严重程度 | 状态 |\n"
            summary += "|----|----------|------|------|----------|------|\n"

            for issue in stats["issues_summary"]["issues"]:
                summary += f"| {issue['id']} | {issue['summary'][:40]} | {issue['type']} | {issue['count']} | {issue['severity']} | {issue['status']} |\n"

        # 添加记录列表
        summary += "\n## 所有记录\n\n"
        for record in sorted(records, key=lambda x: x.get("timestamp", ""), reverse=True):
            timestamp = record.get("timestamp", "")[:19].replace("T", " ")
            summary += f"- **{timestamp}** [{record.get('issue_type', '其他')}] {record.get('description', '')[:80]}\n"

        summary += "\n---\n\n*本报告由 Skill Memory Keeper 自动生成*\n"
        summary += f"*原始记录已清理，共 {stats['total']} 条*\n"

        return summary

    def generate_skill_md_update(self, skill_name, dimension, stats):
        """生成要应用到SKILL.md的更新内容"""
        update = "\n---\n\n## 经验总结\n\n"

        # 添加核心改进点
        if stats["key_improvements"]:
            update += "### 核心改进\n\n"
            for imp in stats["key_improvements"]:
                update += f"- **{imp['issue']}**: {imp['suggestion']}\n"
            update += "\n"

        # 添加归档链接
        date_str = datetime.now().strftime("%Y-%m-%d")
        archive_path = f"../skill-memory-keeper/memory/{dimension}/archive/{skill_name}/summary-{date_str}.md"

        update += "### 历史归档\n\n"
        update += f"- [{date_str} 完整总结]({archive_path})\n"

        # 添加问题统计
        if stats["issues_summary"]:
            total_issues = len(stats["issues_summary"].get("issues", []))
            pending = sum(1 for i in stats["issues_summary"].get("issues", []) if i["status"] == "pending")
            update += f"\n### 问题统计\n"
            update += f"- 当前跟踪问题: {total_issues} 个\n"
            update += f"- 待处理问题: {pending} 个\n"

        return update

    def cleanup_records(self, skill_name, dimension="user"):
        """清理已归档的记录"""
        records = self.recorder.get_all_records(skill_name, dimension)
        deleted_count = self.recorder.delete_records(records)
        return len(records)


def main():
    """命令行接口"""
    import argparse

    parser = argparse.ArgumentParser(description="完整总结skill使用记录并归档")
    parser.add_argument("--skill", required=True, help="技能名称")
    parser.add_argument("--dimension", default="user", choices=["user", "project"], help="维度")
    parser.add_argument("--list", action="store_true", help="列出所有有记录的skills")

    args = parser.parse_args()

    summarizer = SkillMemoryFullSummarizer()

    if args.list:
        skills = summarizer.recorder.list_all_skills(args.dimension)
        print(f"有记录的skills ({args.dimension}):")
        for skill in skills:
            records = summarizer.recorder.get_all_records(skill, args.dimension)
            print(f"  - {skill}: {len(records)} 条记录")
        return

    # 生成完整总结
    summary, archive_path = summarizer.generate_full_summary(args.skill, args.dimension)

    if summary:
        print(f"完整总结已生成: {archive_path}")
        print("\n" + summary)

        # 生成SKILL.md更新内容
        # 需要先获取stats
        all_records = summarizer.recorder.get_all_records(args.skill, args.dimension)
        stats = summarizer._analyze_all_records(all_records)
        update_content = summarizer.generate_skill_md_update(args.skill, args.dimension, stats)

        print("\n=== 建议在SKILL.md中添加以下内容 ===\n")
        print(update_content)

        # 询问是否清理记录
        print(f"\n当前有 {len(all_records)} 条原始记录")
        print("完整总结后可以安全删除这些记录（已归档）")
    else:
        print(summary)


if __name__ == "__main__":
    main()
