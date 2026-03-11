---
id: "xxx-{slug_title}"
language: {language}
frameworks:
  - {framework1}
  - {framework2}
category: {category}
title: "{problem_title}"
severity: critical | major | minor
tags:
  - {category}
  - {tag1}
  - {tag2}
first_seen: "YYYY-MM-DD"
last_seen: "YYYY-MM-DD"
occurrence_count: 1
status: unresolved | resolved | workaround
error_signature: "{error_pattern}"
---

# {problem_title}

**记录时间**: {date}
**严重程度**: {severity} (critical/major/minor)

## 基本信息

**编程语言**: {language}
**框架/库**: {frameworks}
**标签**: {tags}

## 问题描述

{description}

## 错误信息

```
{error_message}
```

## 根本原因

{root_cause}

## 修复方法

{fix_method}

## 代码示例

**修复前**:
```{language}
{before_code}
```

**修复后**:
```{language}
{after_code}
```

## 预防措施

{prevention}

## 变更历史

| 日期 | 变更 | 说明 |
|-------|------|------|
| {date} | 初始记录 | {description} |
