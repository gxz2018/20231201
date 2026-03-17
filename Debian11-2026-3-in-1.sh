#!/bin/bash
#============================================================#
#   SSR + IP 盾构机 全功能完美版 (Debian 11 适配)              #
#   修复：密码明文显示、JSON粘贴、目录嵌套、OpenSSL兼容性      #
#============================================================#

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ "$EUID" -ne 0 ]] && echo -e "${red}错误: 必须使用 root 运行!${plain}" && exit 1

# --- 核心修复函数：应用到所有模式 ---
apply_debian11_fix() {
    local target_dir=$1
    echo -e "${green}正在为 $target_dir 应用兼容性补丁...${plain}"
    # 1. 修复 OpenSSL 函数名
    sed -i 's/EVP_CIPHER_CTX_cleanup/EVP_CIPHER_CTX_reset/g' ${target_dir}/shadowsocks/crypto/openssl.py 2>/dev/null
    # 2. 修复库文件路径拼接错误 (针对 Debian 11)
    sed -i "s/path = ctypes.util.find_library(name)/path = 'libcrypto.so.1.1'/g" ${target_dir}/shadowsocks/crypto/util.py 2>/dev/null
    # 3. 确保目录结构正确
    if [ ! -f "${target_dir}/server.py" ]; then
        cp ${target_dir}/shadowsocks/server.py ${target_dir}/ 2>/dev/null
    fi
}

# --- 1. SSR 独立模式 ---
install_standalone() {
    apt-get update && apt-get install -y python3 wget tar libsodium-dev openssl
    rm -rf /usr/local/shadowsocks-standalone && mkdir -p /usr/local/shadowsocks-standalone
    cd /tmp && wget -q -O ssr.tar.gz https://github.com/shadowsocksrr/shadowsocksr/archive/3.2.2.tar.gz
    tar -zxf ssr.tar.gz
    cp -r shadowsocksr-3.2.2/shadowsocks /usr/local/shadowsocks-standalone/
    
    apply_debian11_fix "/usr/local/shadowsocks-standalone"

    echo -e "\n${yellow}请在下方粘贴您的 JSON 配置内容 (右键粘贴后按 Ctrl+D 结束)：${plain}"
    cat > /etc/shadowsocks-standalone.json

    cat > /etc/systemd/system/ssr-standalone.service <<EOF
[Unit]
Description=SSR Standalone
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/shadowsocks-standalone
ExecStart=/usr/bin/python3 /usr/local/shadowsocks-standalone/server.py -c /etc/shadowsocks-standalone.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable ssr-standalone && systemctl restart ssr-standalone
    echo -e "${green}独立模式已启动。${plain}"
    read -p "按 Enter 返回..." && show_menu
}

# --- 2. SSR 面板模式 ---
install_panel() {
    echo -e "${green}正在安装面板模式依赖...${plain}"
    apt-get update && apt-get install -y git python3 python3-pip supervisor libsodium-dev
    pip3 install cymysql pycryptodome requests -q

    read -p "MySQL 地址: " mysqla
    read -p "MySQL 用户名: " mysqlu
    # 关键修改：去掉 -s 参数，使密码输入可见
    read -p "MySQL 密码: " mysqlp
    read -p "数据库名: " mysqld
    read -p "节点 ID: " node

    cd /home
    rm -rf shadowsocksr
    git clone -q https://github.com/gxz2018/shadowsocksr-backup.git shadowsocksr
    cd shadowsocksr
    bash initcfg.sh >/dev/null 2>&1

    # 配置数据库
    sed -i 's/sspanelv2/glzjinmod/g' userapiconfig.py
    sed -i "s/127.0.0.1/$mysqla/g" usermysql.json
    sed -i "s/\"user\": \"ss\"/\"user\": \"$mysqlu\"/g" usermysql.json
    sed -i "s/\"password\": \"pass\"/\"password\": \"$mysqlp\"/g" usermysql.json
    sed -i "s/\"db\": \"sspanel\"/\"db\": \"$mysqld\"/g" usermysql.json
    sed -i "s/\"node_id\": 0/\"node_id\": $node/g" usermysql.json

    # 应用 Debian 11 补丁
    apply_debian11_fix "/home/shadowsocksr"

    # 配置 Supervisor
    cat > /etc/supervisor/conf.d/ssr-panel.conf <<EOF
[program:ssr-panel]
command=python3 /home/shadowsocksr/server.py
directory=/home/shadowsocksr
autostart=true
autorestart=true
user=root
stdout_logfile=/var/log/ssr-panel.log
EOF
    systemctl restart supervisor
    sleep 2 && supervisorctl update && supervisorctl start ssr-panel
    echo -e "${green}面板模式已启动。${plain}"
    read -p "按 Enter 返回..." && show_menu
}

# --- 3. IP 落地机初始化 ---
ip_init() {
    wget -q http://eltty.elttycn.com/gost -O /usr/bin/gost
    wget -q http://eltty.elttycn.com/iptables_gost -O /usr/bin/iptables_gost
    chmod +x /usr/bin/gost /usr/bin/iptables_gost
    echo -e "${green}落地机组件已就位。${plain}"
    read -p "按 Enter 返回..." && show_menu
}

# --- 主菜单 ---
show_menu() {
    clear
    echo -e "${green}=== SSR + IP 盾构机 修正版 ===${plain}"
    echo "1. SSR 独立模式 (JSON粘贴)"
    echo "2. SSR 面板模式 (密码可见 + 自动补丁)"
    echo "3. IP 落地机初始化"
    echo "4. 卸载所有"
    echo "0. 退出"
    read -p "请选择: " choice
    case "$choice" in
        1) install_standalone ;;
        2) install_panel ;;
        3) ip_init ;;
        4) systemctl stop ssr-standalone; supervisorctl stop ssr-panel; echo "已卸载";;
        0) exit 0 ;;
        *) show_menu ;;
    esac
}

show_menu
