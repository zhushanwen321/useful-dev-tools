#!/bin/bash

set -e

# 显示主菜单并获取用户选择
display_menu() {
    echo "===================================="
    echo "Podman容器开机自启管理脚本"
    echo "===================================="
    echo ""
    echo "请选择操作:"
    echo "1. 添加容器到开机自启"
    echo "2. 列出并移除已设置的开机自启容器"
    echo "3. 退出"
    echo ""
    read -r -p "请输入选项编号: " menu_option
    echo ""
    # 直接返回用户输入
    echo "$menu_option"
}

# 列出所有容器并让用户选择
select_container() {
    echo "正在获取容器列表..."
    echo ""

    containers=$(podman ps -a --format "{{.Names}} {{.ID}} {{.Image}}" 2>/dev/null)

    if [ -z "$containers" ]; then
        echo "错误: 未找到任何podman容器"
        return 1
    fi

    # 显示容器列表并让用户选择
    echo "可用容器列表:"
    echo ""

    # 转换为数组并显示
    container_array=($(echo "$containers" | tr '\n' ' '))
    container_count=0

    for ((i=0; i<${#container_array[@]}; i+=3)); do
        container_count=$((container_count + 1))
        name=${container_array[$i]}
        id=${container_array[$i+1]}
        image=${container_array[$i+2]}
        echo "$container_count. 名称: $name"
        echo "   ID: $id"
        echo "   镜像: $image"
        echo ""
    done

    # 让用户选择
    echo "请输入要设置开机自启的容器编号:"
    read -r container_number

    # 验证输入
    if ! [[ "$container_number" =~ ^[0-9]+$ ]] || [ "$container_number" -lt 1 ] || [ "$container_number" -gt "$container_count" ]; then
        echo "错误: 无效的容器编号"
        return 1
    fi

    # 获取选中的容器名称
    selected_index=$(( (container_number - 1) * 3 ))
    selected_container=${container_array[$selected_index]}

    echo ""
    echo "===================================="
    echo "您选择了容器: $selected_container"
    echo "===================================="
    echo ""

    return 0
}

# 添加容器到开机自启
add_autostart() {
    if ! select_container; then
        return 1
    fi

    # 1. 生成服务文件
    echo "1. 生成systemd服务文件..."
    # 尝试使用--new选项，如果失败则去掉该选项
    echo "尝试使用--new选项生成服务文件..."
    if podman generate systemd --name "$selected_container" --files --new; then
        echo "成功生成服务文件（使用--new选项）"
    else
        echo "警告: --new选项失败，尝试不使用该选项..."
        podman generate systemd --name "$selected_container" --files
        echo "成功生成服务文件（不使用--new选项）"
    fi

    # 2. 移动并启用服务
    echo ""
    echo "2. 移动服务文件到用户systemd目录..."
    mkdir -p ~/.config/systemd/user/

    # 查找生成的服务文件
    service_file=$(ls -1 container-*.service 2>/dev/null | head -1)
    if [ -z "$service_file" ]; then
        echo "错误: 未找到生成的服务文件"
        return 1
    fi

    echo "找到服务文件: $service_file"
    mv "$service_file" ~/.config/systemd/user/
    # 记录实际的服务文件名
    service_file_name=$(basename "$service_file")

    echo ""
    echo "3. 重新加载用户systemd配置..."
    systemctl --user daemon-reload

    echo ""
    echo "4. 启用服务，使其在登录后自动启动..."
    systemctl --user enable "$service_file_name"

    echo ""
    echo "5. 立即启动该服务进行测试..."
    systemctl --user start "$service_file_name"

    echo ""
    echo "6. 启用用户级服务开机自启（无需登录）..."
    sudo loginctl enable-linger "$USER"

    echo ""
    echo "===================================="
    echo "操作完成!"
    echo "===================================="
    echo "容器 $selected_container 已设置为开机自启"
    echo ""
    echo "服务文件路径: ~/.config/systemd/user/$service_file_name"
    echo ""
    echo "验证服务状态:"
    systemctl --user status "$service_file_name"
    echo ""
    echo "提示: 如果需要禁用开机自启，可以使用选项2移除"
    echo ""

    return 0
}

# 列出并移除已设置的开机自启容器
remove_autostart() {
    echo "===================================="
    echo "移除容器开机自启设置"
    echo "===================================="
    echo ""

    # 查找用户systemd目录中的container服务文件
    systemd_dir="~/.config/systemd/user/"
    expanded_dir=$(eval echo "$systemd_dir")

    if [ ! -d "$expanded_dir" ]; then
        echo "错误: 用户systemd目录不存在"
        return 1
    fi

    # 列出所有container服务文件
    service_files=($(ls -1 "$expanded_dir"container-*.service 2>/dev/null))

    if [ ${#service_files[@]} -eq 0 ]; then
        echo "未找到任何已设置开机自启的podman容器"
        return 1
    fi

    # 显示已设置的容器列表
    echo "已设置开机自启的容器列表:"
    echo ""

    service_count=0
    for service_file in "${service_files[@]}"; do
        service_count=$((service_count + 1))
        # 提取容器名称
        service_file_name=$(basename "$service_file")
        container_name=$(echo "$service_file_name" | sed 's/^container-//;s/\.service$//')
        
        # 获取服务状态
        status=$(systemctl --user is-enabled "$service_file_name" 2>/dev/null || echo "unknown")
        
        echo "$service_count. 容器: $container_name"
        echo "   服务文件: $service_file_name"
        echo "   状态: $status"
        echo ""
    done

    # 让用户选择要移除的容器
    echo "请输入要移除开机自启的容器编号:"
    read -r remove_number

    # 验证输入
    if ! [[ "$remove_number" =~ ^[0-9]+$ ]] || [ "$remove_number" -lt 1 ] || [ "$remove_number" -gt "$service_count" ]; then
        echo "错误: 无效的容器编号"
        return 1
    fi

    # 获取选中的服务文件
    selected_service_file=${service_files[$((remove_number - 1))]}
    selected_service_name=$(basename "$selected_service_file")
    selected_container=$(echo "$selected_service_name" | sed 's/^container-//;s/\.service$//')

    echo ""
    echo "===================================="
    echo "您选择了移除容器: $selected_container"
    echo "===================================="
    echo ""

    # 停止并禁用服务
    echo "1. 停止服务..."
    systemctl --user stop "$selected_service_name" 2>/dev/null || echo "服务已停止"

    echo ""
    echo "2. 禁用服务..."
    systemctl --user disable "$selected_service_name"

    echo ""
    echo "3. 删除服务文件..."
    rm "$selected_service_file"

    echo ""
    echo "4. 重新加载用户systemd配置..."
    systemctl --user daemon-reload

    echo ""
    echo "===================================="
    echo "操作完成!"
    echo "===================================="
    echo "容器 $selected_container 已从开机自启中移除"
    echo ""
    echo "提示: 如果需要重新添加该容器到开机自启，可以使用选项1"
    echo ""

    return 0
}

# 主程序
main() {
    # 检查podman是否安装
    if ! command -v podman &> /dev/null; then
        echo "错误: podman 未安装，请先安装podman"
        exit 1
    fi

    while true; do
        # 显示主菜单
        echo "===================================="
        echo "Podman容器开机自启管理脚本"
        echo "===================================="
        echo ""
        echo "请选择操作:"
        echo "1. 添加容器到开机自启"
        echo "2. 列出并移除已设置的开机自启容器"
        echo "3. 退出"
        echo ""
        read -r -p "请输入选项编号: " menu_option
        echo ""

        case $menu_option in
            1)
                add_autostart
                ;;
            2)
                remove_autostart
                ;;
            3)
                echo "感谢使用，再见!"
                exit 0
                ;;
            *)
                echo "错误: 无效的选项"
                echo ""
                ;;
        esac

        # 询问是否继续
        read -r -p "是否返回主菜单? (y/n): " continue_choice
        echo ""
        if [[ "$continue_choice" != "y" && "$continue_choice" != "Y" ]]; then
            echo "感谢使用，再见!"
            exit 0
        fi
    done
}

# 运行主程序
main
