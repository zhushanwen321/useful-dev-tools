#!/usr/bin/env python3
"""
Skill Memory Keeper - 总结脚本
用于分析记录并生成总结报告
"""

import json
import os
from datetime import datetime
from pathlib import Path
from collections import defaultdict, Counter


class SkillMemorySummarizer:
    """总结skill使用记录"""

    def __init__(self, base_path=None):
        if base_path is None:
            base_path = Path(__file__).parent.parent / "memory"
        self.base_path = Path(base_path)
        self.records_dir = self.base_path / "records"
        self.summaries_dir = self.base_path / "summaries"

    def generate_summary(self, skill_name):
        """
        为指定skill生成总结报告

        Args:
            skill_name: 技能名称

        Returns:
            总结报告内容和路径
        """
        # 读取所有记录
        skill_record_dir = self.records_dir / skill_name
        if not skill_record_dir.exists():
            return None, f"未找到 {skill_name} 的记录"

        # 收集所有原始记录
        records = []
        for record_file in skill_record_dir.glob("raw-*.json"):
            with open(record_file, 'r', encoding='utf-8') as f:
                records.append(json.load(f))

        if not records:
            return None, f"{skill_name} 没有记录"

        # 读取问题索引
        index_file = skill_record_dir / "issues.json"
        issues_index = None
        if index_file.exists():
            with open(index_file, 'r', encoding='utf-8') as f:
                issues_index = json.load(f)

        # 生成统计数据
        stats = self._calculate_stats(records, issues_index)

        # 生成改进建议
        recommendations = self._generate_recommendations(issues_index)

        # 生成报告
        report = self._format_report(skill_name, stats, recommendations, records)

        # 保存报告
        summary_dir = self.summaries_dir / skill_name
        summary_dir.mkdir(parents=True, exist_ok=True)

        date_str = datetime.now().strftime("%Y-%m-%d")
        report_file = summary_dir / f"summary-{date_str}.md"

        with open(report_file, 'w', encoding='utf-8') as f:
            f.write(report)

        return report, str(report_file)

    def _calculate_stats(self, records, issues_index):
        """计算统计数据"""
        total = len(records)

        # 按类型统计
        type_counter = Counter(r.get("issue_type", "其他") for r in records)

        # 按严重程度统计
        severity_counter = Counter(r.get("severity", "minor") for r in records)

        # 时间范围
        timestamps = [r.get("timestamp", "") for r in records if r.get("timestamp")]
        period_start = min(timestamps)[:10] if timestamps else "未知"
        period_end = max(timestamps)[:10] if timestamps else "未知"

        return {
            "total": total,
            "period_start": period_start,
            "period_end": period_end,
            "type_distribution": dict(type_counter),
            "severity_distribution": dict(severity_counter),
            "top_issues": issues_index.get("issues", [])[:10] if issues_index else []
        }

    def _generate_recommendations(self, issues_index):
        """基于问题生成改进建议"""
        if not issues_index:
            return []

        recommendations = []
        issues = issues_index.get("issues", [])

        # 按严重程度和频率分类问题
        critical_issues = [i for i in issues if i["severity"] == "critical"]
        frequent_issues = [i for i in issues if i["count"] >= 3]

        # 高优先级建议
        for issue in critical_issues:
            recommendations.append({
                "priority": "high",
                "issue": issue["summary"],
                "count": issue["count"],
                "suggestion": f"解决 {issue['summary']} 问题，已出现 {issue['count']} 次"
            })

        # 中优先级建议
        for issue in frequent_issues:
            if issue["severity"] != "critical":
                recommendations.append({
                    "priority": "medium",
                    "issue": issue["summary"],
                    "count": issue["count"],
                    "suggestion": f"优化 {issue['summary']} 体验，已出现 {issue['count']} 次"
                })

        return recommendations

    def _format_report(self, skill_name, stats, recommendations, records):
        """格式化报告"""
        date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        # 计算百分比
        type_dist = stats["type_distribution"]
        total = stats["total"]
        type_percent = {k: round(v / total * 100, 1) for k, v in type_dist.items()}

        # 构建报告
        report = f"""# {skill_name} 使用总结报告

**生成时间**: {date}
**统计周期**: {stats['period_start']} 至 {stats['period_end']}
**记录总数**: {total}

## 📊 统计概览

### 问题类型分布
"""

        # 类型分布表格
        type_order = ["错误", "性能", "体验", "功能", "其他"]
        for issue_type in type_order:
            if issue_type in type_dist:
                count = type_dist[issue_type]
                percent = type_percent[issue_type]
                report += f"| {issue_type} | {count} | {percent}% |\n"

        report += "\n### 严重程度分布\n"
        report += "| 严重程度 | 数量 |\n|----------|------|\n"
        for severity, count in stats.get("severity_distribution", {}).items():
            report += f"| {severity} | {count} |\n"

        # 高频问题
        if stats["top_issues"]:
            report += "\n## 🔥 高频问题 (Top 10)\n\n"
            report += "| 排名 | 问题描述 | 类型 | 出现次数 | 严重程度 | 状态 |\n"
            report += "|------|----------|------|----------|----------|------|\n"
            for i, issue in enumerate(stats["top_issues"][:10], 1):
                report += f"| {i} | {issue['summary'][:40]} | {issue['type']} | {issue['count']} | {issue['severity']} | {issue['status']} |\n"

        # 改进建议
        if recommendations:
            report += "\n## 💡 改进建议\n\n"

            high_priority = [r for r in recommendations if r["priority"] == "high"]
            medium_priority = [r for r in recommendations if r["priority"] == "medium"]

            if high_priority:
                report += "### 高优先级 (建议立即处理)\n\n"
                for rec in high_priority:
                    report += f"1. **{rec['issue']}**\n"
                    report += f"   - 出现次数: {rec['count']}\n"
                    report += f"   - 建议: {rec['suggestion']}\n\n"

            if medium_priority:
                report += "### 中优先级 (建议规划处理)\n\n"
                for rec in medium_priority:
                    report += f"1. **{rec['issue']}**\n"
                    report += f"   - 出现次数: {rec['count']}\n"
                    report += f"   - 建议: {rec['suggestion']}\n\n"

        # 详细记录列表
        report += "\n## 📝 详细记录列表\n\n"
        for record in sorted(records, key=lambda x: x.get("timestamp", ""), reverse=True):
            report += f"- **{record.get('timestamp', '')[:10]}** - {record.get('issue_type', '其他')}: {record.get('description', '')[:80]}\n"

        report += "\n---\n\n*本报告由 Skill Memory Keeper 自动生成*\n"

        return report

    def list_all_skills(self):
        """列出所有有记录的skills"""
        if not self.records_dir.exists():
            return []

        return [d.name for d in self.records_dir.iterdir() if d.is_dir()]


def main():
    """命令行接口"""
    import argparse

    parser = argparse.ArgumentParser(description="生成skill使用总结")
    parser.add_argument("--skill", help="技能名称（不指定则列出所有skills）")
    parser.add_argument("--list", action="store_true", help="列出所有有记录的skills")

    args = parser.parse_args()

    summarizer = SkillMemorySummarizer()

    if args.list:
        skills = summarizer.list_all_skills()
        print("有记录的skills:")
        for skill in skills:
            summary = summarizer.get_issues_summary(skill)
            if summary:
                print(f"  - {skill}: {len(summary.get('issues', []))} 个问题")
            else:
                print(f"  - {skill}")
        return

    if args.skill:
        report, path = summarizer.generate_summary(args.skill)
        if report:
            print(f"总结报告已生成: {path}")
            print("\n" + report)
        else:
            print(path)
    else:
        print("请指定 --skill 或使用 --list 查看所有skills")


if __name__ == "__main__":
    main()
