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
declare -a _REG=()
declare -A _R_TITLE=()
declare -A _R_WEIGHT=()
declare -A _R_CATEGORY=()
declare -A _R_DEPS=()
declare -A _R_FILE=()

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

_in_array() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
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
        [[ ${#remaining[@]} -eq ${#next_round[@]} ]] && break
    done
    _REG=("${sorted[@]}" "${remaining[@]+"${remaining[@]}"}")
}

get_modules_by_category() {
    local category="$1"
    local result=()
    for name in "${_REG[@]}"; do
        [[ "${_R_CATEGORY[$name]}" == "$category" ]] && result+=("$name")
    done
    printf '%s\n' "${result[@]}"
}

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

resolve_deps_for_modules() {
    local -n _result="$1"
    shift
    local requested=("$@")
    local result_map=()
    for name in "${requested[@]}"; do
        _add_with_deps "$name" result_map
    done
    for name in "${_REG[@]}"; do
        if _in_array "$name" "${result_map[@]+"${result_map[@]}"}"; then
            _result+=("$name")
        fi
    done
}

_add_with_deps() {
    local name="$1"
    local -n _map="$2"
    _in_array "$name" "${_map[@]+"${_map[@]}"}" && return
    local deps="${_R_DEPS[$name]:-}"
    for dep in ${deps//,/ }; do
        [[ -z "$dep" ]] && continue
        _add_with_deps "$dep" _map
    done
    _map+=("$name")
}

_REGISTRY_SH_LOADED=true
