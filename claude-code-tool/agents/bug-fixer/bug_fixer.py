#!/usr/bin/env python3
"""
Bug Fixer - Bug 修复知识库管理工具

用于记录和管理代码修复问题，帮助构建问题修复模式库。
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Optional


class BugFixer:
    """Bug 修复知识库管理器"""

    # 有效的严重程度值
    VALID_SEVERITIES = {"critical", "major", "minor"}

    # 索引文件的默认结构
    DEFAULT_INDEX_STRUCTURE = {
        "category": "",
        "language": "",
        "last_updated": "",
        "problems": [],
        "tag_counts": {},
        "severity_counts": {"critical": 0, "major": 0, "minor": 0}
    }

    # 统计文件的默认结构
    DEFAULT_STATS_STRUCTURE = {
        "total_problems": 0,
        "by_language": {},
        "by_category": {},
        "by_severity": {"critical": 0, "major": 0, "minor": 0},
        "last_updated": ""
    }

    def __init__(self, library_path: Optional[str] = None, dry_run: bool = False):
        """
        初始化 BugFixer

        Args:
            library_path: 知识库路径，默认为 ~/.claude/bug-fix-library/
            dry_run: 预览模式，不实际写入文件
        """
        if library_path is None:
            library_path = os.path.expanduser("~/.claude/bug-fix-library/")
        self.library_path = Path(library_path)
        self.dry_run = dry_run

        if not dry_run:
            self.library_path.mkdir(parents=True, exist_ok=True)

        # 全局统计文件
        self.stats_file = self.library_path / "stats.json"
        self._init_stats()

    def _init_stats(self):
        """初始化全局统计文件"""
        if self.dry_run:
            return
        if not self.stats_file.exists():
            self._save_json(self.stats_file, self.DEFAULT_STATS_STRUCTURE.copy())

    def _load_json(self, path: Path) -> dict:
        """加载 JSON 文件"""
        if path.exists():
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except json.JSONDecodeError as e:
                print(f"警告: JSON 文件格式错误 {path}: {e}", file=sys.stderr)
                return {}
        return {}

    def _save_json(self, path: Path, data: dict):
        """保存 JSON 文件"""
        if self.dry_run:
            print(f"[DRY-RUN] 将保存到: {path}")
            return
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def _ensure_index_format(self, index: dict, category: str = "", language: str = "") -> dict:
        """
        确保索引文件格式正确，自动修复缺失的字段

        Args:
            index: 原始索引数据
            category: 分类名称
            language: 语言名称

        Returns:
            修复后的索引数据
        """
        result = self.DEFAULT_INDEX_STRUCTURE.copy()

        # 复制现有数据
        for key in result:
            if key in index:
                result[key] = index[key]

        # 确保必要字段存在
        if category and not result.get("category"):
            result["category"] = category
        if language and not result.get("language"):
            result["language"] = language

        # 确保 problems 是列表
        if not isinstance(result.get("problems"), list):
            result["problems"] = []

        # 确保 tag_counts 是字典
        if not isinstance(result.get("tag_counts"), dict):
            result["tag_counts"] = {}

        # 确保 severity_counts 结构正确
        if not isinstance(result.get("severity_counts"), dict):
            result["severity_counts"] = {"critical": 0, "major": 0, "minor": 0}
        else:
            for sev in ["critical", "major", "minor"]:
                if sev not in result["severity_counts"] or not isinstance(result["severity_counts"].get(sev), int):
                    result["severity_counts"][sev] = 0

        return result

    def _ensure_stats_format(self, stats: dict) -> dict:
        """
        确保统计文件格式正确

        Args:
            stats: 原始统计数据

        Returns:
            修复后的统计数据
        """
        result = self.DEFAULT_STATS_STRUCTURE.copy()

        for key in result:
            if key in stats:
                result[key] = stats[key]

        # 确保数值字段是整数
        if not isinstance(result.get("total_problems"), int):
            result["total_problems"] = 0

        # 确保 by_language 是简单整数计数的字典
        if not isinstance(result.get("by_language"), dict):
            result["by_language"] = {}
        else:
            # 修复可能的复杂对象格式
            fixed = {}
            for lang, value in result["by_language"].items():
                if isinstance(value, dict):
                    fixed[lang] = value.get("count", 0)
                elif isinstance(value, int):
                    fixed[lang] = value
                else:
                    fixed[lang] = 0
            result["by_language"] = fixed

        # 同样处理 by_category
        if not isinstance(result.get("by_category"), dict):
            result["by_category"] = {}
        else:
            fixed = {}
            for cat, value in result["by_category"].items():
                if isinstance(value, dict):
                    fixed[cat] = value.get("count", 0)
                elif isinstance(value, int):
                    fixed[cat] = value
                else:
                    fixed[cat] = 0
            result["by_category"] = fixed

        # 确保 severity_counts 正确
        if not isinstance(result.get("by_severity"), dict):
            result["by_severity"] = {"critical": 0, "major": 0, "minor": 0}
        else:
            for sev in ["critical", "major", "minor"]:
                if sev not in result["by_severity"] or not isinstance(result["by_severity"].get(sev), int):
                    result["by_severity"][sev] = 0

        return result

    def _get_category_path(self, language: str, category: str) -> Path:
        """获取分类目录路径"""
        language = language.lower()
        category = category.lower().replace(" ", "-")

        path = self.library_path / language / category
        if not self.dry_run:
            path.mkdir(parents=True, exist_ok=True)
        return path

    def _get_index_path(self, category_path: Path) -> Path:
        """获取索引文件路径"""
        return category_path / "index.json"

    def _get_global_index_path(self, language: str) -> Path:
        """获取语言全局索引文件路径"""
        return self.library_path / language.lower() / "global_index.json"

    def _get_next_problem_id(self, category_path: Path) -> str:
        """获取下一个问题 ID"""
        if self.dry_run:
            return "000"

        existing_ids = []
        for f in category_path.glob("*.md"):
            if f.name != "index.md":
                match = re.match(r"^(\d+)-", f.name)
                if match:
                    existing_ids.append(int(match.group(1)))

        if existing_ids:
            next_id = max(existing_ids) + 1
        else:
            next_id = 1

        return f"{next_id:03d}"

    def _extract_error_signature(self, error_message: str) -> str:
        """提取错误签名（用于匹配类似问题）"""
        signature = error_message

        signature = signature.replace("'", '"')
        signature = re.sub(r'/[^\s"\'`]+/([^\s"\'`]+\.(py|js|ts|jsx|tsx))', '<FILE>', signature)
        signature = re.sub(r'line \d+', 'line N', signature)
        signature = re.sub(r':\d+', ':N', signature)
        signature = re.sub(r'"[^"]+"', '"<value>"', signature)
        signature = re.sub(r'\b\d{3,}\b', '<ID>', signature)

        return signature[:200].strip()

    def _calculate_similarity(self, problem1: dict, problem2: dict) -> float:
        """计算两个问题的相似度（0-100）"""
        score = 0.0

        sig1 = problem1.get("error_signature", "")
        sig2 = problem2.get("error_signature", "")
        if sig1 and sig2:
            if sig1 == sig2:
                score += 60
            else:
                common = set(sig1.split()) & set(sig2.split())
                total = set(sig1.split()) | set(sig2.split())
                if total:
                    score += 60 * (len(common) / len(total))

        tags1 = set(problem1.get("tags", []))
        tags2 = set(problem2.get("tags", []))
        if tags1 or tags2:
            intersection = tags1 & tags2
            union = tags1 | tags2
            if union:
                score += 25 * (len(intersection) / len(union))

        if (problem1.get("language") == problem2.get("language") and
            problem1.get("frameworks") == problem2.get("frameworks")):
            score += 15

        return min(score, 100.0)

    def _validate_input(self, **kwargs) -> list:
        """
        验证输入参数

        Returns:
            错误消息列表，空列表表示验证通过
        """
        errors = []

        required_fields = ["language", "frameworks", "title", "description",
                          "error_message", "root_cause", "fix_method"]

        for field in required_fields:
            if not kwargs.get(field):
                errors.append(f"缺少必填字段: {field}")

        severity = kwargs.get("severity", "major")
        if severity not in self.VALID_SEVERITIES:
            errors.append(f"无效的严重程度: {severity}，有效值: {self.VALID_SEVERITIES}")

        return errors

    def record_problem(
        self,
        language: str,
        frameworks: str,
        title: str,
        description: str,
        error_message: str,
        root_cause: str,
        fix_method: str,
        severity: str = "major",
        tags: Optional[list] = None,
        before_code: Optional[str] = None,
        after_code: Optional[str] = None,
        related_files: Optional[list] = None,
        category: Optional[str] = None,
        force: bool = False,
    ) -> dict:
        """
        记录一个问题

        Args:
            language: 编程语言
            frameworks: 框架/库
            title: 问题标题
            description: 问题描述
            error_message: 错误信息
            root_cause: 根本原因
            fix_method: 修复方法
            severity: 严重程度 (critical/major/minor)
            tags: 标签列表
            before_code: 修复前代码
            after_code: 修复后代码
            related_files: 相关文件路径列表
            category: 分类
            force: 强制创建，跳过去重检查

        Returns:
            操作结果字典
        """
        # 验证输入
        errors = self._validate_input(
            language=language, frameworks=frameworks, title=title,
            description=description, error_message=error_message,
            root_cause=root_cause, fix_method=fix_method, severity=severity
        )
        if errors:
            return {
                "action": "error",
                "errors": errors,
                "message": "输入验证失败: " + "; ".join(errors)
            }

        # 规范化 severity
        severity = severity.lower()
        if severity not in self.VALID_SEVERITIES:
            severity = "major"

        # 默认从 tags 中提取 category
        if category is None and tags:
            category = tags[0] if tags else "general"
        elif category is None:
            category = "general"

        # 提取错误签名
        error_signature = self._extract_error_signature(error_message)

        # 构建问题数据
        problem_data = {
            "language": language,
            "frameworks": frameworks,
            "title": title,
            "description": description,
            "error_message": error_message,
            "error_signature": error_signature,
            "root_cause": root_cause,
            "fix_method": fix_method,
            "severity": severity,
            "tags": tags or [],
            "before_code": before_code,
            "after_code": after_code,
            "related_files": related_files or [],
        }

        # 获取分类路径
        category_path = self._get_category_path(language, category)

        # 搜索类似问题（除非强制创建）
        if not force:
            similar_problems = self._find_similar_problems(category_path, problem_data)

            if similar_problems:
                return {
                    "action": "confirm_update",
                    "similar_problems": similar_problems,
                    "new_problem": problem_data,
                    "message": f"发现 {len(similar_problems)} 个类似问题，是否补充到现有记录？使用 --force 强制创建新记录。"
                }

        # 没有类似问题或强制创建
        return self._create_new_problem(category_path, category, problem_data)

    def _find_similar_problems(self, category_path: Path, problem_data: dict, threshold: float = 70.0) -> list:
        """查找类似问题"""
        index_path = self._get_index_path(category_path)
        if not index_path.exists():
            return []

        index = self._load_json(index_path)
        index = self._ensure_index_format(index)

        similar = []

        for existing_problem in index.get("problems", []):
            similarity = self._calculate_similarity(problem_data, existing_problem)
            if similarity >= threshold:
                similar.append({
                    **existing_problem,
                    "similarity": similarity,
                    "file_path": str(category_path / existing_problem["file"])
                })

        similar.sort(key=lambda x: x["similarity"], reverse=True)
        return similar

    def _create_new_problem(self, category_path: Path, category: str, problem_data: dict) -> dict:
        """创建新问题记录"""
        problem_id = self._get_next_problem_id(category_path)

        # 生成文件名
        title_slug = re.sub(r'[^\w\s-]', '', problem_data["title"])
        title_slug = re.sub(r'[-\s]+', '-', title_slug).lower().strip('-')
        filename = f"{problem_id}-{title_slug}.md"
        file_path = category_path / filename

        # 生成问题内容
        content = self._generate_problem_content(problem_data, problem_id)

        if self.dry_run:
            print(f"[DRY-RUN] 将创建文件: {file_path}")
            print(f"[DRY-RUN] 文件内容预览:")
            print("-" * 40)
            print(content[:500] + "..." if len(content) > 500 else content)
            print("-" * 40)
            return {
                "action": "dry_run",
                "file_path": str(file_path),
                "problem_id": problem_id,
                "message": f"[预览] 将创建: {file_path.relative_to(self.library_path)}"
            }

        # 写入文件
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(content)

        # 更新索引
        self._update_index(category_path, category, problem_data, filename, problem_id)

        # 更新全局统计
        self._update_global_stats(problem_data, is_new=True)

        return {
            "action": "created",
            "file_path": str(file_path),
            "problem_id": problem_id,
            "message": f"创建新记录: {file_path.relative_to(self.library_path)}"
        }

    def _generate_problem_content(self, problem_data: dict, problem_id: str) -> str:
        """生成问题记录的 Markdown 内容"""
        today = datetime.now().strftime("%Y-%m-%d")

        content = f"""# {problem_data['title']}

**记录时间**: {today}
**严重程度**: {problem_data['severity']}

## 基本信息

**编程语言**: {problem_data['language']}
**框架/库**: {problem_data['frameworks']}
**标签**: {', '.join(problem_data.get('tags', []))}

## 问题描述

{problem_data['description']}

## 错误信息

```
{problem_data['error_message']}
```

## 根本原因

{problem_data['root_cause']}

## 修复方法

{problem_data['fix_method']}
"""

        if problem_data.get('before_code') or problem_data.get('after_code'):
            content += "\n## 代码示例\n\n"
            if problem_data.get('before_code'):
                content += f"""**修复前**:
```{problem_data['language'].lower()}
{problem_data['before_code']}
```

"""
            if problem_data.get('after_code'):
                content += f"""**修复后**:
```{problem_data['language'].lower()}
{problem_data['after_code']}
```

"""

        if problem_data.get('related_files'):
            content += "## 相关文件\n\n"
            for file in problem_data['related_files']:
                content += f"- `{file}`\n"
            content += "\n"

        content += f"""## 统计信息

- **首次发现**: {today}
- **最后出现**: {today}
- **出现次数**: 1

## 变更历史

- {today}: 初始记录
"""
        return content

    def _update_index(
        self,
        category_path: Path,
        category: str,
        problem_data: dict,
        filename: str,
        problem_id: str
    ):
        """更新分类索引"""
        index_path = self._get_index_path(category_path)

        # 加载并修复现有索引
        index = self._load_json(index_path) if index_path.exists() else {}
        index = self._ensure_index_format(index, category, problem_data["language"])

        # 添加新问题
        problem_entry = {
            "id": problem_id,
            "title": problem_data["title"],
            "file": filename,
            "severity": problem_data["severity"],
            "tags": problem_data.get("tags", []),
            "error_signature": problem_data.get("error_signature", ""),
            "occurrence_count": 1,
            "first_seen": datetime.now().strftime("%Y-%m-%d"),
            "last_seen": datetime.now().strftime("%Y-%m-%d")
        }
        index["problems"].append(problem_entry)

        # 更新标签计数
        for tag in problem_data.get("tags", []):
            index["tag_counts"][tag] = index["tag_counts"].get(tag, 0) + 1

        # 更新严重程度计数
        severity = problem_data["severity"]
        if severity in index["severity_counts"]:
            index["severity_counts"][severity] += 1

        index["last_updated"] = datetime.now().isoformat()

        self._save_json(index_path, index)
        self._update_global_index(problem_data["language"], problem_entry)

    def _update_index_after_increment(self, category_path: Path, problem_id: str, new_count: int):
        """在问题计数增加后更新索引"""
        index_path = self._get_index_path(category_path)
        if not index_path.exists():
            return

        index = self._load_json(index_path)
        index = self._ensure_index_format(index)

        for problem in index.get("problems", []):
            if problem["id"] == problem_id:
                problem["occurrence_count"] = new_count
                problem["last_seen"] = datetime.now().strftime("%Y-%m-%d")
                break

        index["last_updated"] = datetime.now().isoformat()
        self._save_json(index_path, index)

    def _update_global_index(self, language: str, problem_entry: dict):
        """更新语言全局索引"""
        global_index_path = self._get_global_index_path(language)

        if global_index_path.exists():
            global_index = self._load_json(global_index_path)
            if "problems" not in global_index:
                global_index["problems"] = []
            if "by_category" not in global_index:
                global_index["by_category"] = {}
        else:
            global_index = {
                "language": language,
                "last_updated": datetime.now().isoformat(),
                "problems": [],
                "by_category": {}
            }

        global_index["problems"].append({
            "id": problem_entry["id"],
            "title": problem_entry["title"],
            "file": problem_entry["file"],
            "category": problem_entry.get("category", "general")
        })

        global_index["last_updated"] = datetime.now().isoformat()
        self._save_json(global_index_path, global_index)

    def _update_global_stats(self, problem_data: dict, is_new: bool):
        """更新全局统计"""
        stats = self._load_json(self.stats_file)
        stats = self._ensure_stats_format(stats)

        if is_new:
            stats["total_problems"] += 1

        lang = problem_data["language"]
        stats["by_language"][lang] = stats["by_language"].get(lang, 0) + (1 if is_new else 0)

        for tag in problem_data.get("tags", []):
            stats["by_category"][tag] = stats["by_category"].get(tag, 0) + (1 if is_new else 0)

        severity = problem_data["severity"]
        if severity in stats["by_severity"]:
            stats["by_severity"][severity] += 1

        stats["last_updated"] = datetime.now().isoformat()
        self._save_json(self.stats_file, stats)

    def search_problems(
        self,
        language: Optional[str] = None,
        category: Optional[str] = None,
        tags: Optional[list] = None,
        severity: Optional[str] = None,
        keyword: Optional[str] = None
    ) -> list:
        """搜索问题"""
        results = []

        if language:
            search_roots = [self.library_path / language.lower()]
        else:
            search_roots = [self.library_path / d for d in self.library_path.iterdir()
                          if d.is_dir() and d.name not in ["__pycache__"]]

        for root in search_roots:
            if not root.exists():
                continue

            if category:
                search_dirs = [root / category.lower().replace(" ", "-")]
            else:
                search_dirs = [d for d in root.iterdir() if d.is_dir()]

            for category_dir in search_dirs:
                if not category_dir.exists():
                    continue

                index_path = category_dir / "index.json"
                if not index_path.exists():
                    continue

                index = self._load_json(index_path)
                index = self._ensure_index_format(index)

                for problem in index.get("problems", []):
                    if severity and problem.get("severity") != severity:
                        continue

                    if tags:
                        if not any(tag in problem.get("tags", []) for tag in tags):
                            continue

                    if keyword:
                        title = problem.get("title", "").lower()
                        if keyword.lower() not in title:
                            continue

                    results.append({
                        **problem,
                        "language": index.get("language"),
                        "category": index.get("category"),
                        "file_path": str(category_dir / problem["file"])
                    })

        return results

    def get_stats(self) -> dict:
        """获取全局统计信息"""
        stats = self._load_json(self.stats_file)
        return self._ensure_stats_format(stats)

    def repair_indexes(self) -> dict:
        """
        修复所有索引文件

        Returns:
            修复报告
        """
        if self.dry_run:
            return {"action": "dry_run", "message": "[预览] 将修复索引文件"}

        repaired = []
        errors = []

        # 修复统计文件
        stats = self._load_json(self.stats_file)
        fixed_stats = self._ensure_stats_format(stats)
        if fixed_stats != stats:
            self._save_json(self.stats_file, fixed_stats)
            repaired.append("stats.json")

        # 遍历所有语言目录
        for lang_dir in self.library_path.iterdir():
            if not lang_dir.is_dir() or lang_dir.name.startswith('.'):
                continue

            # 修复分类索引
            for category_dir in lang_dir.iterdir():
                if not category_dir.is_dir():
                    continue

                index_path = category_dir / "index.json"
                if index_path.exists():
                    index = self._load_json(index_path)
                    fixed_index = self._ensure_index_format(
                        index,
                        category_dir.name,
                        lang_dir.name
                    )
                    if fixed_index != index:
                        self._save_json(index_path, fixed_index)
                        repaired.append(f"{lang_dir.name}/{category_dir.name}/index.json")

        return {
            "action": "repaired",
            "repaired_files": repaired,
            "errors": errors,
            "message": f"修复了 {len(repaired)} 个索引文件"
        }


def main():
    """CLI 主函数"""
    parser = argparse.ArgumentParser(
        description="Bug 修复知识库管理工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 记录一个新问题
  %(prog)s record \\
    --language "TypeScript" \\
    --frameworks "Vue 3" \\
    --title "Computed 属性空值错误" \\
    --description "在 computed 中访问未初始化的数据" \\
    --error-message "Cannot read properties of undefined" \\
    --root-cause "Store 初始化时序问题" \\
    --fix-method "添加空值检查" \\
    --tags vue,pinia,computed \\
    --severity major

  # 强制创建（跳过去重）
  %(prog)s record ... --force

  # 预览模式
  %(prog)s record ... --dry-run

  # 搜索问题
  %(prog)s search --language python --tags database

  # 获取统计
  %(prog)s stats

  # 修复索引文件
  %(prog)s repair
        """
    )

    parser.add_argument("--dry-run", action="store_true", help="预览模式，不实际写入文件")

    subparsers = parser.add_subparsers(dest="command", help="可用命令")

    # record 命令
    record_parser = subparsers.add_parser("record", help="记录一个新的 bug 修复")
    record_parser.add_argument("--language", required=True, help="编程语言")
    record_parser.add_argument("--frameworks", required=True, help="框架/库名称")
    record_parser.add_argument("--title", required=True, help="问题标题")
    record_parser.add_argument("--description", required=True, help="问题描述")
    record_parser.add_argument("--error-message", required=True, help="错误信息")
    record_parser.add_argument("--root-cause", required=True, help="根本原因")
    record_parser.add_argument("--fix-method", required=True, help="修复方法")
    record_parser.add_argument("--severity", default="major", choices=["critical", "major", "minor"], help="严重程度")
    record_parser.add_argument("--tags", help="标签列表（逗号分隔）")
    record_parser.add_argument("--before-code", help="修复前的代码")
    record_parser.add_argument("--after-code", help="修复后的代码")
    record_parser.add_argument("--related-files", help="相关文件列表（逗号分隔）")
    record_parser.add_argument("--category", help="分类名称")
    record_parser.add_argument("--force", action="store_true", help="强制创建新记录，跳过去重检查")

    # search 命令
    search_parser = subparsers.add_parser("search", help="搜索已记录的问题")
    search_parser.add_argument("--language", help="编程语言")
    search_parser.add_argument("--category", help="分类")
    search_parser.add_argument("--tags", help="标签列表（逗号分隔）")
    search_parser.add_argument("--severity", help="严重程度")
    search_parser.add_argument("--keyword", help="关键词")

    # stats 命令
    subparsers.add_parser("stats", help="显示全局统计信息")

    # repair 命令
    subparsers.add_parser("repair", help="修复所有索引文件格式")

    # 解析参数
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    fixer = BugFixer(dry_run=getattr(args, 'dry_run', False))

    if args.command == "record":
        tags = args.tags.split(",") if args.tags else None
        related_files = args.related_files.split(",") if args.related_files else None

        result = fixer.record_problem(
            language=args.language,
            frameworks=args.frameworks,
            title=args.title,
            description=args.description,
            error_message=args.error_message,
            root_cause=args.root_cause,
            fix_method=args.fix_method,
            severity=args.severity,
            tags=tags,
            before_code=args.before_code,
            after_code=args.after_code,
            related_files=related_files,
            category=args.category,
            force=args.force,
        )

        print(json.dumps(result, ensure_ascii=False, indent=2))

        if result.get("action") == "error":
            return 1
        if result.get("action") == "confirm_update":
            return 2
        return 0

    elif args.command == "search":
        tags = args.tags.split(",") if args.tags else None

        results = fixer.search_problems(
            language=args.language,
            category=args.category,
            tags=tags,
            severity=args.severity,
            keyword=args.keyword,
        )

        print(json.dumps(results, ensure_ascii=False, indent=2))
        print(f"\n找到 {len(results)} 个匹配问题", file=sys.stderr)

        return 0

    elif args.command == "stats":
        stats = fixer.get_stats()
        print(json.dumps(stats, ensure_ascii=False, indent=2))
        return 0

    elif args.command == "repair":
        result = fixer.repair_indexes()
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
