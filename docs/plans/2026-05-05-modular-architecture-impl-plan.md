# 模块化架构重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 debian-init-tool 和 claude-code-tool 重构为「加文件 = 加功能，框架零改动」的自描述模块架构。

**Architecture:** debian-init-tool 用 bash 注释头部声明模块元数据，框架扫描自动发现、两级菜单、拓扑排序。claude-code-tool 用目录自动发现 symlink 模块 + handlers/ 目录的 drop-in Python 插件。

**Tech Stack:** Bash (whiptail) + Python 3 stdlib

**Spec:** `docs/plans/2026-05-05-modular-architecture-redesign.md`

---

## Part 1: debian-init-tool 重构

---

### Task 1: 创建 `lib/registry.sh` 发现引擎

**Files:**
- Create: `debian-init-tool/lib/registry.sh`

- [ ] **Step 1: 创建 registry.sh**

```bash
#!/bin/bash
# 模块发现引擎
# 扫描 modules/ 目录，解析头部元数据，构建注册表

# === 分类常量 ===
CATEGORIES=("system" "base-tools" "dev-tools")
declare -A CATEGORY_TITLES=(
    ["system"]="基础功能"
    ["base-tools"]="基础工具"
    ["dev-tools"]="编程工具"
)

# === 注册表 ===
declare -a _REG=()              # 按 weight+deps 排序的模块名
declare -A _R_TITLE=()          # name → 标题
declare -A _R_WEIGHT=()         # name → 排序权重
declare -A _R_CATEGORY=()       # name → 分类
declare -A _R_DEPS=()           # name → 依赖
declare -A _R_FILE=()           # name → 文件路径

# === 发现入口 ===
load_and_discover_modules() {
    local modules_dir="${SCRIPT_DIR}/modules"
    for f in "${modules_dir}"/*.sh; do
        [[ -f "$f" ]] || continue
        source "$f" || log_warn "无法加载模块: $f"
        _parse_meta "$f"
    done
    _topo_sort
    log_info "已发现 ${#_REG[@]} 个模块"
}

# === 解析模块头部元数据 ===
_parse_meta() {
    local f="$1"
    local name="" title="" weight=99 category="" deps=""

    while IFS= read -r line; do
        # 遇到非注释行停止
        [[ "$line" =~ ^[^#] ]] && break
        [[ "$line" =~ @name[[:space:]]+(.*) ]]     && name="${BASH_REMATCH[1]}"
        [[ "$line" =~ @title[[:space:]]+(.*) ]]    && title="${BASH_REMATCH[1]}"
        [[ "$line" =~ @weight[[:space:]]+(.*) ]]   && weight="${BASH_REMATCH[1]}"
        [[ "$line" =~ @category[[:space:]]+(.*) ]] && category="${BASH_REMATCH[1]}"
        [[ "$line" =~ @deps[[:space:]]+(.*) ]]     && deps="${BASH_REMATCH[1]}"
    done < "$f"

    [[ -z "$name" ]] && return 1

    _R_TITLE[$name]="$title"
    _R_WEIGHT[$name]="$weight"
    _R_CATEGORY[$name]="$category"
    _R_DEPS[$name]="$deps"
    _R_FILE[$name]="$f"
}

# === 辅助：检查值是否在数组中 ===
_in_array() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# === 拓扑排序（按 deps 排序） ===
_topo_sort() {
    local sorted=()
    local remaining=("${!_R_WEIGHT[@]}")
    local changed=1

    while [[ $changed -eq 1 ]]; do
        changed=0
        local next_round=()

        for name in "${remaining[@]}"; do
            local deps="${_R_DEPS[$name]:-}"
            local all_met=1

            for dep in ${deps//,/ }; do
                [[ -z "$dep" ]] && continue
                if ! _in_array "$dep" "${sorted[@]+"${sorted[@]}"}"; then
                    all_met=0
                    break
                fi
            done

            if [[ $all_met -eq 1 ]]; then
                sorted+=("$name")
                changed=1
            else
                next_round+=("$name")
            fi
        done

        remaining=("${next_round[@]+"${next_round[@]}"}")
        # 防止循环依赖死循环
        [[ ${#remaining[@]} -eq ${#next_round[@]} ]] && break
    done

    # 残余（循环依赖）追加到末尾
    _REG=("${sorted[@]}" "${remaining[@]+"${remaining[@]}"}")
}

# === 按分类获取模块列表 ===
get_modules_by_category() {
    local category="$1"
    local result=()
    for name in "${_REG[@]}"; do
        [[ "${_R_CATEGORY[$name]}" == "$category" ]] && result+=("$name")
    done
    printf '%s\n' "${result[@]}"
}

# === 统计分类内完成数 ===
count_in_category() {
    local category="$1"
    local count=0
    for name in "${_REG[@]}"; do
        [[ "${_R_CATEGORY[$name]}" == "$category" ]] && ((count++))
    done
    echo $count
}

count_completed_in_category() {
    local category="$1"
    local count=0
    for name in "${_REG[@]}"; do
        if [[ "${_R_CATEGORY[$name]}" == "$category" ]] && is_completed "$name"; then
            ((count++))
        fi
    done
    echo $count
}

# === 解析 --only 参数时补齐依赖 ===
resolve_deps_for_modules() {
    local -n _result="$1"
    shift
    local requested=("$@")
    local result_map=()

    for name in "${requested[@]}"; do
        # 递归添加依赖
        _add_with_deps "$name" result_map
    done

    # 按 _REG 顺序输出
    for name in "${_REG[@]}"; do
        if _in_array "$name" "${result_map[@]+"${result_map[@]}"}"; then
            _result+=("$name")
        fi
    done
}

_add_with_deps() {
    local name="$1"
    local -n _map="$2"

    # 已添加则跳过
    _in_array "$name" "${_map[@]+"${_map[@]}"}" && return

    # 先添加依赖
    local deps="${_R_DEPS[$name]:-}"
    for dep in ${deps//,/ }; do
        [[ -z "$dep" ]] && continue
        _add_with_deps "$dep" _map
    done

    _map+=("$name")
}

# 标记库已加载
_REGISTRY_SH_LOADED=true
```

- [ ] **Step 2: 验证语法**

Run: `bash -n debian-init-tool/lib/registry.sh`
Expected: 无输出（语法正确）

- [ ] **Step 3: Commit**

```bash
git add debian-init-tool/lib/registry.sh
git commit -m "feat(debian-init): 新增 lib/registry.sh 模块发现引擎"
```

---

### Task 2: 给 16 个模块文件添加元数据头部 + 重命名去编号

**Files:**
- Modify: `debian-init-tool/modules/*.sh` (16 个文件)
- Rename: 去掉编号前缀

- [ ] **Step 1: 给每个模块文件添加头部注释并重命名**

对每个文件执行：先在 `#!/bin/bash` 行后插入 `@name/@title/@category/@weight` 注释，然后 `git mv` 去编号。

```bash
cd debian-init-tool/modules

# system 类 (weight 0-7)
git mv 00_preflight.sh preflight.sh
git mv 01_apt.sh apt.sh
git mv 02_locale.sh locale.sh
git mv 03_timezone.sh timezone.sh
git mv 04_ssh.sh ssh.sh
git mv 05_firewall.sh firewall.sh
git mv 06_fail2ban.sh fail2ban.sh
git mv 07_user.sh user.sh

# base-tools 类 (weight 10-31)
git mv 08_bash.sh bash.sh
git mv 09_zsh.sh zsh.sh
git mv 10_fish.sh fish.sh
git mv 10_docker.sh docker.sh
git mv 11_podman.sh podman.sh
git mv 13_gh.sh gh.sh
git mv 14_pi.sh pi.sh

# dev-tools 类 (weight 40+)
git mv 12_nodejs.sh nodejs.sh
```

然后在每个文件的 `#!/bin/bash` 行后添加元数据。以下是每个文件需要插入的头部（在原第一行注释前插入）：

**preflight.sh** — 在 `#!/bin/bash` 后、`# 前置检查模块` 前插入：
```bash
# @name preflight
# @title 前置检查
# @category system
# @weight 0
```

**apt.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name apt
# @title APT 源配置
# @category system
# @weight 1
```

**locale.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name locale
# @title Locale 设置
# @category system
# @weight 2
```

**timezone.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name timezone
# @title 时区设置
# @category system
# @weight 3
```

**ssh.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name ssh
# @title SSH 配置
# @category system
# @weight 4
```

**firewall.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name firewall
# @title 防火墙配置
# @category system
# @weight 5
```

**fail2ban.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name fail2ban
# @title Fail2ban 配置
# @category system
# @weight 6
```

**user.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name user
# @title 用户管理
# @category system
# @weight 7
```

**bash.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name bash
# @title Bash 配置
# @category base-tools
# @weight 10
```

**zsh.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name zsh
# @title Zsh 配置
# @category base-tools
# @weight 11
```

**fish.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name fish
# @title Fish Shell 配置
# @category base-tools
# @weight 12
```

**docker.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name docker
# @title Docker 配置
# @category base-tools
# @weight 20
```

**podman.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name podman
# @title Podman 配置
# @category base-tools
# @weight 21
```

**gh.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name gh
# @title GitHub CLI 配置
# @category base-tools
# @weight 30
```

**pi.sh** — 在 `#!/bin/bash` 后插入：
```bash
# @name pi
# @title pi coding agent 配置
# @category base-tools
# @weight 31
```

**nodejs.sh** — 在 `#!/bin/bash` 后、`# Node.js / npm` 前插入：
```bash
# @name nodejs
# @title Node.js / npm 配置
# @category dev-tools
# @weight 40
# @deps apt
```

- [ ] **Step 2: 验证每个文件头部正确**

Run: `for f in debian-init-tool/modules/*.sh; do echo "=== $(basename $f) ==="; head -6 "$f"; echo; done`
Expected: 每个文件都有 `@name` 和 `@category` 行

- [ ] **Step 3: Commit**

```bash
git add debian-init-tool/modules/
git commit -m "refactor(debian-init): 模块添加元数据头部 + 去编号重命名"
```

---

### Task 3: 重写 `lib/ui.sh` — 删硬编码、改两级菜单

**Files:**
- Modify: `debian-init-tool/lib/ui.sh`

这是最大的改动。需要：
1. 删除 `get_module_index()` 函数（~17 行）
2. 重写 `draw_main_menu()` 为两级分类菜单
3. 新增 `draw_category_menu()` 函数
4. 重写 `run_module()` 和 `run_module_silent()` 使用 `_R_FILE`
5. 重写 `run_all_modules()` 使用 `_REG` + checklist

- [ ] **Step 1: 删除 `get_module_index` 函数**

删除 `lib/ui.sh` 中整个 `get_module_index()` 函数（从 `get_module_index() {` 到对应的 `}`）。

- [ ] **Step 2: 重写 `draw_main_menu`**

用以下代码替换整个 `draw_main_menu()` 函数：

```bash
draw_main_menu() {
    local title="Debian 系统初始化配置工具"

    while true; do
        local options=()

        # 动态生成分类菜单
        for cat in "${CATEGORIES[@]}"; do
            local cat_title="${CATEGORY_TITLES[$cat]}"
            local done=$(count_completed_in_category "$cat")
            local total=$(count_in_category "$cat")
            local status="  "
            [[ "$done" -eq "$total" ]] && [[ "$total" -gt 0 ]] && status="✓"
            options+=("$cat" "${status} ${cat_title} (${done}/${total})")
        done

        options+=("all" "一键配置所有")
        options+=("backup" "查看/恢复备份")
        options+=("log" "查看日志")
        options+=("exit" "退出")

        local choice
        choice=$(draw_menu "$title" "选择要配置的类别:" "${options[@]}")

        case $? in
            0)
                case "$choice" in
                    exit)
                        return 0
                        ;;
                    all)
                        draw_run_all_menu
                        ;;
                    backup)
                        show_backup_menu
                        ;;
                    log)
                        show_log_viewer
                        ;;
                    *)
                        draw_category_menu "$choice"
                        ;;
                esac
                ;;
            1|255)
                return 0
                ;;
        esac
    done
}
```

- [ ] **Step 3: 新增 `draw_category_menu` 函数**

在 `draw_main_menu` 函数后面添加：

```bash
# 显示分类下的二级菜单
draw_category_menu() {
    local category="$1"
    local cat_title="${CATEGORY_TITLES[$category]}"

    # 收集该分类下的模块
    local modules=()
    for name in "${_REG[@]}"; do
        [[ "${_R_CATEGORY[$name]}" == "$category" ]] && modules+=("$name")
    done

    [[ ${#modules[@]} -eq 0 ]] && { draw_msgbox "$cat_title" "该分类下没有模块"; return; }

    # 生成 checklist
    local options=()
    for name in "${modules[@]}"; do
        local status="OFF"
        is_completed "$name" && status="ON"
        # 基础功能默认全选
        [[ "$category" == "system" ]] && status="ON"
        options+=("$name" "${_R_TITLE[$name]}" "$status")
    done

    local choices
    choices=$(draw_checklist "$cat_title" "选择要配置的模块 (空格选择，回车确认):" "${options[@]}")
    [[ $? -ne 0 ]] && return

    # 依次执行选中的模块
    for name in $choices; do
        run_module "$name"
    done
}
```

- [ ] **Step 4: 重写 `run_module`**

用以下代码替换整个 `run_module()` 函数：

```bash
# 运行单个模块 (交互模式)
run_module() {
    local module
    module=$(strip_ansi "$1")
    local file="${_R_FILE[$module]}"

    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        draw_msgbox "错误" "找不到模块: $module"
        return 1
    fi

    local title="${_R_TITLE[$module]:-$module}"
    log_info "开始执行模块: $module"

    if configure_"$module"; then
        mark_completed "$module"
        if declare -f mark_module_completed &>/dev/null; then
            mark_module_completed "$module"
        fi
        draw_msgbox "成功" "${title} 配置完成"
    else
        draw_msgbox "错误" "${title} 配置失败，请查看日志"
    fi
}
```

注意：模块文件已在 `load_and_discover_modules` 中被 source，这里不需要再 source。

- [ ] **Step 5: 重写 `run_module_silent`**

用以下代码替换整个 `run_module_silent()` 函数：

```bash
# 静默运行模块
run_module_silent() {
    local module
    module=$(strip_ansi "$1")
    local file="${_R_FILE[$module]}"

    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        return 1
    fi

    if configure_"$module"; then
        mark_completed "$module"
        return 0
    fi
    return 1
}
```

- [ ] **Step 6: 重写 `run_all_modules`**

用以下代码替换整个 `run_all_modules()` 函数：

```bash
# 一键配置 — 弹出全模块 checklist 让用户确认
draw_run_all_menu() {
    local options=()
    for name in "${_REG[@]}"; do
        local status="OFF"
        is_completed "$name" && status="ON"
        options+=("$name" "${_R_TITLE[$name]}" "$status")
    done

    local choices
    choices=$(draw_checklist "一键配置" "选择要配置的模块 (空格选择，回车确认):" "${options[@]}")
    [[ $? -ne 0 ]] && return

    local total=$(echo "$choices" | wc -w)
    local current=0
    local failed=()

    for name in $choices; do
        ((current++))
        show_gauge "一键配置" "正在配置: ${_R_TITLE[$name]} ($current/$total)" $((current * 100 / total))

        if ! run_module_silent "$name"; then
            failed+=("$name")
        fi
    done

    if [[ ${#failed[@]} -eq 0 ]]; then
        draw_msgbox "成功" "所有模块配置完成!"
    else
        draw_msgbox "警告" "以下模块配置失败: ${failed[*]}"
    fi
}
```

- [ ] **Step 7: 验证语法**

Run: `bash -n debian-init-tool/lib/ui.sh`
Expected: 无输出（注意会有 `source` 相关的未定义变量警告，这是正常的）

- [ ] **Step 8: Commit**

```bash
git add debian-init-tool/lib/ui.sh
git commit -m "refactor(debian-init): ui.sh 改为两级菜单 + registry 驱动

- 删除 get_module_index() 硬编码映射
- draw_main_menu 从 registry 动态生成分类菜单
- 新增 draw_category_menu 二级菜单
- run_module/run_module_silent 通过 _R_FILE 查找文件
- run_all_modules 改为 checklist 确认模式"
```

---

### Task 4: 重写 `debian-init.sh` — 接入 registry

**Files:**
- Modify: `debian-init-tool/debian-init.sh`

- [ ] **Step 1: 添加 registry.sh 的 source**

在 `debian-init.sh` 中，找到加载 lib 库的区块（约第 75-79 行），在 `source "${SCRIPT_DIR}/lib/backup.sh"` 之后添加一行：

```bash
source "${SCRIPT_DIR}/lib/registry.sh" || { echo "无法加载注册表模块"; exit 1; }
```

- [ ] **Step 2: 删除 `load_modules` 函数**

删除 `debian-init.sh` 中整个 `load_modules()` 函数：

```bash
# 删除这整个函数（约第 202-209 行）
load_modules() {
    local modules_dir="${SCRIPT_DIR}/modules"
    ...
}
```

- [ ] **Step 3: 重写 `run_auto_mode`**

用以下代码替换整个 `run_auto_mode()` 函数：

```bash
run_auto_mode() {
    log_info "启动自动配置模式..."

    local modules=()
    local skip_array=()

    # 处理 --only 参数（带依赖解析）
    if [[ -n "$ONLY_MODULES" ]]; then
        local -a only_names=()
        IFS=',' read -ra only_names <<< "$ONLY_MODULES"
        resolve_deps_for_modules modules "${only_names[@]}"
    else
        modules=("${_REG[@]}")
    fi

    # 处理 --skip 参数
    if [[ -n "$SKIP_MODULES" ]]; then
        IFS=',' read -ra skip_array <<< "$SKIP_MODULES"
    fi

    local failed_modules=()
    local total=${#modules[@]}
    local current=0

    for module in "${modules[@]}"; do
        # 检查是否跳过
        local skip=false
        for skip_module in "${skip_array[@]}"; do
            [[ "$module" == "$skip_module" ]] && skip=true && break
        done

        if $skip; then
            log_info "跳过模块: $module"
            continue
        fi

        ((current++))
        echo "[$current/$total] 配置: $module"

        if ! run_module_cli "$module"; then
            failed_modules+=("$module")
        fi
    done

    # 报告结果
    echo ""
    echo "================================"
    if [[ ${#failed_modules[@]} -eq 0 ]]; then
        echo "所有模块配置完成!"
    else
        echo "配置完成，以下模块失败:"
        for module in "${failed_modules[@]}"; do
            echo "  - $module"
        done
    fi
    echo "================================"

    return ${#failed_modules[@]}
}
```

- [ ] **Step 4: 修改 `main` 函数中的模块加载**

找到 `main()` 函数中的 `load_modules` 调用（约第 408 行），替换为：

```bash
    load_and_discover_modules
```

- [ ] **Step 5: 验证语法**

Run: `bash -n debian-init-tool/debian-init.sh`
Expected: 无输出

- [ ] **Step 6: Commit**

```bash
git add debian-init-tool/debian-init.sh
git commit -m "refactor(debian-init): 接入 registry 引擎 + 依赖解析

- source registry.sh
- load_modules → load_and_discover_modules
- run_auto_mode 使用 _REG + resolve_deps_for_modules
- --only 参数自动补齐依赖"
```

---

### Task 5: debian-init-tool 集成验证

**Files:**
- 无新文件

- [ ] **Step 1: 验证模块发现**

Run: `cd debian-init-tool && bash -c 'SCRIPT_DIR="$(pwd)"; source lib/log.sh; source lib/common.sh; source lib/registry.sh; load_and_discover_modules; echo "Found ${#_REG[@]} modules:"; for n in "${_REG[@]}"; do echo "  $n (${_R_CATEGORY[$n]}) w=${_R_WEIGHT[$n]}"; done'`
Expected: 输出 16 个模块及其分类和权重，按排序顺序

- [ ] **Step 2: 验证分类统计**

Run: `cd debian-init-tool && bash -c 'SCRIPT_DIR="$(pwd)"; source lib/log.sh; source lib/common.sh; source lib/registry.sh; source lib/ui.sh; load_and_discover_modules; for cat in "${CATEGORIES[@]}"; do echo "$cat: $(count_in_category $cat) modules"; done'`
Expected: system: 8, base-tools: 7, dev-tools: 1

- [ ] **Step 3: 验证自动模式 dry-run**

Run: `cd debian-init-tool && sudo bash debian-init.sh --auto --dry-run 2>&1 | head -20`
Expected: 输出 16 个模块的模拟执行信息

- [ ] **Step 4: Commit（如有修复）**

```bash
git add -A
git commit -m "fix(debian-init): 集成验证修复"
```

---

## Part 2: claude-code-tool 重构

---

### Task 6: 创建 `installer/registry.py` 发现引擎

**Files:**
- Create: `claude-code-tool/installer/registry.py`

- [ ] **Step 1: 创建 registry.py**

```python
"""自动发现引擎：目录即模块 + Handler 插件。"""

import importlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, Callable

EXCLUDE_DIRS = {"__pycache__", ".DS_Store", ".git", "node_modules", "bak",
                "knowledge-engine", "installer"}
EXCLUDE_FILES = {".DS_Store", ".gitignore"}
SYMLINK_SUFFIX = (".md",)  # 根目录下这些后缀的文件自动 symlink


@dataclass
class ModuleInfo:
    """一个已发现的模块。"""
    name: str
    title: str
    risk: str = "low"
    module_type: str = "symlink"      # symlink | file | handler | user-handler
    source: Optional[Path] = None     # symlink/file: 源目录或源文件
    handler: Optional[object] = None  # handler: Python 模块对象
    targets: Optional[list[str]] = None  # None = 所有 target

    @property
    def is_user_level(self) -> bool:
        return self.module_type == "user-handler"


def discover_all(script_dir: Path) -> list[ModuleInfo]:
    """扫描 script_dir + handlers/ 目录，发现所有模块。"""
    modules = []

    # 第一层：目录即 symlink 模块
    for child in sorted(script_dir.iterdir()):
        if child.name.startswith('.') or child.name in EXCLUDE_DIRS:
            continue
        if child.is_dir():
            modules.append(ModuleInfo(
                name=child.name,
                title=f"{child.name}/ 目录",
                module_type="symlink",
                source=child,
            ))
        elif child.is_file() and child.suffix in SYMLINK_SUFFIX:
            modules.append(ModuleInfo(
                name=child.stem,
                title=child.name,
                risk="medium",
                module_type="file",
                source=child,
            ))

    # 第二层：Handler 插件
    handler_dir = Path(__file__).parent / "handlers"
    if handler_dir.is_dir():
        for py in sorted(handler_dir.glob("*.py")):
            if py.name.startswith("_"):
                continue
            mod = importlib.import_module(f".handlers.{py.stem}", package="installer")
            targets = getattr(mod, "TARGETS", [])
            modules.append(ModuleInfo(
                name=py.stem.replace("_", "-"),
                title=getattr(mod, "TITLE", py.stem),
                risk=getattr(mod, "RISK", "low"),
                module_type="user-handler" if not targets else "handler",
                handler=mod,
                targets=targets if targets else None,
            ))

    return modules
```

- [ ] **Step 2: 验证语法**

Run: `cd claude-code-tool && python3 -c "from installer.registry import discover_all, ModuleInfo; print('✓ OK')"`
Expected: `✓ OK`

- [ ] **Step 3: Commit**

```bash
git add claude-code-tool/installer/registry.py
git commit -m "feat(claude-code): 新增 registry.py 发现引擎"
```

---

### Task 7: 创建 `installer/engine.py` 通用执行引擎

**Files:**
- Create: `claude-code-tool/installer/engine.py`

这个文件包含：UndoStack、Action 类型、通用 plan/execute 逻辑、settings.json snapshot。

- [ ] **Step 1: 创建 engine.py**

```python
"""通用执行引擎：plan → execute → undo。"""

import json
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from . import ui
from .utils import backup_file, create_symlink, is_our_symlink, load_json, save_json
from .registry import ModuleInfo

EXCLUDE_PATTERNS = {"__pycache__", ".DS_Store", ".git"}


# ── UndoStack ──────────────────────────────────────────────

class UndoStack:
    def __init__(self):
        self._items: list[tuple[str, callable]] = []

    def push(self, description: str, undo_fn: callable) -> None:
        self._items.append((description, undo_fn))

    def rollback(self) -> int:
        count = 0
        for desc, undo_fn in reversed(self._items):
            try:
                undo_fn()
                ui.info(f"  ↩ 回滚: {desc}")
                count += 1
            except Exception as e:
                ui.warn(f"  ↩ 回滚失败: {desc} ({e})")
        self._items.clear()
        return count

    def clear(self) -> None:
        self._items.clear()


# ── Action types ───────────────────────────────────────────

@dataclass
class Action:
    description: str

@dataclass
class SymlinkAction(Action):
    source: Path
    target: Path

@dataclass
class BackupAction(Action):
    original: Path
    backup: Path

@dataclass
class MessageAction(Action):
    pass

@dataclass
class DeployFileAction(Action):
    source: Path
    target: Path

@dataclass
class GenerateFileAction(Action):
    target: Path
    content: str
    executable: bool = False

@dataclass
class PipInstallAction(Action):
    package: str


# ── Symlink planning ──────────────────────────────────────

def plan_symlinks(source_dir: Path, target_dir: Path, backup_dir: Path) -> list[Action]:
    """扫描 source_dir，生成 symlink actions。"""
    from datetime import datetime
    if not source_dir.is_dir():
        return []
    actions = []
    for child in sorted(source_dir.iterdir()):
        if child.name in EXCLUDE_PATTERNS or not child.exists():
            continue
        dest = target_dir / child.name
        if dest.is_symlink() and is_our_symlink(dest, child):
            continue
        if dest.exists() and not dest.is_symlink():
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            actions.append(BackupAction(
                description=f"备份 {child.name}",
                original=dest,
                backup=backup_dir / f"{child.name}_{ts}",
            ))
        actions.append(SymlinkAction(
            description=f"{source_dir.name}/{child.name}",
            source=child, target=dest,
        ))
    return actions


def plan_file(source: Path, target: Path, backup_dir: Path) -> list[Action]:
    """单文件 symlink plan（带 diff 显示）。"""
    from datetime import datetime
    if not source.exists():
        return []
    actions = []
    if target.is_symlink() and is_our_symlink(target, source):
        return []
    if target.exists() and not target.is_symlink():
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        actions.append(BackupAction(
            description=f"备份 {source.name}",
            original=target,
            backup=backup_dir / f"{source.name}_{ts}",
        ))
        if target.is_file():
            try:
                import difflib
                old = target.read_text().splitlines(keepends=True)
                new = source.read_text().splitlines(keepends=True)
                diff = list(difflib.unified_diff(old, new,
                                                  fromfile=str(target), tofile=str(source)))
                if diff:
                    actions.append(MessageAction(description=f"{source.name} 有差异:"))
                    for line in diff[:20]:
                        actions.append(MessageAction(description=f"  {line.rstrip()}"))
            except Exception:
                pass
    actions.append(SymlinkAction(description=source.name, source=source, target=target))
    return actions


# ── Action execution ──────────────────────────────────────

def execute_action(action, backup_dir: Path, undo_stack: Optional[UndoStack] = None) -> None:
    """执行单个 action。"""
    if isinstance(action, SymlinkAction):
        if action.target.exists() and not action.target.is_symlink():
            backup_file(action.target, backup_dir)
        create_symlink(action.source, action.target)
        ui.success(f"链接: {action.target.name}")
        if undo_stack:
            undo_stack.push(f"移除链接 {action.target.name}",
                            lambda t=action.target: t.unlink())

    elif isinstance(action, BackupAction):
        backup_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(str(action.original), str(action.backup))

    elif isinstance(action, DeployFileAction):
        action.target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(str(action.source), str(action.target))
        ui.success(f"部署: {action.target}")
        if undo_stack:
            undo_stack.push(f"移除部署 {action.target.name}",
                            lambda t=action.target: t.unlink(missing_ok=True))

    elif isinstance(action, GenerateFileAction):
        action.target.parent.mkdir(parents=True, exist_ok=True)
        action.target.write_text(action.content)
        if action.executable:
            action.target.chmod(0o755)
        ui.success(f"生成: {action.target}")
        if undo_stack:
            undo_stack.push(f"移除生成文件 {action.target.name}",
                            lambda t=action.target: t.unlink(missing_ok=True))

    elif isinstance(action, PipInstallAction):
        ui.info(f"安装 {action.package}...")
        result = subprocess.run(
            [sys.executable, "-m", "pip", "install", action.package],
            capture_output=True, text=True)
        if result.returncode == 0:
            ui.success(f"{action.package} 安装完成")
        else:
            ui.error(f"{action.package} 安装失败")
            raise RuntimeError(f"pip install {action.package} failed")

    elif isinstance(action, MessageAction):
        ui.info(action.description)


def execute_actions(actions: list, backup_dir: Path,
                    undo_stack: Optional[UndoStack] = None) -> None:
    """执行一组 actions。"""
    for action in actions:
        execute_action(action, backup_dir, undo_stack)


# ── Settings snapshot ─────────────────────────────────────

def snapshot_settings(target: Path, backup_dir: Path) -> Optional[dict]:
    """备份 settings.json 并返回内容快照。None 表示文件不存在。"""
    settings = target / "settings.json"
    if settings.exists():
        data = load_json(settings)
        backup_file(settings, backup_dir)
        return json.loads(json.dumps(data))  # deep copy
    return None


def restore_or_delete_settings(target: Path, snapshot: Optional[dict],
                                undo_stack: UndoStack) -> None:
    """记录 settings.json 的 undo 操作。"""
    rel = "~/" + str(target.relative_to(Path.home()))
    settings = target / "settings.json"
    if snapshot is not None:
        snap = snapshot
        undo_stack.push(f"恢复 {rel}/settings.json",
                        lambda s=settings, d=snap: save_json(s, d))
    else:
        undo_stack.push(f"删除 {rel}/settings.json",
                        lambda s=settings: s.unlink(missing_ok=True))
```

- [ ] **Step 2: 验证语法**

Run: `cd claude-code-tool && python3 -c "from installer.engine import UndoStack, discover_all; print('✓ OK')"`
Expected: `✓ OK`（注意 discover_all 在 registry.py 里，这里测试 import）

- [ ] **Step 3: Commit**

```bash
git add claude-code-tool/installer/engine.py
git commit -m "feat(claude-code): 新增 engine.py 通用执行引擎"
```

---

### Task 8: 创建 handlers 目录和 7 个 handler 文件

**Files:**
- Create: `claude-code-tool/installer/handlers/__init__.py`
- Create: `claude-code-tool/installer/handlers/statusline.py`
- Create: `claude-code-tool/installer/handlers/skill_inject.py`
- Create: `claude-code-tool/installer/handlers/knowledge_engine.py`
- Create: `claude-code-tool/installer/handlers/tavily_cli.py`
- Create: `claude-code-tool/installer/handlers/pi_skills.py`
- Create: `claude-code-tool/installer/handlers/pi_agents.py`
- Create: `claude-code-tool/installer/handlers/pi_statusline.py`

每个 handler 从当前 `installer/modules.py` 中提取逻辑，保持 `configure` / `unconfigure` 两个函数。

- [ ] **Step 1: 创建 handlers/__init__.py**

空文件：
```python
"""Handler plugins for claude-code-tool installer."""
```

- [ ] **Step 2: 创建 handlers/statusline.py**

```python
"""Statusline configuration — adds statusLine to settings.json."""

from pathlib import Path
from installer.utils import load_json, save_json

TITLE = "状态栏"
RISK = "low"
TARGETS = [".claude", ".opencode"]


def configure(target: Path, script_dir: Path) -> bool:
    settings = target / "settings.json"
    command = f'"{target}/custom-tools/statusline.sh"'

    if settings.exists():
        data = load_json(settings)
        if data.get("statusLine", {}).get("command", "") == command:
            return True
    else:
        data = {}

    data["statusLine"] = {"type": "command", "command": command}
    save_json(settings, data)
    return True


def unconfigure(target: Path, script_dir: Path = None) -> None:
    settings = target / "settings.json"
    if not settings.exists():
        return
    data = load_json(settings)
    if "statusLine" in data:
        del data["statusLine"]
        save_json(settings, data)
```

- [ ] **Step 3: 创建 handlers/skill_inject.py**

```python
"""Skill injection hook — adds PreToolUse hook for Skill tool."""

from pathlib import Path
from installer.utils import load_json, save_json

TITLE = "Skill 注入 Hook"
RISK = "medium"
TARGETS = [".claude"]

HOOK_CMD = 'bash "$HOME/.claude/hooks/skill-inject.sh"'


def configure(target: Path, script_dir: Path) -> bool:
    settings = target / "settings.json"
    data = load_json(settings) if settings.exists() else {}

    hooks = data.setdefault("hooks", {})
    pre = hooks.setdefault("PreToolUse", [])

    # 检查是否已配置
    for entry in pre:
        if entry.get("matcher") == "Skill":
            for h in entry.get("hooks", []):
                if h.get("command") == HOOK_CMD:
                    return True

    pre = [e for e in pre if e.get("matcher") != "Skill"]
    pre.append({"matcher": "Skill",
                "hooks": [{"type": "command", "command": HOOK_CMD, "timeout": 5}]})
    hooks["PreToolUse"] = pre
    save_json(settings, data)
    return True


def unconfigure(target: Path, script_dir: Path = None) -> None:
    settings = target / "settings.json"
    if not settings.exists():
        return
    data = load_json(settings)
    pre = data.get("hooks", {}).get("PreToolUse", [])
    pre = [e for e in pre
           if not (e.get("matcher") == "Skill"
                   and any(h.get("command") == HOOK_CMD for h in e.get("hooks", [])))]
    pre = [e for e in pre if e.get("hooks")]
    data.setdefault("hooks", {})["PreToolUse"] = pre
    save_json(settings, data)
```

- [ ] **Step 4: 创建 handlers/knowledge_engine.py**

```python
"""Knowledge engine — bun deps, hooks, crontab, marker file."""

import shutil
import subprocess
from pathlib import Path

from installer import ui
from installer.utils import run_cmd, load_json, save_json

TITLE = "知识引擎"
RISK = "high"
TARGETS = [".claude"]

ENGINE_MARKER = ".engine_cli_path"


def configure(target: Path, script_dir: Path) -> bool:
    engine_dir = script_dir / "knowledge-engine"
    cli_path = engine_dir / "src" / "cli.ts"
    if not cli_path.exists():
        ui.warn("知识引擎源码不存在，跳过")
        return False

    # Install deps
    result = run_cmd(["bun", "install", "--frozen-lockfile"], cwd=str(engine_dir))
    if result.returncode != 0:
        result = run_cmd(["bun", "install", "--no-save"], cwd=str(engine_dir))
        if result.returncode != 0:
            ui.error("知识引擎依赖安装失败")
            return False

    # Init knowledge dir
    knowledge_dir = target / "knowledge"
    knowledge_dir.mkdir(parents=True, exist_ok=True)
    config_path = knowledge_dir / "config.json"
    if not config_path.exists():
        save_json(config_path, {
            "categories": ["architecture", "patterns", "domain", "troubleshooting"],
            "consolidateThreshold": 3,
            "excludePatterns": ["**/*.lock", "**/node_modules/**", ".env*"],
        }, perm=0o644)

    # Configure hooks
    cli_abs = cli_path.resolve()
    record_cmd = f'bun "{cli_abs}" record'
    process_cmd = f'bun "{cli_abs}" process'
    inject_cmd = f'bun "{cli_abs}" inject-index'

    settings = target / "settings.json"
    data = load_json(settings) if settings.exists() else {}
    hooks = data.setdefault("hooks", {})

    post = [e for e in hooks.get("PostToolUse", [])
            if not any(h.get("command") == record_cmd for h in e.get("hooks", []))]
    post.append({"matcher": "Write|Edit", "hooks": [
        {"type": "command", "command": record_cmd, "async": True, "timeout": 5}]})
    hooks["PostToolUse"] = post

    stop = [e for e in hooks.get("Stop", [])
            if not any(h.get("command") == process_cmd for h in e.get("hooks", []))]
    stop.append({"hooks": [
        {"type": "command", "command": process_cmd, "async": True, "timeout": 120}]})
    hooks["Stop"] = stop

    start = [e for e in hooks.get("SessionStart", [])
             if not any(h.get("command") == inject_cmd for h in e.get("hooks", []))]
    start.append({"hooks": [
        {"type": "command", "command": inject_cmd, "timeout": 5}]})
    hooks["SessionStart"] = start

    save_json(settings, data)
    ui.success("知识引擎 hooks 已配置")

    # Store cli path marker
    (knowledge_dir / ENGINE_MARKER).write_text(str(cli_abs))

    # Crontab
    _setup_crontab(engine_dir)
    return True


def _setup_crontab(engine_dir: Path) -> None:
    cron_script = engine_dir / "scripts" / "cron-maintenance.sh"
    marker = "# knowledge-engine-cron"
    entry = f"0 23 * * * {cron_script} >> ~/.claude/knowledge/maintenance.log 2>&1 {marker}"
    try:
        result = run_cmd(["crontab", "-l"])
        existing = result.stdout if result.returncode == 0 else ""
        lines = [l for l in existing.splitlines() if marker not in l]
        lines.append(entry)
        r = subprocess.run(["crontab", "-"], input="\n".join(lines) + "\n", text=True)
        if r.returncode == 0:
            ui.success("crontab 已配置")
        else:
            ui.warn(f"crontab 写入失败 (exit {r.returncode})")
    except Exception:
        ui.warn("crontab 配置失败")


def unconfigure(target: Path, script_dir: Path = None) -> None:
    settings = target / "settings.json"
    if not settings.exists():
        return

    # Read marker for precise removal
    marker_path = target / "knowledge" / ENGINE_MARKER
    if marker_path.is_file():
        cli_abs_str = marker_path.read_text().strip()
        cli_abs = Path(cli_abs_str)
        cmds = {f'bun "{cli_abs}" {cmd}' for cmd in ("record", "process", "inject-index")}
        data = load_json(settings)
        for hook_type in ("PostToolUse", "Stop", "SessionStart"):
            entries = data.get("hooks", {}).get(hook_type, [])
            cleaned = []
            for e in entries:
                hs = [h for h in e.get("hooks", []) if h.get("command") not in cmds]
                if hs:
                    e["hooks"] = hs
                    cleaned.append(e)
            data.setdefault("hooks", {})[hook_type] = cleaned
        save_json(settings, data)
        marker_path.unlink(missing_ok=True)
    else:
        data = load_json(settings)
        for hook_type in ("PostToolUse", "Stop", "SessionStart"):
            entries = data.get("hooks", {}).get(hook_type, [])
            data.setdefault("hooks", {})[hook_type] = [e for e in entries if e.get("hooks")]
        save_json(settings, data)

    # Remove crontab
    marker = "knowledge-engine-cron"
    try:
        result = run_cmd(["crontab", "-l"])
        if result.returncode == 0 and marker in result.stdout:
            lines = [l for l in result.stdout.splitlines() if marker not in l]
            subprocess.run(["crontab", "-"], input="\n".join(lines) + "\n", text=True)
    except Exception:
        pass
```

- [ ] **Step 5: 创建 handlers/tavily_cli.py**

```python
"""Tavily CLI — user-level search/extract/crawl tool."""

import shutil
import subprocess
import sys
from pathlib import Path

from installer import ui
from installer.utils import cmd_exists, run_cmd
from installer.engine import DeployFileAction, GenerateFileAction, PipInstallAction, execute_actions

TITLE = "Tavily CLI 工具 (search/extract/crawl)"
RISK = "low"
TARGETS = []  # user-level, no target binding

TAVILY_LIB = Path.home() / ".local" / "share" / "tavily"
TAVILY_BIN = Path.home() / ".local" / "bin" / "tavily"


def _wrapper_script() -> str:
    return (
        '#!/usr/bin/env python3\n'
        '"""tavily — wrapper that sources shell env if needed."""\n'
        'import os, sys\n'
        '\n'
        'if os.environ.get("TAVILY_API_KEYS"):\n'
        '    os.execvp(sys.executable, [sys.executable,\n'
        '        os.path.expanduser("~/.local/share/tavily/tavily.py")] + sys.argv[1:])\n'
        '\n'
        'tavily_sh = os.path.expanduser("~/.shell/tavily.sh")\n'
        'if os.path.isfile(tavily_sh):\n'
        '    with open(tavily_sh) as f:\n'
        '        for line in f:\n'
        '            line = line.strip()\n'
        '            if line.startswith("export TAVILY_API_KEYS="):\n'
        '                val = line.split("=", 1)[1].strip().strip(\'"\').strip("\'")\n'
        '                os.environ["TAVILY_API_KEYS"] = val\n'
        '                break\n'
        '\n'
        'if os.environ.get("TAVILY_API_KEYS"):\n'
        '    os.execvp(sys.executable, [sys.executable,\n'
        '        os.path.expanduser("~/.local/share/tavily/tavily.py")] + sys.argv[1:])\n'
        'else:\n'
        '    print("错误: 请设置 TAVILY_API_KEYS 环境变量", file=sys.stderr)\n'
        '    sys.exit(1)\n'
    )


def configure(target: Path, script_dir: Path) -> bool:
    """target 参数被忽略（user-level）。"""
    src = script_dir / "skills" / "tavily-web-search" / "scripts" / "tavily.py"
    if not src.exists():
        ui.warn("Tavily CLI: 源码不存在")
        return False

    actions = [
        DeployFileAction(description="部署 tavily.py", source=src,
                         target=TAVILY_LIB / "tavily.py"),
        GenerateFileAction(description="部署 tavily wrapper",
                           target=TAVILY_BIN,
                           content=_wrapper_script(), executable=True),
    ]
    result = run_cmd(["python3", "-c", "import httpx"])
    if result.returncode != 0:
        actions.append(PipInstallAction(description="安装 httpx", package="httpx"))

    execute_actions(actions, Path.home() / ".local" / "bak")
    return True


def unconfigure(target: Path, script_dir: Path = None) -> None:
    if TAVILY_BIN.exists():
        TAVILY_BIN.unlink()
        ui.info("已移除 ~/.local/bin/tavily")
    if TAVILY_LIB.is_dir():
        shutil.rmtree(TAVILY_LIB)
        ui.info("已移除 ~/.local/share/tavily/")
    ui.info("注意: httpx 依赖未卸载")
```

- [ ] **Step 6: 创建 handlers/pi_skills.py**

```python
"""Pi Skills — symlink skills/ to ~/.pi/agent/skills/."""

from pathlib import Path
from installer import ui
from installer.utils import backup_file, create_symlink, is_our_symlink
from installer.engine import EXCLUDE_PATTERNS

TITLE = "pi Skills"
RISK = "low"
TARGETS = ["pi"]


def configure(target: Path, script_dir: Path) -> bool:
    src_dir = script_dir / "skills"
    if not src_dir.is_dir():
        return True
    dest_dir = target / "skills"
    dest_dir.mkdir(parents=True, exist_ok=True)
    for child in sorted(src_dir.iterdir()):
        if child.name in EXCLUDE_PATTERNS or not child.exists():
            continue
        dest = dest_dir / child.name
        if dest.is_symlink() and is_our_symlink(dest, child):
            continue
        if dest.exists() and not dest.is_symlink():
            backup_file(dest, target / "bak")
        create_symlink(child, dest)
        ui.success(f"链接: {child.name}")
    return True


def unconfigure(target: Path, script_dir: Path = None) -> None:
    src_dir = (script_dir or Path()) / "skills"
    if not src_dir.is_dir():
        return
    for child in sorted(src_dir.iterdir()):
        dest = target / "skills" / child.name
        if dest.is_symlink() and is_our_symlink(dest, child):
            dest.unlink()
            ui.info(f"移除: {child.name}")
```

- [ ] **Step 7: 创建 handlers/pi_agents.py**

```python
"""Pi Agents — map agents/*/agent.md to ~/.pi/agent/agents/*.md."""

from datetime import datetime
from pathlib import Path
from installer import ui
from installer.utils import backup_file, create_symlink, is_our_symlink
from installer.engine import EXCLUDE_PATTERNS

TITLE = "pi Agents"
RISK = "low"
TARGETS = ["pi"]


def configure(target: Path, script_dir: Path) -> bool:
    src_dir = script_dir / "agents"
    if not src_dir.is_dir():
        return True
    dest_dir = target / "agents"
    dest_dir.mkdir(parents=True, exist_ok=True)
    for child in sorted(src_dir.iterdir()):
        if child.name in EXCLUDE_PATTERNS:
            continue
        agent_md = child / "agent.md"
        if not child.is_dir() or not agent_md.exists():
            continue
        dest = dest_dir / f"{child.name}.md"
        if dest.is_symlink() and is_our_symlink(dest, agent_md):
            continue
        if dest.exists() and not dest.is_symlink():
            backup_file(dest, target / "bak")
        create_symlink(agent_md, dest)
        ui.success(f"链接: {child.name}.md")
    return True


def unconfigure(target: Path, script_dir: Path = None) -> None:
    src_dir = (script_dir or Path()) / "agents"
    if not src_dir.is_dir():
        return
    for child in sorted(src_dir.iterdir()):
        agent_md = child / "agent.md"
        dest = target / "agents" / f"{child.name}.md"
        if dest.is_symlink() and is_our_symlink(dest, agent_md):
            dest.unlink()
            ui.info(f"移除: {child.name}")
```

- [ ] **Step 8: 创建 handlers/pi_statusline.py**

```python
"""Pi Statusline — symlink custom-tools/pi-statusline/ to ~/.pi/agent/extensions/statusline/."""

from pathlib import Path
from installer import ui
from installer.utils import backup_file, create_symlink, is_our_symlink

TITLE = "pi 状态栏"
RISK = "low"
TARGETS = ["pi"]


def configure(target: Path, script_dir: Path) -> bool:
    src_dir = script_dir / "custom-tools" / "pi-statusline"
    if not src_dir.is_dir():
        return True
    dest_dir = target / "extensions" / "statusline"
    dest_dir.mkdir(parents=True, exist_ok=True)
    for child in sorted(src_dir.iterdir()):
        if not child.is_file():
            continue
        dest = dest_dir / child.name
        if dest.is_symlink() and is_our_symlink(dest, child):
            continue
        if dest.exists() and not dest.is_symlink():
            backup_file(dest, target / "bak")
        create_symlink(child, dest)
        ui.success(f"链接: {child.name}")
    return True


def unconfigure(target: Path, script_dir: Path = None) -> None:
    src_dir = (script_dir or Path()) / "custom-tools" / "pi-statusline"
    dest_dir = target / "extensions" / "statusline"
    if not src_dir.is_dir() or not dest_dir.is_dir():
        return
    for child in sorted(src_dir.iterdir()):
        dest = dest_dir / child.name
        if dest.is_symlink() and is_our_symlink(dest, child):
            dest.unlink()
            ui.info(f"移除: {child.name}")
```

- [ ] **Step 9: 验证所有 handler 可加载**

Run: `cd claude-code-tool && python3 -c "from installer.registry import discover_all; from pathlib import Path; ms = discover_all(Path('.')); print(f'Found {len(ms)} modules:'); [print(f'  {m.name} ({m.module_type})') for m in ms]"`
Expected: 列出所有 symlink 模块 + 7 个 handler

- [ ] **Step 10: Commit**

```bash
git add claude-code-tool/installer/handlers/
git commit -m "feat(claude-code): 新增 7 个 handler 插件

- statusline: settings.json statusLine 配置
- skill_inject: PreToolUse hook 配置
- knowledge_engine: bun deps + hooks + crontab + marker
- tavily_cli: 用户级 CLI 部署
- pi_skills/pi_agents/pi_statusline: Pi 路径映射"
```

---

### Task 9: 重写 `installer/core.py` — 调用 registry + engine

**Files:**
- Rewrite: `claude-code-tool/installer/core.py`

- [ ] **Step 1: 重写 core.py**

```python
"""Claude Code Tool Installer — main installer logic."""

import shutil
from pathlib import Path
from typing import Optional

from . import ui
from .engine import (
    Action, SymlinkAction, BackupAction, MessageAction,
    UndoStack, plan_symlinks, plan_file,
    execute_actions, snapshot_settings, restore_or_delete_settings,
)
from .registry import discover_all, ModuleInfo
from .utils import backup_file, log_action


class Installer:
    """Main installer orchestrator."""

    def __init__(self, script_dir: Path, dry_run: bool = False):
        self.script_dir = script_dir
        self.dry_run = dry_run
        self.all_modules = discover_all(script_dir)
        self.targets: dict[str, Path] = {
            "claude": Path.home() / ".claude",
            "opencode": Path.home() / ".opencode",
            "agents": Path.home() / ".agents",
            "pi": Path.home() / ".pi" / "agent",
        }

    def run(self) -> None:
        while True:
            mode = " (dry-run)" if self.dry_run else ""
            choice = ui.choose(
                f"=== Claude Code Tool 管理脚本{mode} ===\n请选择操作:",
                [("1", "安装"), ("2", "卸载"), ("3", "退出")],
            )
            if choice == "1":
                self._install_flow()
            elif choice == "2":
                self._uninstall_flow()
            else:
                print("\n再见!\n")
                break

    # ── Install ──────────────────────────────────────────────

    def _install_flow(self) -> None:
        selected_targets = self._select_targets()
        if not selected_targets:
            return

        selected_modules = self._select_modules(selected_targets)
        if not selected_modules:
            return

        plan_data = self._build_plan(selected_targets, selected_modules)
        real = [a for a in plan_data["actions"] if not isinstance(a, MessageAction)]
        if not real:
            print("\n无需变更，所有选中模块已是最新状态。")
            return

        self._show_plan(plan_data["actions"])

        if self.dry_run:
            print("\n[dry-run] 仅展示计划，不执行变更。")
            return

        if not ui.confirm("\n确认执行以上变更?", default=False):
            print("已取消。")
            return

        self._execute(plan_data)

        backups = [a for a in plan_data["actions"] if isinstance(a, BackupAction)]
        if backups:
            print(f"\n{ui.dim('回滚指令 (如需撤销):')}")
            for ba in backups:
                print(ui.dim(f"  cp {ba.backup} {ba.original}"))

        for t in selected_targets:
            log_action(t, "INSTALL", ", ".join(m.name for m in selected_modules))

        print(f"\n{ui.green('安装完成。')}")

    def _select_targets(self) -> list[Path]:
        choice = ui.choose("--- [1/4] 选择目标平台 ---", [
            ("1", "Claude Code (~/.claude)"),
            ("2", "OpenCode (~/.opencode)"),
            ("3", "Agent Skills (~/.agents)"),
            ("4", "pi (~/.pi/agent)"),
            ("5", "全部"),
        ])
        if choice is None:
            return []
        mapping = {"1": ["claude"], "2": ["opencode"], "3": ["agents"],
                   "4": ["pi"], "5": ["claude", "opencode", "agents", "pi"]}
        keys = mapping.get(choice, [])
        targets = [self.targets[k] for k in keys]
        if self.targets["opencode"] in targets and not self.targets["opencode"].is_dir():
            targets.remove(self.targets["opencode"])
        return targets

    def _select_modules(self, targets: list[Path]) -> list[ModuleInfo]:
        items = []
        defaults = set()
        unavailable = {}

        for mod in self.all_modules:
            if not self._is_applicable(mod, targets):
                continue
            items.append((mod.name, mod.title, mod.risk))
            if mod.risk == "low":
                defaults.add(mod.name)

        if not items:
            print("没有可用的模块。")
            return []

        selected_names = ui.multi_select(
            "--- [2/4] 选择要安装的模块 ---", items, defaults, unavailable)
        return [m for m in self.all_modules if m.name in selected_names]

    def _is_applicable(self, mod: ModuleInfo, targets: list[Path]) -> bool:
        if mod.is_user_level:
            return True
        if mod.targets:
            return any(t.name in mod.targets for t in targets)
        return True

    # ── Plan ─────────────────────────────────────────────────

    def _build_plan(self, targets: list[Path],
                    selected: list[ModuleInfo]) -> dict:
        actions = []
        per_target_data = {}

        for target in targets:
            target_actions = []
            for mod in selected:
                if mod.is_user_level:
                    continue
                if mod.targets and target.name not in mod.targets:
                    continue

                if mod.module_type == "symlink":
                    acts = plan_symlinks(mod.source, target / mod.name, target / "bak")
                    target_actions.extend(acts)
                elif mod.module_type == "file":
                    acts = plan_file(mod.source, target / mod.source.name, target / "bak")
                    target_actions.extend(acts)
                elif mod.module_type == "handler":
                    target_actions.append(MessageAction(description=f"配置 {mod.title}"))

            per_target_data[target] = target_actions
            actions.extend(target_actions)

        # User-level
        for mod in selected:
            if mod.is_user_level:
                target_actions.append(MessageAction(description=f"配置 {mod.title}"))

        return {"actions": actions, "per_target_data": per_target_data, "selected": selected}

    def _show_plan(self, actions: list) -> None:
        print(f"\n{ui.bold('=== 变更计划 ===')}\n")
        symlinks = backups = others = 0
        for a in actions:
            if isinstance(a, SymlinkAction):
                ui.info(f"+ {a.description}"); symlinks += 1
            elif isinstance(a, BackupAction):
                ui.info(f"△ 备份: {a.original.name}"); backups += 1
            elif isinstance(a, MessageAction):
                ui.info(f"  {a.description}")
            else:
                ui.info(f"* {a.description}"); others += 1
        print(f"\n摘要: {symlinks} 个链接, {backups} 个备份, {others} 个其他操作")

    # ── Execute ──────────────────────────────────────────────

    def _execute(self, plan_data: dict) -> None:
        selected = plan_data["selected"]
        undo_stack = UndoStack()

        try:
            for target, target_actions in plan_data["per_target_data"].items():
                if not target_actions:
                    continue
                rel = "~/" + str(target.relative_to(Path.home()))
                print(f"\n--- 安装到 {rel} ---")
                target.mkdir(parents=True, exist_ok=True)
                backup_dir = target / "bak"

                self._migrate_legacy(target, undo_stack)

                # Snapshot settings once
                snap = snapshot_settings(target, backup_dir)

                for mod in selected:
                    if mod.is_user_level:
                        continue
                    if mod.targets and target.name not in mod.targets:
                        continue

                    if mod.module_type in ("symlink", "file"):
                        mod_acts = [a for a in target_actions
                                    if isinstance(a, (SymlinkAction, BackupAction))
                                    and a.description.startswith(mod.name)]
                        execute_actions(mod_acts, backup_dir, undo_stack)
                    elif mod.module_type == "handler":
                        mod.handler.configure(target, self.script_dir)

                restore_or_delete_settings(target, snap, undo_stack)

            # User-level
            for mod in selected:
                if mod.is_user_level:
                    print(f"\n--- {mod.title} ---")
                    mod.handler.configure(Path.home(), self.script_dir)

        except Exception as e:
            ui.error(f"安装失败: {e}")
            print(f"\n{ui.bold('=== 自动回滚 ===')}")
            count = undo_stack.rollback()
            print(f"\n{ui.yellow(f'已回滚 {count} 个操作。')}" if count
                  else "\n没有需要回滚的操作。")
            raise

        undo_stack.clear()

    # ── Uninstall ────────────────────────────────────────────

    def _uninstall_flow(self) -> None:
        choice = ui.choose("选择要卸载的目标:", [
            ("1", "~/.claude"), ("2", "~/.opencode"),
            ("3", "~/.agents"), ("4", "~/.pi/agent"), ("5", "全部"),
        ])
        if choice is None:
            return
        mapping = {"1": ["claude"], "2": ["opencode"], "3": ["agents"],
                   "4": ["pi"], "5": ["claude", "opencode", "agents", "pi"]}
        keys = mapping.get(choice, [])

        if not self.dry_run and not ui.confirm("确认卸载?", default=False):
            print("已取消。")
            return

        # User-level first
        for mod in self.all_modules:
            if mod.is_user_level and hasattr(mod.handler, "unconfigure"):
                if self.dry_run:
                    ui.info(f"[dry-run] 将卸载 {mod.title}")
                else:
                    mod.handler.unconfigure(Path.home(), self.script_dir)
                break

        for key in keys:
            target = self.targets[key]
            if key == "opencode" and not target.is_dir():
                continue
            rel = "~/" + str(target.relative_to(Path.home()))
            print(f"\n--- 从 {rel} 卸载 ---")

            for mod in self.all_modules:
                if mod.is_user_level:
                    continue
                if mod.targets and target.name not in mod.targets:
                    continue
                if not self.dry_run:
                    if mod.handler:
                        mod.handler.unconfigure(target, self.script_dir)
                    else:
                        # Symlink: remove our symlinks
                        self._uninstall_symlinks(mod, target)

        if not self.dry_run:
            for key in keys:
                log_action(self.targets[key], "UNINSTALL", "all")
            print(f"\n{ui.green('卸载完成。')}")

    def _uninstall_symlinks(self, mod: ModuleInfo, target: Path) -> None:
        if mod.module_type == "symlink" and mod.source and mod.source.is_dir():
            dest_dir = target / mod.name
            for child in sorted(mod.source.iterdir()):
                dest = dest_dir / child.name
                if dest.is_symlink() and is_our_symlink(dest, child):
                    dest.unlink()
                    ui.info(f"移除: {dest.name}")

    # ── Legacy migration ─────────────────────────────────────

    def _migrate_legacy(self, target: Path, undo_stack: UndoStack) -> None:
        migrated = 0
        for item_name in ("skills", "agents", "commands", "hooks", "custom-tools"):
            item_path = target / item_name
            if not item_path.is_symlink() or not item_path.is_dir():
                continue
            source_dir = self.script_dir / item_name
            if not source_dir.is_dir():
                continue
            ui.info(f"迁移老安装: {item_name}")
            old_target = str(item_path.resolve())
            undo_stack.push(f"恢复老安装 {item_name}",
                            lambda p=item_path, r=old_target: (
                                shutil.rmtree(str(p)) if p.is_dir() else p.unlink(missing_ok=True),
                                p.symlink_to(r))[-1])
            item_path.unlink()
            item_path.mkdir(parents=True, exist_ok=True)
            for child in sorted(source_dir.iterdir()):
                if child.exists() and child.name not in {"__pycache__", ".DS_Store", ".git"}:
                    (item_path / child.name).symlink_to(child)
            migrated += 1
        if migrated:
            ui.success(f"已迁移 {migrated} 个目录从老安装方式")
```

- [ ] **Step 2: 更新 `installer/__init__.py`**

```python
"""Claude Code Tool Installer — Python 版本"""

from .core import Installer
```

- [ ] **Step 3: 验证完整导入**

Run: `cd claude-code-tool && python3 -c "from installer.core import Installer; print('✓ OK')"`
Expected: `✓ OK`

- [ ] **Step 4: Commit**

```bash
git add claude-code-tool/installer/core.py claude-code-tool/installer/__init__.py
git commit -m "refactor(claude-code): 重写 core.py 调用 registry+engine

- 从 discover_all() 获取模块列表
- plan/execute 分离
- UndoStack 回滚保留
- settings.json snapshot 保留"
```

---

### Task 10: 删除旧 `modules.py` + 最终验证

**Files:**
- Delete: `claude-code-tool/installer/modules.py`

- [ ] **Step 1: 删除 modules.py**

```bash
rm claude-code-tool/installer/modules.py
```

- [ ] **Step 2: 验证 install.py 入口仍可用**

Run: `cd claude-code-tool && python3 -c "from installer.core import Installer; from pathlib import Path; i = Installer(Path('.')); print(f'Modules: {len(i.all_modules)}')"`
Expected: `Modules: <数字>` (目录数 + 7 个 handler)

- [ ] **Step 3: 验证完整导入链**

Run: `cd claude-code-tool && python3 -c "
from installer.registry import discover_all
from installer.engine import UndoStack, plan_symlinks
from pathlib import Path
ms = discover_all(Path('.'))
for m in ms:
    print(f'  {m.name:20s} type={m.module_type:15s} risk={m.risk}')
print(f'Total: {len(ms)} modules')
"`
Expected: 列出所有模块

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(claude-code): 删除旧 modules.py，重构完成

旧: modules.py 819行 13个类
新: registry.py + engine.py + 7个handler = ~800行
新增模块 = 创建目录或创建 handler 文件，框架零改动"
```

---

## Self-Review

### Spec Coverage Check

| Spec 要求 | 对应 Task |
|-----------|-----------|
| 模块头部 `@name/@title/@category/@weight` | Task 2 |
| 发现引擎 `load_and_discover_modules` | Task 1 |
| 拓扑排序 `_topo_sort` | Task 1 |
| 两级菜单 `draw_main_menu` + `draw_category_menu` | Task 3 |
| 基础功能默认全选 | Task 3 (draw_category_menu) |
| `run_module` 用 `_R_FILE` | Task 3 |
| `run_auto_mode` 用 `_REG` | Task 4 |
| `--only` 依赖解析 | Task 1 (resolve_deps_for_modules) |
| 一键配置 checklist | Task 3 (draw_run_all_menu) |
| 文件名去编号 | Task 2 |
| claude-code 目录即模块 | Task 6 (registry.py) |
| claude-code handler 插件 | Task 8 |
| claude-code plan/execute 分离 | Task 7 + Task 9 |
| claude-code UndoStack 保留 | Task 7 |
| 删除旧 modules.py | Task 10 |

### Placeholder Scan

No TBD/TODO found. All steps contain complete code.

### Type Consistency

- `_REG` array of strings → consumed by `for name in "${_REG[@]}"`
- `_R_FILE` associative array name→path → consumed by `local file="${_R_FILE[$name]}"`
- `ModuleInfo` dataclass → consumed by `mod.name`, `mod.handler.configure()`, `mod.module_type`
- Handler modules export `TITLE`, `RISK`, `TARGETS`, `configure()`, `unconfigure()` → consistent across all 7 handlers
