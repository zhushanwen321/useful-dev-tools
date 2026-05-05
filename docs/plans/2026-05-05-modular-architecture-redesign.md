# debian-init-tool & claude-code-tool 架构重构设计

> 日期：2026-05-05
> 状态：已确认，待实施

## 目标

**加一个功能 = 加一个文件，框架代码零改动。**

两个产品统一采用「自描述模块 + 自动发现」架构，消除所有硬编码注册。

## 痛点

| 痛点 | 原因 |
|------|------|
| 加模块要改 4 个文件，漏改出 bug | 模块元数据散落在 3 个文件的 4 个位置 |
| 代码太长难读，改一处怕牵连 | 13 个类大量重复逻辑（5 个 SymlinkModule 几乎相同） |
| 模块间不隔离 | bash source 共享作用域，Python 类继承层次深 |
| 复杂功能没有二级页面 | debian-init 所有模块平铺，claude-code 缺少精细控制 |

## 设计原则

1. **框架不认识任何具体模块**，它只认识一种约定
2. **文件即注册表**：每个模块文件自描述元数据
3. **目录即模块**（claude-code-tool）：源目录自动发现，零配置 symlink
4. **Handler 插件**（claude-code-tool）：需要代码逻辑的场景，drop-in Python 文件
5. **隔离性**：模块间不共享可变状态，失败不影响其他模块

---

## 一、debian-init-tool 重构

### 1.1 模块文件约定

每个模块文件头部用注释声明元数据：

```bash
#!/bin/bash
# @name nodejs
# @title Node.js / npm 配置
# @category dev-tools
# @weight 40
# @deps apt

configure_nodejs() {
    # 原有逻辑不变
    ...
}
```

**字段说明：**

| 字段 | 必填 | 含义 |
|------|------|------|
| `@name` | ✅ | 模块唯一标识，对应 `configure_<name>` 函数名 |
| `@title` | ✅ | 菜单显示文字 |
| `@category` | ✅ | 分类：`system` / `base-tools` / `dev-tools` |
| `@weight` | ❌ | 同类内排序，默认 99，数字越小越靠前 |
| `@deps` | ❌ | 依赖的其他模块名，逗号分隔 |

### 1.2 分类与模块归属

**三个固定分类**（框架里硬编码分类名和显示顺序）：

```bash
CATEGORIES=("system" "base-tools" "dev-tools")
CATEGORY_TITLES=(
    ["system"]="基础功能"
    ["base-tools"]="基础工具"
    ["dev-tools"]="编程工具"
)
```

**模块归属与排序：**

```
模块                    @category    @weight
────────────────────────────────────────────
preflight.sh            system       0
apt.sh                  system       1
locale.sh               system       2
timezone.sh             system       3
ssh.sh                  system       4
firewall.sh             system       5
fail2ban.sh             system       6
user.sh                 system       7
bash.sh                 base-tools   10
zsh.sh                  base-tools   11
fish.sh                 base-tools   12
docker.sh               base-tools   20
podman.sh               base-tools   21
gh.sh                   base-tools   30
pi.sh                   base-tools   31
nodejs.sh               dev-tools    40
```

weight 间隔 10，方便未来插入新模块。

**基础功能分类行为**：默认全选，用户可取消勾选。

### 1.3 发现引擎

新增 `lib/registry.sh`（~70 行）：

```bash
declare -a _REG=()              # 按 weight+deps 排序的模块名
declare -A _R_TITLE=()
declare -A _R_WEIGHT=()
declare -A _R_CATEGORY=()
declare -A _R_DEPS=()
declare -A _R_FILE=()

load_and_discover_modules() {
    for f in "${SCRIPT_DIR}/modules/"*.sh; do
        source "$f"              # 一次性加载函数定义
        _parse_meta "$f"         # 解析 @name/@title/@category...
    done
    _topo_sort                   # 按 deps 拓扑排序
}

_parse_meta() {
    local f="$1"
    local name="" title="" weight=99 category="" deps=""
    while IFS= read -r line; do
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
        [[ ${#remaining[@]} -eq ${#next_round[@]} ]] && break
    done
    _REG=("${sorted[@]}" "${remaining[@]+"${remaining[@]}"}")
}
```

### 1.4 两级菜单

**主菜单**（动态生成）：

```
┌─────────── Debian 系统初始化配置工具 ───────────┐
│                                                  │
│  选择要配置的类别:                                │
│                                                  │
│  1)   基础功能 (0/8 完成)                        │
│  2)   基础工具 (0/6 完成)                        │
│  3)   编程工具 (0/1 完成)                        │
│  4)   一键配置所有                               │
│  5)   查看日志                                   │
│  6)   退出                                       │
│                                                  │
└──────────────────────────────────────────────────┘
```

```bash
draw_main_menu() {
    while true; do
        local options=()
        for cat in "${CATEGORIES[@]}"; do
            local title="${CATEGORY_TITLES[$cat]}"
            local done=$(count_completed_in_category "$cat")
            local total=$(count_in_category "$cat")
            options+=("$cat" "$(cat_status $cat) ${title} (${done}/${total})")
        done
        options+=("all" "一键配置所有")
        options+=("log" "查看日志")
        options+=("exit" "退出")

        local choice
        choice=$(draw_menu "Debian 系统初始化" "选择类别:" "${options[@]}")

        case "$choice" in
            exit)  return 0 ;;
            all)   run_all_modules ;;
            log)   show_log_viewer ;;
            *)     draw_category_menu "$choice" ;;
        esac
    done
}
```

**二级菜单**（按分类过滤）：

```bash
draw_category_menu() {
    local category="$1"
    local title="${CATEGORY_TITLES[$category]}"

    local modules=()
    for name in "${_REG[@]}"; do
        [[ "${_R_CATEGORY[$name]}" == "$category" ]] && modules+=("$name")
    done

    local options=()
    for name in "${modules[@]}"; do
        local status="OFF"
        is_completed "$name" && status="ON"
        [[ "$category" == "system" ]] && status="ON"  # 基础功能默认全选
        options+=("$name" "${_R_TITLE[$name]}" "$status")
    done

    local choices
    choices=$(draw_checklist "$title" "选择要配置的模块:" "${options[@]}")
    [[ $? -ne 0 ]] && return

    for name in $choices; do
        run_module "$name"
    done
}
```

**一键配置所有**：弹出包含全部模块的 checklist，用户确认后执行。

```bash
run_all_modules() {
    local options=()
    for name in "${_REG[@]}"; do
        local status="OFF"
        is_completed "$name" && status="ON"
        options+=("$name" "${_R_TITLE[$name]}" "$status")
    done

    local choices
    choices=$(draw_checklist "一键配置" "选择要配置的模块:" "${options[@]}")
    [[ $? -ne 0 ]] && return

    for name in $choices; do
        run_module "$name"
    done
}
```

### 1.5 模块执行

```bash
run_module() {
    local name
    name=$(strip_ansi "$1")
    local file="${_R_FILE[$name]}"

    if [[ ! -f "$file" ]]; then
        draw_msgbox "错误" "找不到模块: $name"
        return 1
    fi

    local old_opts=$(set +o)

    source "$file"

    if declare -f "configure_$name" &>/dev/null; then
        "configure_$name"
        local ret=$?
    else
        draw_msgbox "错误" "模块 $name 缺少 configure_$name 函数"
        local ret=1
    fi

    eval "$old_opts"

    if [[ $ret -eq 0 ]]; then
        mark_completed "$name"
        draw_msgbox "成功" "${_R_TITLE[$name]} 配置完成"
    else
        draw_msgbox "错误" "${_R_TITLE[$name]} 配置失败"
    fi
    return $ret
}
```

### 1.6 自动模式

`--auto` 行为不变：全部模块按 `_REG` 顺序依次执行。

`--only nodejs` 时，engine 发现 `nodejs` deps `apt`，自动把 `apt` 插到前面。

```bash
run_auto_mode() {
    for name in "${_REG[@]}"; do
        run_module_cli "$name"
    done
}
```

### 1.7 文件名去编号

```
改前                              改后
00_preflight.sh          →       preflight.sh
01_apt.sh                →       apt.sh
02_locale.sh             →       locale.sh
03_timezone.sh           →       timezone.sh
04_ssh.sh                →       ssh.sh
05_firewall.sh           →       firewall.sh
06_fail2ban.sh           →       fail2ban.sh
07_user.sh               →       user.sh
08_bash.sh               →       bash.sh
09_zsh.sh                →       zsh.sh
10_fish.sh               →       fish.sh
10_docker.sh             →       docker.sh
11_podman.sh             →       podman.sh
13_gh.sh                 →       gh.sh
14_pi.sh                 →       pi.sh
12_nodejs.sh             →       nodejs.sh
```

### 1.8 改动清单

| 操作 | 文件 | 内容 |
|------|------|------|
| 新增 | `lib/registry.sh` | ~70 行，发现引擎 |
| 修改 | `lib/ui.sh` | 删 `get_module_index`、硬编码菜单；改 `draw_main_menu` 为两级菜单；改 `run_module`/`run_module_silent` 用 `_R_FILE` |
| 修改 | `debian-init.sh` | `main()` 里 source `registry.sh`，`load_modules` → `load_and_discover_modules`，`run_auto_mode` 用 `_REG` |
| 修改 | 16 个模块文件 | 每个加 4-5 行 `@name/@title/@category/@weight` 头部 |
| 重命名 | 16 个模块文件 | 去掉编号前缀 |
| 删除 | — | `get_module_index` 函数、4 处硬编码模块列表 |

---

## 二、claude-code-tool 重构

### 2.1 两层发现

```
第一层：目录即模块（覆盖 80% 场景）
  script_dir 下的目录 → 自动逐项 symlink
  无需任何配置

第二层：Handler 插件（覆盖 20% 需要逻辑的场景）
  handlers/*.py → 自动加载
  每个 handler 导出固定接口
```

### 2.2 Handler 约定接口

```python
# handlers/xxx.py

TITLE = "模块标题"
RISK = "low"
TARGETS = []           # 空=所有 target，[".claude", ".opencode"]=指定 target

def configure(target: Path, script_dir: Path) -> bool:
    """安装。返回 True=成功"""
    ...

def unconfigure(target: Path, script_dir: Path = None) -> None:
    """卸载"""
    ...
```

### 2.3 新文件结构

```
claude-code-tool/
  install.py                 (入口，不变)
  installer/
    __init__.py
    registry.py              (~80行) 自动发现引擎
    engine.py                (~250行) 通用执行 + UndoStack + Action
    handlers/
      statusline.py          (~30行)
      skill_inject.py        (~40行)
      knowledge_engine.py    (~80行)
      tavily_cli.py          (~50行)
      pi_skills.py           (~25行)
      pi_agents.py           (~30行)
      pi_statusline.py       (~25行)
    ui.py                    (不变)
    utils.py                 (不变)
```

### 2.4 发现引擎

```python
# registry.py

def discover_all(script_dir):
    modules = []

    # 第一层：目录即 symlink 模块
    for child in sorted(script_dir.iterdir()):
        if child.is_dir() and child.name not in EXCLUDE:
            modules.append(SymlinkModule(child.name, child))
        elif child.is_file() and child.suffix in ('.md',):
            modules.append(FileModule(child.stem, child))

    # 第二层：Handler 插件
    handler_dir = Path(__file__).parent / "handlers"
    for py in sorted(handler_dir.glob("*.py")):
        if py.name.startswith("_"):
            continue
        mod = importlib.import_module(f".handlers.{py.stem}", package="installer")
        modules.append(HandlerModule(py.stem, mod))

    return modules
```

### 2.5 通用执行引擎

保留 plan/execute 两阶段分离：

```
discover → plan (dry-run 可选) → 用户确认 → execute → undo on failure
```

保留 UndoStack 回滚机制和 settings.json snapshot。

### 2.6 Handler 列表

| Handler | 复杂度 | 特殊逻辑 |
|---------|--------|---------|
| statusline.py | 简单 | 编辑 settings.json |
| skill_inject.py | 简单 | 编辑 settings.json hooks |
| knowledge_engine.py | 复杂 | bun install、hooks、crontab、marker 文件 |
| tavily_cli.py | 中等 | 用户级部署、pip install、wrapper 脚本 |
| pi_skills.py | 简单 | 特殊路径映射 ~/.pi/agent/skills/ |
| pi_agents.py | 简单 | 目录→单文件映射 ~/.pi/agent/agents/*.md |
| pi_statusline.py | 简单 | 跨目录映射 ~/.pi/agent/extensions/statusline/ |

### 2.7 改动清单

| 操作 | 文件 | 内容 |
|------|------|------|
| 新增 | `installer/registry.py` | ~80 行，目录发现 + handler 加载 |
| 新增 | `installer/engine.py` | ~250 行，通用 Action 执行 + UndoStack |
| 新增 | `installer/handlers/*.py` | 7 个 handler 文件，共 ~280 行 |
| 重写 | `installer/core.py` | ~200 行，调用 registry+engine |
| 删除 | `installer/modules.py` | 819 行（被 registry+engine+handlers 替代） |

### 2.8 行数对比

| | 改前 | 改后 |
|---|---|---|
| 总行数 | ~1414 行 | ~1000 行 |
| 模块定义 | 819 行，13 个类 | ~360 行（registry+handlers） |
| 新增模块 | 创建新类或修改 registry dict | 创建目录或创建 handler 文件 |

---

## 三、新增功能流程

### debian-init-tool 加一个新模块

```
1. 创建 modules/xxx.sh
2. 写 @name/@title/@category/@weight 头部
3. 实现 configure_xxx() 函数
4. 完成。框架自动发现。
```

### claude-code-tool 加一个新功能

**纯 symlink（如 `prompts/` 目录）：**
```
1. 创建 claude-code-tool/prompts/ 目录，放入文件
2. 完成。引擎自动发现并 symlink。
```

**需要代码逻辑（如 `mcp-servers` handler）：**
```
1. 创建 installer/handlers/mcp_servers.py
2. 声明 TITLE/RISK/TARGETS
3. 实现 configure() + unconfigure()
4. 完成。引擎自动加载。
```

---

## 四、实施顺序

### 第一步：debian-init-tool（优先）

1. 创建 `lib/registry.sh`
2. 给 16 个模块加头部 + 重命名去编号
3. 改 `lib/ui.sh`（删 `get_module_index`，改主菜单为两级，改 `run_module`）
4. 改 `debian-init.sh`（`load_and_discover_modules`）
5. 测试：`--dry-run`、`--auto`、交互模式

### 第二步：claude-code-tool

1. 创建 `registry.py`（目录发现 + handler 加载）
2. 创建 `engine.py`（通用 Action 执行 + UndoStack）
3. 拆 `modules.py` → `handlers/` 目录
4. 重写 `core.py`
5. 删除 `modules.py`
6. 测试完整安装/卸载流程
