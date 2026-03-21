#!/usr/bin/env python3
"""
Skill Memory Keeper - 快速总结脚本
总结未总结过的记录，生成增量笔记
"""

import json
from datetime import datetime
from pathlib import Path
from collections import Counter
from record import SkillMemoryRecorder


class SkillMemoryQuickSummarizer:
    """快速总结未总结的记录"""

    def __init__(self, base_path=None):
        if base_path is None:
            base_path = Path(__file__).parent.parent / "memory"
        self.base_path = Path(base_path)
        self.recorder = SkillMemoryRecorder(base_path)

    def generate_quick_note(self, skill_name, dimension="user"):
        """
        为指定skill生成快速笔记

        Args:
            skill_name: 技能名称
            dimension: 维度

        Returns:
            笔记内容和路径
        """
        # 获取未总结的记录
        unsummarized = self.recorder.get_unsummarized_records(skill_name, dimension)

        if not unsummarized:
            return None, f"{skill_name} 没有未总结的记录"

        # 分析新增记录
        stats = self._analyze_records(unsummarized)

        # 生成笔记
        note = self._format_note(skill_name, dimension, stats, unsummarized)

        # 保存笔记
        notes_dir = self.base_path / dimension / "quick-notes" / skill_name
        notes_dir.mkdir(parents=True, exist_ok=True)

        date_str = datetime.now().strftime("%Y-%m-%d")
        note_file = notes_dir / f"note-{date_str}.md"

        with open(note_file, 'w', encoding='utf-8') as f:
            f.write(note)

        # 标记记录为已总结
        # 计算相对路径用于引用
        note_ref = f"../memory/{dimension}/quick-notes/{skill_name}/note-{date_str}.md"
        self.recorder.mark_as_summarized(unsummarized, note_ref)

        return note, str(note_file)

    def _analyze_records(self, records):
        """分析记录数据"""
        total = len(records)

        # 按类型统计
        type_counter = Counter(r.get("issue_type", "其他") for r in records)

        # 按严重程度统计
        severity_counter = Counter(r.get("severity", "minor") for r in records)

        # 收集问题详情
        issues = []
        for record in records:
            issues.append({
                "type": record.get("issue_type", "其他"),
                "description": record.get("description", ""),
                "severity": record.get("severity", "minor"),
                "timestamp": record.get("timestamp", ""),
                "file": Path(record.get("_file", "")).name
            })

        # 生成改进建议
        recommendations = self._generate_recommendations(records)

        return {
            "total": total,
            "type_distribution": dict(type_counter),
            "severity_distribution": dict(severity_counter),
            "issues": issues,
            "recommendations": recommendations
        }

    def _generate_recommendations(self, records):
        """基于记录生成改进建议"""
        # 简单的建议生成逻辑
        type_counter = Counter(r.get("issue_type", "其他") for r in records)

        recommendations = []

        # 如果有很多体验问题
        if type_counter.get("体验", 0) >= 2:
            recommendations.append({
                "priority": "high",
                "issue": "体验问题较多",
                "suggestion": "考虑优化输出格式或添加配置选项"
            })

        # 如果有错误
        if type_counter.get("错误", 0) >= 1:
            recommendations.append({
                "priority": "high",
                "issue": "存在错误",
                "suggestion": "需要修复相关bug"
            })

        return recommendations

    def _format_note(self, skill_name, dimension, stats, records):
        """格式化笔记"""
        date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        note = f"""# {skill_name} 快速笔记

**日期**: {date}
**维度**: {dimension}
**本次总结记录数**: {stats['total']}

## 新增问题

| 类型 | 问题描述 | 严重程度 | 记录文件 |
|------|----------|----------|----------|
"""

        # 添加问题表格
        for issue in stats["issues"]:
            desc = issue["description"][:40] + "..." if len(issue["description"]) > 40 else issue["description"]
            note += f"| {issue['type']} | {desc} | {issue['severity']} | {issue['file']} |\n"

        # 添加统计
        note += f"""
## 问题统计

### 类型分布
"""
        for issue_type, count in stats["type_distribution"].items():
            note += f"- {issue_type}: {count}\n"

        note += "\n### 严重程度分布\n"
        for severity, count in stats["severity_distribution"].items():
            note += f"- {severity}: {count}\n"

        # 添加改进建议
        if stats["recommendations"]:
            note += "\n## 改进建议\n\n"
            for rec in stats["recommendations"]:
                note += f"### {rec['priority'].upper()} - {rec['issue']}\n"
                note += f"{rec['suggestion']}\n\n"

        # 添加相关记录
        note += "\n## 相关记录\n\n"
        for record in records:
            timestamp = record.get("timestamp", "")[:19].replace("T", " ")
            note += f"- **{timestamp}**: {record.get('description', '')[:60]}\n"

        note += "\n---\n\n*本笔记由 Skill Memory Keeper 自动生成*\n"

        return note

    def generate_skill_md_link(self, skill_name, dimension, note_file):
        """生成SKILL.md中要添加的链接内容"""
        note_name = Path(note_file).name
        relative_path = f"../skill-memory-keeper/memory/{dimension}/quick-notes/{skill_name}/{note_name}"

        return f"""
---

## 经验总结

### 最新笔记
- [{Path(note_file).stem}]({relative_path})

### 问题统计
- 当前跟踪问题: 见最新笔记
"""

    def list_all_skills(self, dimension="user"):
        """列出所有有记录的skills"""
        return self.recorder.list_all_skills(dimension)


def main():
    """命令行接口"""
    import argparse

    parser = argparse.ArgumentParser(description="快速总结skill使用记录")
    parser.add_argument("--skill", required=True, help="技能名称")
    parser.add_argument("--dimension", default="user", choices=["user", "project"], help="维度")
    parser.add_argument("--list", action="store_true", help="列出所有有未总结记录的skills")

    args = parser.parse_args()

    summarizer = SkillMemoryQuickSummarizer()

    if args.list:
        skills = summarizer.list_all_skills(args.dimension)
        print(f"有未总结记录的skills ({args.dimension}):")
        for skill in skills:
            unsummarized = summarizer.recorder.get_unsummarized_records(skill, args.dimension)
            if unsummarized:
                print(f"  - {skill}: {len(unsummarized)} 条未总结")
        return

    note, path = summarizer.generate_quick_note(args.skill, args.dimension)
    if note:
        print(f"快速笔记已生成: {path}")
        print("\n" + note)

        # 生成SKILL.md链接
        link_content = summarizer.generate_skill_md_link(args.skill, args.dimension, path)
        print("\n=== 在SKILL.md中添加以下内容 ===\n")
        print(link_content)
    else:
        print(path)


if __name__ == "__main__":
    main()
