#!/bin/bash

get_pip() {
    if command -v pip3 &> /dev/null; then
        pip3
    elif command -v pip &> /dev/null; then
        pip
    elif command -v python3 &> /dev/null; then
        python3 -m pip
    elif command -v python &> /dev/null; then
        python -m pip
    else
        echo "错误: 未找到 pip" >&2
        exit 1
    fi
}

$(get_pip) install rope
