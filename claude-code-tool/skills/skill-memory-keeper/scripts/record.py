#!/usr/bin/env python3
"""
Skill Memory Keeper - 记录脚本
用于记录skill使用过程中的问题和反馈
支持user维度和project维度
"""

import json
from datetime import datetime
from pathlib import Path


class SkillMemoryRecorder:
    """记录skill使用中的问题和反馈"""

    def __init__(self, base_path=None):
        if base_path is None:
            base_path = Path(__file__).parent.parent / "memory"
        self.base_path = Path(base_path)

    def record_issue(self, skill_name, issue_data, dimension="user"):
        """
        记录一个skill问题

        Args:
            skill_name: 技能名称
            issue_data: 问题数据字典
            dimension: 维度，"user" 或 "project"

        Returns:
            记录文件路径
        """
        # 确保目录存在
        skill_record_dir = self.base_path / dimension / "records" / skill_name
        skill_record_dir.mkdir(parents=True, exist_ok=True)

        # 生成时间戳文件名
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        record_file = skill_record_dir / f"raw-{timestamp}.json"

        # 添加元数据
        issue_data["timestamp"] = datetime.now().isoformat()
        issue_data["skill_name"] = skill_name
        issue_data["dimension"] = dimension
        issue_data["summarized"] = False
        issue_data["summary_ref"] = None

        # 写入记录
        with open(record_file, 'w', encoding='utf-8') as f:
            json.dump(issue_data, f, ensure_ascii=False, indent=2)

        # 更新问题索引
        self._update_issue_index(skill_name, issue_data, dimension)

        return str(record_file)

    def _update_issue_index(self, skill_name, issue_data, dimension):
        """更新问题索引文件"""
        index_file = self.base_path / dimension / "records" / skill_name / "issues.json"

        # 读取现有索引或创建新的
        if index_file.exists():
            with open(index_file, 'r', encoding='utf-8') as f:
                index = json.load(f)
        else:
            index = {
                "skill_name": skill_name,
                "dimension": dimension,
                "last_updated": "",
                "issues": []
            }

        # 更新时间戳
        index["last_updated"] = datetime.now().isoformat()

        # 检查是否已有类似问题
        description = issue_data.get("description", "")
        existing_issue = None
        for issue in index["issues"]:
            if self._is_similar_issue(issue["summary"], description):
                existing_issue = issue
                break

        if existing_issue:
            # 更新现有问题的计数
            existing_issue["count"] += 1
            existing_issue["last_seen"] = datetime.now().strftime("%Y-%m-%d")
            # 如果严重程度更高，更新严重程度
            severity_order = {"critical": 3, "major": 2, "minor": 1}
            if severity_order.get(issue_data.get("severity", "minor"), 0) > \
               severity_order.get(existing_issue["severity"], 0):
                existing_issue["severity"] = issue_data.get("severity")
        else:
            # 添加新问题
            summary = description[:50] + "..." if len(description) > 50 else description
            index["issues"].append({
                "id": f"issue-{len(index['issues']) + 1:03d}",
                "type": issue_data.get("issue_type", "其他"),
                "count": 1,
                "first_seen": datetime.now().strftime("%Y-%m-%d"),
                "last_seen": datetime.now().strftime("%Y-%m-%d"),
                "severity": issue_data.get("severity", "minor"),
                "summary": summary,
                "status": "pending"
            })

        # 按计数和严重程度排序
        severity_order = {"critical": 3, "major": 2, "minor": 1}
        index["issues"].sort(
            key=lambda x: (x["count"], severity_order.get(x["severity"], 0)),
            reverse=True
        )

        # 写回索引文件
        with open(index_file, 'w', encoding='utf-8') as f:
            json.dump(index, f, ensure_ascii=False, indent=2)

    def _is_similar_issue(self, existing_summary, new_description):
        """判断是否为类似问题"""
        existing_words = set(existing_summary.lower().split())
        new_words = set(new_description.lower().split())

        if not existing_words or not new_words:
            return False

        intersection = existing_words & new_words
        union = existing_words | new_words

        return len(intersection) / len(union) > 0.3

    def get_unsummarized_records(self, skill_name, dimension="user"):
        """获取未总结的记录"""
        skill_record_dir = self.base_path / dimension / "records" / skill_name

        if not skill_record_dir.exists():
            return []

        unsummarized = []
        for record_file in skill_record_dir.glob("raw-*.json"):
            with open(record_file, 'r', encoding='utf-8') as f:
                record = json.load(f)
                if not record.get("summarized", False):
                    record["_file"] = str(record_file)
                    unsummarized.append(record)

        return sorted(unsummarized, key=lambda x: x.get("timestamp", ""))

    def get_all_records(self, skill_name, dimension="user"):
        """获取所有记录（包括已总结和未总结）"""
        skill_record_dir = self.base_path / dimension / "records" / skill_name

        if not skill_record_dir.exists():
            return []

        all_records = []
        for record_file in skill_record_dir.glob("raw-*.json"):
            with open(record_file, 'r', encoding='utf-8') as f:
                record = json.load(f)
                record["_file"] = str(record_file)
                all_records.append(record)

        return sorted(all_records, key=lambda x: x.get("timestamp", ""))

    def mark_as_summarized(self, records, summary_ref):
        """标记记录为已总结"""
        for record in records:
            file_path = record.get("_file")
            if not file_path:
                continue

            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)

            data["summarized"] = True
            data["summary_ref"] = summary_ref

            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)

    def delete_records(self, records):
        """删除已归档的记录"""
        for record in records:
            file_path = record.get("_file")
            if file_path and Path(file_path).exists():
                Path(file_path).unlink()

    def list_all_skills(self, dimension="user"):
        """列出所有有记录的skills"""
        records_dir = self.base_path / dimension / "records"
        if not records_dir.exists():
            return []

        return [d.name for d in records_dir.iterdir() if d.is_dir()]

    def get_issues_summary(self, skill_name, dimension="user"):
        """获取某个skill的问题摘要"""
        index_file = self.base_path / dimension / "records" / skill_name / "issues.json"

        if not index_file.exists():
            return None

        with open(index_file, 'r', encoding='utf-8') as f:
            return json.load(f)


def main():
    """命令行接口"""
    import argparse

    parser = argparse.ArgumentParser(description="记录skill问题")
    parser.add_argument("--skill", required=True, help="技能名称")
    parser.add_argument("--dimension", default="user", choices=["user", "project"], help="维度")
    parser.add_argument("--type", default="其他", help="问题类型")
    parser.add_argument("--severity", default="minor", help="严重程度")
    parser.add_argument("--description", required=True, help="问题描述")
    parser.add_argument("--feedback", help="用户反馈")

    args = parser.parse_args()

    recorder = SkillMemoryRecorder()

    issue_data = {
        "trigger_context": "命令行记录",
        "issue_type": args.type,
        "severity": args.severity,
        "description": args.description,
        "user_feedback": args.feedback or "",
        "context": {
            "command": f"record.py --skill {args.skill}",
            "input": "",
            "output": ""
        },
        "environment": {
            "model": "unknown",
            "platform": "cli"
        },
        "tags": []
    }

    record_file = recorder.record_issue(args.skill, issue_data, args.dimension)
    print(f"已记录到: {record_file}")
    print(f"维度: {args.dimension}")


if __name__ == "__main__":
    main()
