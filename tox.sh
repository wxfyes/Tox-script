#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}注意： CentOS 7 无法使用hysteria1/2协议！${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

# 检查系统是否有 IPv6 地址
check_ipv6_support() {
    if ip -6 addr | grep -q "inet6"; then
        echo "1"  # 支持 IPv6
    else
        echo "0"  # 不支持 IPv6
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启tox" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/wxfyes/Tox-script/master/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "输入指定版本(默认最新版): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/wxfyes/Tox-script/master/install.sh) $version
    if [[ $? == 0 ]]; then
        echo -e "${green}更新完成，已自动重启 tox，请使用 tox log 查看运行日志${plain}"
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "tox在修改配置后会自动尝试重启"
    vi /etc/tox/config.json
    sleep 2
    restart
    check_status
    case $? in
        0)
            echo -e "tox状态: ${green}已运行${plain}"
            ;;
        1)
            echo -e "检测到您未启动tox或tox自动重启失败，是否查看日志？[Y/n]" && echo
            read -e -rp "(默认: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "tox状态: ${red}未安装${plain}"
    esac
}

uninstall() {
    confirm "确定要卸载 tox 吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        service tox stop
        rc-update del tox
        rm /etc/init.d/tox -f
    else
        systemctl stop tox
        systemctl disable tox
        rm /etc/systemd/system/tox.service -f
        systemctl daemon-reload
        systemctl reset-failed
    fi
    rm /etc/tox/ -rf
    rm /usr/local/tox/ -rf

    echo ""
    echo -e "卸载成功，如果你想删除此脚本，则退出脚本后运行 ${green}rm /usr/bin/tox -f${plain} 进行删除"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}tox已运行，无需再次启动，如需重启请选择重启${plain}"
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service tox start
        else
            systemctl start tox
        fi
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}tox 启动成功，请使用 tox log 查看运行日志${plain}"
        else
            echo -e "${red}tox可能启动失败，请稍后使用 tox log 查看日志信息${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    if [[ x"${release}" == x"alpine" ]]; then
        service tox stop
    else
        systemctl stop tox
    fi
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}tox 停止成功${plain}"
    else
        echo -e "${red}tox停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    if [[ x"${release}" == x"alpine" ]]; then
        service tox restart
    else
        systemctl restart tox
    fi
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}tox 重启成功，请使用 tox log 查看运行日志${plain}"
    else
        echo -e "${red}tox可能启动失败，请稍后使用 tox log 查看日志信息${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    if [[ x"${release}" == x"alpine" ]]; then
        service tox status
    else
        systemctl status tox --no-pager -l
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add tox
    else
        systemctl enable tox
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}tox 设置开机自启成功${plain}"
    else
        echo -e "${red}tox 设置开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del tox
    else
        systemctl disable tox
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}tox 取消开机自启成功${plain}"
    else
        echo -e "${red}tox 取消开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    if [[ x"${release}" == x"alpine" ]]; then
        echo -e "${red}alpine系统暂不支持日志查看${plain}\n" && exit 1
    else
        journalctl -u tox.service -e --no-pager -f
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_bbr() {
    bash <(curl -L -s https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh)
}

update_shell() {
    wget -O /usr/bin/tox -N --no-check-certificate https://raw.githubusercontent.com/wxfyes/Tox-script/master/tox.sh
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/tox
        echo -e "${green}升级脚本成功，请重新运行脚本${plain}" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/tox/tox ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service tox status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        if systemctl is-active --quiet tox; then
            return 0
        else
            return 1
        fi
    fi
}

check_enabled() {
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(rc-update show | grep tox)
        if [[ x"${temp}" == x"" ]]; then
            return 1
        else
            return 0
        fi
    else
        temp=$(systemctl is-enabled tox)
        if [[ x"${temp}" == x"enabled" ]]; then
            return 0
        else
            return 1;
        fi
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}tox已安装，请不要重复安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}请先安装tox${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "tox状态: ${green}已运行${plain}"
            show_enable_status
            ;;
        1)
            echo -e "tox状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "tox状态: ${red}未安装${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

generate_x25519_key() {
    echo -n "正在生成 x25519 密钥："
    /usr/local/tox/tox x25519
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_V2bX_version() {
    echo -n "tox 版本："
    /usr/local/tox/tox version
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

add_node_config() {
    echo -e "${yellow}请选择核心类型 (Tox 双核版)：${plain}"
    echo -e "${green}1. sing-box${plain}"
    echo -e "${green}2. xray${plain}"
    read -rp "请输入 (默认1): " core_type
    case "$core_type" in
        2 ) 
            core="xray"
            has_xray=true
            echo -e "${green}核心类型已设置为: xray${plain}"
            ;;
        * ) 
            core="sing"
            has_sing=true
            echo -e "${green}核心类型已设置为: singbox${plain}"
            ;;
    esac
    while true; do
        read -rp "请输入节点Node ID：" NodeID
        # 判断NodeID是否为正整数
        if [[ "$NodeID" =~ ^[0-9]+$ ]]; then
            break  # 输入正确，退出循环
        else
            echo "错误：请输入正确的数字作为Node ID。"
        fi
    done

    if [ "$core" == "sing" ] || [ "$core" == "xray" ]; then
        echo -e "${yellow}请选择节点传输协议：${plain}"
        echo -e "${green}1. Shadowsocks${plain}"
        echo -e "${green}2. Vless${plain}"
        echo -e "${green}3. Vmess${plain}"
        echo -e "${green}4. Hysteria${plain}"
        echo -e "${green}5. Hysteria2${plain}"
        echo -e "${green}6. Trojan${plain}"  
        echo -e "${green}7. Tuic${plain}"
        echo -e "${green}8. AnyTLS${plain}"
        read -rp "请输入：" NodeType
        case "$NodeType" in
            1 ) NodeType="shadowsocks" ;;
            2 ) NodeType="vless" ;;
            3 ) NodeType="vmess" ;;
            4 ) NodeType="hysteria" ;;
            5 ) NodeType="hysteria2" ;;
            6 ) NodeType="trojan" ;;
            7 ) NodeType="tuic" ;;
            8 ) NodeType="anytls" ;;
            * ) NodeType="shadowsocks" ;;
        esac
    fi
    # 强制 AnyTLS 使用 Sing-box
    if [ "$NodeType" == "anytls" ]; then
        core="sing"
        has_sing=true
    fi
    fastopen=true
    if [ "$NodeType" == "vless" ]; then
        read -rp "请选择是否为reality节点？(y/n)" isreality
    elif [ "$NodeType" == "hysteria" ] || [ "$NodeType" == "hysteria2" ] || [ "$NodeType" == "tuic" ] || [ "$NodeType" == "anytls" ]; then
        fastopen=false
        istls="y"
    fi

    if [[ "$isreality" != "y" && "$isreality" != "Y" &&  "$istls" != "y" ]]; then
        read -rp "请选择是否进行TLS配置？(y/n)" istls
    fi

    certmode="none"
    certdomain="example.com"
    if [[ "$isreality" != "y" && "$isreality" != "Y" && ( "$istls" == "y" || "$istls" == "Y" ) ]]; then
        echo -e "${yellow}请选择证书申请模式：${plain}"
        echo -e "${green}1. http模式自动申请，节点域名已正确解析${plain}"
        echo -e "${green}2. dns模式自动申请，需填入正确域名服务商API参数${plain}"
        echo -e "${green}3. self模式，自签证书或提供已有证书文件${plain}"
        read -rp "请输入：" certmode
        case "$certmode" in
            1 ) certmode="http" ;;
            2 ) certmode="dns" ;;
            3 ) certmode="self" ;;
        esac
        read -rp "请输入节点证书域名(example.com)：" certdomain
        if [ "$certmode" != "http" ]; then
            echo -e "${red}请手动修改配置文件后重启tox！${plain}"
        fi
    fi
    ipv6_support=$(check_ipv6_support)
    listen_ip="0.0.0.0"
    if [ "$ipv6_support" -eq 1 ]; then
        listen_ip="::"
    fi
    node_config=""
    if [ "$core_type" == "2" ] || [ "$core_sing" == true ]; then
    node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "$listen_ip",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "TCPFastOpen": $fastopen,
            "SniffEnabled": true,
            "XrayOptions": {
                "EnableFallback": true,
                "FallBackConfigs": [
                    {
                        "SNI": "",
                        "Dest": "8080",
                        "ProxyProtocolVer": 0
                    }
                ],
                "DisableSniffing": false
            },
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/tox/fullchain.cer",
                "KeyFile": "/etc/tox/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)

    nodes_config+=("$node_config")
    fi
}

generate_config_file() {
    echo -e "${yellow}tox 配置文件生成向导${plain}"
    echo -e "${red}请阅读以下注意事项：${plain}"
    echo -e "${red}1. 目前该功能正处测试阶段${plain}"
    echo -e "${red}2. 生成的配置文件会保存到 /etc/tox/config.json${plain}"
    echo -e "${red}3. 原来的配置文件会保存到 /etc/tox/config.json.bak${plain}"
    echo -e "${red}4. 目前仅部分支持TLS${plain}"
    echo -e "${red}5. 使用此功能生成的配置文件会自带审计，确定继续？(y/n)${plain}"
    read -rp "请输入：" continue_prompt
    if [[ "$continue_prompt" =~ ^[Nn][Oo]? ]]; then
        exit 0
    fi
    
    nodes_config=()
    first_node=true
    has_xray=false
    has_sing=false
    fixed_api_info=false
    check_api=false
    
    while true; do
        if [ "$first_node" = true ]; then
            read -rp "请输入机场网址(https://example.com)：" ApiHost
            read -rp "请输入面板对接API Key：" ApiKey
            read -rp "是否设置固定的机场网址和API Key？(y/n)" fixed_api
            if [ "$fixed_api" = "y" ] || [ "$fixed_api" = "Y" ]; then
                fixed_api_info=true
                echo -e "${red}成功固定地址${plain}"
            fi
            first_node=false
            add_node_config
        else
            read -rp "是否继续添加节点配置？(回车继续，输入n或no退出)" continue_adding_node
            if [[ "$continue_adding_node" =~ ^[Nn][Oo]? ]]; then
                break
            elif [ "$fixed_api_info" = false ]; then
                read -rp "请输入机场网址：" ApiHost
                read -rp "请输入面板对接API Key：" ApiKey
            fi
            add_node_config
        fi
    done

    # 检查并添加xray核心配置
    if [ "$has_xray" = true ]; then
        cores_config+="
    {
        \"Type\": \"xray\",
        \"Log\": {
            \"Level\": \"error\",
            \"Timestamp\": true
        }
    },"
    fi

    # 检查并添加sing核心配置
    if [ "$has_sing" = true ]; then
        cores_config+="
    {
        \"Type\": \"sing\",
        \"Log\": {
            \"Level\": \"error\",
            \"Timestamp\": true
        },
        \"NTP\": {
            \"Enable\": false,
            \"Server\": \"time.apple.com\",
            \"ServerPort\": 0
        },
        \"OriginalPath\": \"/etc/tox/sing_origin.json\"
    },"
    fi

    # 检查并添加hysteria2核心配置


    # 移除最后一个逗号并关闭数组
    cores_config="${cores_config%,}"
    cores_config+="]"

    # 切换到配置文件目录
    mkdir -p /etc/tox
    cd /etc/tox
    
    # 备份旧的配置文件
    mv -f config.json config.json.bak 2>/dev/null
    nodes_config_str=$(printf ",%s" "${nodes_config[@]}")
    formatted_nodes_config="${nodes_config_str:1}"

    # 创建 config.json 文件
    cat <<EOF > /etc/tox/config.json
{
    "Log": {
        "Level": "error",
        "Output": ""
    },
    "Cores": $cores_config,
    "Nodes": [$formatted_nodes_config],
    "DNS": "/etc/tox/dns.json",
    "Routing": "/etc/tox/route.json"
}
EOF
    
    # 创建 custom_outbound.json 文件
    cat <<EOF > /etc/tox/custom_outbound.json
    [
        {
            "tag": "IPv4_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv4v6"
            }
        },
        {
            "tag": "IPv6_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv6"
            }
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
EOF
    
    # 创建 route.json 文件
    cat <<EOF > /etc/tox/route.json
    {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "geoip:private"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "domain": [
                    "regexp:(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
                    "regexp:(.+.|^)(360|so).(cn|com)",
                    "regexp:(Subject|HELO|SMTP)",
                    "regexp:(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
                    "regexp:(^.@)(guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168).(info|biz|com|de|net|org|me|la)",
                    "regexp:(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
                    "regexp:(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
                    "regexp:(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
                    "regexp:(.+.|^)(360).(cn|com|net)",
                    "regexp:(.*.||)(guanjia.qq.com|qqpcmgr|QQPCMGR)",
                    "regexp:(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
                    "regexp:(.*.||)(netvigator|torproject).(com|cn|net|org)",
                    "regexp:(..||)(visa|mycard|gash|beanfun|bank).",
                    "regexp:(.*.||)(gov|12377|12315|talk.news.pts.org|creaders|zhuichaguoji|efcc.org|cyberpolice|aboluowang|tuidang|epochtimes|zhengjian|110.qq|mingjingnews|inmediahk|xinsheng|breakgfw|chengmingmag|jinpianwang|qi-gong|mhradio|edoors|renminbao|soundofhope|xizang-zhiye|bannedbook|ntdtv|12321|secretchina|dajiyuan|boxun|chinadigitaltimes|dwnews|huaglad|oneplusnews|epochweekly|cn.rfi).(cn|com|org|net|club|net|fr|tw|hk|eu|info|me)",
                    "regexp:(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
                    "regexp:(.*.||)(mycard).(com|tw)",
                    "regexp:(.*.||)(gash).(com|tw)",
                    "regexp:(.bank.)",
                    "regexp:(.*.||)(pincong).(rocks)",
                    "regexp:(.*.||)(taobao).(com)",
                    "regexp:(.*.||)(laomoe|jiyou|ssss|lolicp|vv1234|0z|4321q|868123|ksweb|mm126).(com|cloud|fun|cn|gs|xyz|cc)",
                    "regexp:(flows|miaoko).(pages).(dev)"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "127.0.0.1/32",
                    "10.0.0.0/8",
                    "fc00::/7",
                    "fe80::/10",
                    "172.16.0.0/12"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "protocol": [
                    "bittorrent"
                ]
            }
        ]
    }
EOF

    ipv6_support=$(check_ipv6_support)
    dnsstrategy="ipv4_only"
    if [ "$ipv6_support" -eq 1 ]; then
        dnsstrategy="prefer_ipv4"
    fi
    # 创建 sing_origin.json 文件
    cat <<EOF > /etc/tox/sing_origin.json
{
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "https://8.8.8.8/dns-query"
      },
      {
        "tag": "cf",
        "address": "https://1.1.1.1/dns-query"
      },
      {
        "tag": "google-udp",
        "address": "8.8.8.8"
      }
    ],
    "strategy": "$dnsstrategy"
  },
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct",
      "domain_resolver": {
        "server": "google",
        "strategy": "$dnsstrategy"
      }
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "ip_cidr": ["127.0.0.1/32"],
        "outbound": "direct"
      },
      {
        "ip_is_private": true,
        "outbound": "block"
      },
      {
        "domain_regex": [
            "(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
            "(.+.|^)(360|so).(cn|com)",
            "(Subject|HELO|SMTP)",
            "(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
            "(^.@)(guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168).(info|biz|com|de|net|org|me|la)",
            "(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
            "(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
            "(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
            "(.+.|^)(360).(cn|com|net)",
            "(.*.||)(guanjia.qq.com|qqpcmgr|QQPCMGR)",
            "(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
            "(.*.||)(netvigator|torproject).(com|cn|net|org)",
            "(..||)(visa|mycard|gash|beanfun|bank).",
            "(.*.||)(gov|12377|12315|talk.news.pts.org|creaders|zhuichaguoji|efcc.org|cyberpolice|aboluowang|tuidang|epochtimes|zhengjian|110.qq|mingjingnews|inmediahk|xinsheng|breakgfw|chengmingmag|jinpianwang|qi-gong|mhradio|edoors|renminbao|soundofhope|xizang-zhiye|bannedbook|ntdtv|12321|secretchina|dajiyuan|boxun|chinadigitaltimes|dwnews|huaglad|oneplusnews|epochweekly|cn.rfi).(cn|com|org|net|club|net|fr|tw|hk|eu|info|me)",
            "(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
            "(.*.||)(mycard).(com|tw)",
            "(.*.||)(gash).(com|tw)",
            "(.bank.)",
            "(.*.||)(pincong).(rocks)",
            "(.*.||)(taobao).(com)",
            "(.*.||)(laomoe|jiyou|ssss|lolicp|vv1234|0z|4321q|868123|ksweb|mm126).(com|cloud|fun|cn|gs|xyz|cc)",
            "(flows|miaoko).(pages).(dev)"
        ],
        "outbound": "block"
      },
      {
        "outbound": "direct",
        "network": [
          "udp","tcp"
        ]
      }
    ]
  },
  "experimental": {
    "cache_file": {
      "enabled": true
    }
  }
}
EOF

    # 创建 hy2config.yaml 文件           
    cat <<EOF > /etc/tox/hy2config.yaml
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false
ignoreClientBandwidth: false
disableUDP: false
udpIdleTimeout: 60s
resolver:
  type: system
acl:
  inline:
    - direct(geosite:google)
    - reject(geosite:cn)
    - reject(geoip:cn)
masquerade:
  type: 404
EOF
    echo -e "${green}V2bX 配置文件生成完成，正在重新启动 V2bX 服务${plain}"
    restart 0
    before_show_menu
}

# 放开防火墙端口
open_ports() {
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    echo -e "${green}放开防火墙端口成功！${plain}"
}

show_usage() {
    echo "tox 管理脚本使用方法 (兼容使用tox执行，大小写不敏感): "
    echo "------------------------------------------"
    echo "tox              - 显示管理菜单 (功能更多)"
    echo "tox start        - 启动 tox"
    echo "tox stop         - 停止 tox"
    echo "tox restart      - 重启 tox"
    echo "tox status       - 查看 tox 状态"
    echo "tox enable       - 设置 tox 开机自启"
    echo "tox disable      - 取消 tox 开机自启"
    echo "tox log          - 查看 tox 日志"
    echo "tox x25519       - 生成 x25519 密钥"
    echo "tox update       - 更新 tox"
    echo "tox update x.x.x - 更新 tox 指定版本"
    echo "tox install      - 安装 tox"
    echo "tox uninstall    - 卸载 tox"
    echo "tox version      - 查看 tox 版本"
    echo "------------------------------------------"
}


uninstall_nginx() {
    confirm "确定要卸载 Nginx (关闭伪装站) 吗?" "n"
    if [[ $? != 0 ]]; then
        show_menu
        return 0
    fi
    echo -e "${yellow}正在卸载 Nginx...${plain}"
    systemctl stop nginx
    systemctl disable nginx
    if [[ x"${release}" == x"centos" ]]; then
        yum remove nginx -y
    elif [[ x"${release}" == x"ubuntu" || x"${release}" == x"debian" ]]; then
        apt-get remove nginx -y
    elif [[ x"${release}" == x"alpine" ]]; then
        apk del nginx
    fi
    rm -rf /etc/nginx/
    echo -e "${green}Nginx 已卸载${plain}"
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_reset_nginx() {
    confirm "确定要安装/重置 Nginx 为监听 8080 端口吗？(这将覆盖现有 Nginx 配置)" "n"
    if [[ $? != 0 ]]; then
        show_menu
        return 0
    fi
    echo -e "${yellow}正在安装/配置 Nginx...${plain}"
    if [[ x"${release}" == x"centos" ]]; then
        yum install nginx -y
    elif [[ x"${release}" == x"ubuntu" || x"${release}" == x"debian" ]]; then
        apt-get update
        apt-get install nginx -y
    elif [[ x"${release}" == x"alpine" ]]; then
        apk update
        apk add nginx
    fi
    
    if [[ $? != 0 ]]; then
        echo -e "${red}Nginx 安装失败，请检查网络或软件源设置${plain}"
        before_show_menu
        return 1
    fi

    # Fix for missing mime.types or other core config files
    if [[ ! -f /etc/nginx/mime.types ]]; then
        echo -e "${yellow}检测到 Nginx 核心配置文件缺失，正在尝试修复...${plain}"
        if [[ x"${release}" == x"ubuntu" || x"${release}" == x"debian" ]]; then
            apt-get install --reinstall nginx-common -y
        fi
    fi

    mkdir -p /usr/share/nginx/html
    mkdir -p /etc/nginx
    echo -e "${yellow}请选择伪装站点主题/游戏：${plain}"
    echo -e "  1. 贪吃蛇游戏 (Snake Game)"
    echo -e "  2. 2048 游戏 (2048 Game, 简版)"
    echo -e "  3. 黑客帝国代码雨 (Matrix Rain)"
    echo -e "  4. 3D 星空背景 (Starfield)"
    echo -e "  5. 粒子网络 (Particles)"
    echo -e "  6. 极简技术博客 (Tech Blog)"
    echo -e "  7. 炫酷时钟 (Digital Clock)"
    echo -e "  8. 随机选择 (Random)"
    read -rp "请输入选项 [1-8]: " theme_num
    [[ -z "$theme_num" ]] && theme_num=1
    if [[ "$theme_num" == "8" ]]; then
        theme_num=$((RANDOM % 7 + 1))
    fi

    case "$theme_num" in
        1) # Snake
            cat > /usr/share/nginx/html/index.html <<EOF
<!DOCTYPE html><html><head><title>System Update</title><style>html,body{height:100%;margin:0;background:#000;display:flex;align-items:center;justify-content:center;color:#fff;font-family:sans-serif;flex-direction:column}canvas{border:1px solid #fff}h1{margin-bottom:10px}p{color:#aaa}</style></head>
<body><h1>System Update</h1><p>Play Snake while you wait...</p><canvas width="400" height="400" id="g"></canvas>
<script>var c=document.getElementById('g'),x=c.getContext('2d'),g=16,n=0,s={x:160,y:160,dx:g,dy:0,c:[],m:4},a={x:320,y:320};
function l(){requestAnimationFrame(l);if(++n<4)return;n=0;x.clearRect(0,0,400,400);s.x+=s.dx;s.y+=s.dy;if(s.x<0)s.x=384;if(s.x>384)s.x=0;if(s.y<0)s.y=384;if(s.y>384)s.y=0;s.c.unshift({x:s.x,y:s.y});if(s.c.length>s.m)s.c.pop();x.fillStyle='red';x.fillRect(a.x,a.y,15,15);x.fillStyle='lime';s.c.forEach((e,i)=>{x.fillRect(e.x,e.y,15,15);if(e.x===a.x&&e.y===a.y){s.m++;a.x=Math.floor(Math.random()*25)*16;a.y=Math.floor(Math.random()*25)*16}for(var j=i+1;j<s.c.length;j++)if(e.x===s.c[j].x&&e.y===s.c[j].y){s.x=160;s.y=160;s.c=[];s.m=4}})}
document.onkeydown=e=>{if(e.which===37&&s.dx===0){s.dx=-g;s.dy=0}else if(e.which===38&&s.dy===0){s.dy=-g;s.dx=0}else if(e.which===39&&s.dx===0){s.dx=g;s.dy=0}else if(e.which===40&&s.dy===0){s.dy=g;s.dx=0}};requestAnimationFrame(l);</script></body></html>
EOF
            ;;
        2) # 2048 (Simplified)
             cat > /usr/share/nginx/html/index.html <<EOF
<!DOCTYPE html><html><head><title>2048</title><style>body{font-family:sans-serif;background:#faf8ef;color:#776e65;display:flex;flex-direction:column;align-items:center}#grid{display:grid;grid-template-columns:repeat(4,100px);gap:10px;background:#bbada0;padding:10px;border-radius:5px}.cell{width:100px;height:100px;background:#cdc1b4;font-size:40px;display:flex;justify-content:center;align-items:center;font-weight:bold;color:#fff}</style></head>
<body><h1>2048</h1><div id="grid"></div><p>Use Arrow Keys to Play</p><script>
const G=document.getElementById('grid');let b=Array(16).fill(0);function D(){G.innerHTML='';b.forEach(v=>{let c=document.createElement('div');c.className='cell';c.innerText=v||'';c.style.background=v?'#edc22e':(v?'#f2b179':'#cdc1b4');if(v>=8)c.style.color='#f9f6f2';G.appendChild(c)})}
function A(){let e=b.map((v,i)=>v? -1:i).filter(i=>i!==-1);if(e.length)b[e[Math.floor(Math.random()*e.length)]]=Math.random()>.9?4:2}
function M(d){let c=false;for(let i=0;i<4;i++){let r=d%2!==0?[i*4,i*4+1,i*4+2,i*4+3]:[i,i+4,i+8,i+12];let v=r.map(k=>b[k]).filter(x=>x);if(d===1||d===2)v.reverse();
for(let j=0;j<v.length-1;j++)if(v[j]===v[j+1]){v[j]*=2;v.splice(j+1,1);c=true}while(v.length<4)v.push(0);if(d===1||d===2)v.reverse();
r.forEach((k,x)=>{if(b[k]!==v[x])c=true;b[k]=v[x]})}return c}
window.onkeydown=e=>{let m=false;if(e.code=='ArrowUp')m=M(0);else if(e.code=='ArrowRight')m=M(1);else if(e.code=='ArrowDown')m=M(2);else if(e.code=='ArrowLeft')m=M(3);if(m){A();D()}};A();A();D();</script></body></html>
EOF
            ;;
        3) # Matrix Rain
            cat > /usr/share/nginx/html/index.html <<EOF
<!DOCTYPE html><html><body style="margin:0;overflow:hidden;background:#000"><canvas id="c"></canvas><script>
var c=document.getElementById("c"),x=c.getContext("2d"),w=c.width=window.innerWidth,h=c.height=window.innerHeight;
var s='ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',a=s.split(''),f=16,p=Array(Math.floor(w/f)).fill(0);
function d(){x.fillStyle='rgba(0,0,0,0.05)';x.fillRect(0,0,w,h);x.fillStyle='#0F0';x.font=f+'px monospace';
p.forEach((y,i)=>{var t=a[Math.floor(Math.random()*a.length)];x.fillText(t,i*f,y*f);
if(y*f>h&&Math.random()>0.975)p[i]=0;p[i]++})};setInterval(d,33);window.onresize=()=>location.reload();
</script></body></html>
EOF
            ;;
        4) # Starfield
            cat > /usr/share/nginx/html/index.html <<EOF
<!DOCTYPE html><html><body style="background:#000;overflow:hidden;margin:0"><canvas id="c"></canvas><script>
var c=document.getElementById('c'),x=c.getContext('2d'),w=c.width=window.innerWidth,h=c.height=window.innerHeight,S=[];
for(var i=0;i<800;i++)S.push({x:Math.random()*w,y:Math.random()*h,z:Math.random()*w});
function d(){x.fillStyle='black';x.fillRect(0,0,w,h);x.fillStyle='white';
S.forEach(s=>{s.z-=2;if(s.z<=0){s.x=Math.random()*w;s.y=Math.random()*h;s.z=w}
var k=128/s.z,px=(s.x-w/2)*k+w/2,py=(s.y-h/2)*k+h/2;if(px>0&&px<w&&py>0&&py<h){x.fillRect(px,py,1.5,1.5)}});requestAnimationFrame(d)}
d();window.onresize=()=>location.reload();</script></body></html>
EOF
            ;;
        5) # Particles
             cat > /usr/share/nginx/html/index.html <<EOF
<!DOCTYPE html><html><body style="margin:0;overflow:hidden;background:#1a1a1a"><canvas id="c"></canvas><script>
var c=document.getElementById('c'),ctx=c.getContext('2d'),w=c.width=window.innerWidth,h=c.height=window.innerHeight,p=[];
for(var i=0;i<100;i++)p.push({x:Math.random()*w,y:Math.random()*h,vx:Math.random()*2-1,vy:Math.random()*2-1});
function l(){ctx.fillStyle='rgba(26,26,26,0.3)';ctx.fillRect(0,0,w,h);ctx.fillStyle='#00d2ff';
p.forEach((a,i)=>{a.x+=a.vx;a.y+=a.vy;if(a.x<0||a.x>w)a.vx*=-1;if(a.y<0||a.y>h)a.vy*=-1;ctx.beginPath();ctx.arc(a.x,a.y,2,0,Math.PI*2);ctx.fill();
p.slice(i+1).forEach(b=>{var d=Math.hypot(a.x-b.x,a.y-b.y);if(d<100){ctx.beginPath();ctx.strokeStyle='rgba(0,210,255,'+(1-d/100)+')';ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);ctx.stroke()}})});requestAnimationFrame(l)}
l();</script></body></html>
EOF
            ;;
        6) # Tech Blog
            cat > /usr/share/nginx/html/index.html <<EOF
<!DOCTYPE html><html lang="en"><head><title>My Blog</title><style>body{font-family:'Segoe UI',sans-serif;line-height:1.6;max-width:800px;margin:0 auto;padding:20px;color:#333;background:#f4f4f4}header{background:#333;color:#fff;padding:20px;text-align:center;border-radius:5px}article{background:#fff;padding:20px;margin-bottom:20px;border-radius:5px;box-shadow:0 2px 5px rgba(0,0,0,0.1)}h1{margin:0}a{color:#007bff;text-decoration:none}a:hover{text-decoration:underline}</style></head>
<body><header><h1>TechnoSpace</h1><p>Coding, Coffee, and Chaos</p></header></br>
<article><h2>Welcome to my world</h2><p>This is a place where I share my thoughts on technology, programming, and the future of AI. Stay tuned for updates.</p><a href="#">Read more...</a></article>
<article><h2>Why Linux?</h2><p>Linux is the kernel of choice for servers, embedded systems, and supercomputers. Here's why I love it...</p><a href="#">Read more...</a></article>
<article><h2>The Future of WebAssembly</h2><p>WebAssembly (Wasm) is a binary instruction format for a stack-based virtual machine. It is designed as a portable compilation target...</p><a href="#">Read more...</a></article>
</body></html>
EOF
            ;;
        7) # Digital Clock
            cat > /usr/share/nginx/html/index.html <<EOF
<!DOCTYPE html><html><body style="background:#000;color:#0f0;display:flex;justify-content:center;align-items:center;height:100vh;font-family:monospace;font-size:15vw;margin:0"><div id="c"></div><script>
setInterval(()=>document.getElementById('c').innerText=new Date().toLocaleTimeString(),1000)</script></body></html>
EOF
            ;;
    esac
    
    # 强力清理 Nginx 环境
    systemctl stop nginx 2>/dev/null
    pkill -9 nginx 2>/dev/null
    rm -rf /etc/nginx/conf.d/*
    rm -rf /etc/nginx/sites-enabled/*
    mkdir -p /var/log/nginx
    
    cat > /etc/nginx/nginx.conf <<EOF
worker_processes auto;
error_log /var/log/nginx/error.log;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    
    server {
        listen 8080 default_server;
        server_name _;
        root /usr/share/nginx/html;
        index index.html;
        location / {
            try_files \$uri \$uri/ =404;
        }
    }
}
EOF
    
    echo -e "${yellow}正在检查 Nginx 配置...${plain}"
    if nginx -t; then
        systemctl start nginx
        systemctl enable nginx
        echo -e "${green}Nginx 安装/重置完成，监听端口: 8080${plain}"
    else
        echo -e "${red}Nginx 配置错误，请根据上方提示排查！${plain}"
    fi
    echo -e "${green}Nginx 安装/重置完成，监听端口: 8080${plain}"
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_menu() {
    echo -e "
  ${green}tox 后端管理脚本，使用${plain} ${red}tox${plain} ${green}命令运行本脚本${plain}
 ${green} 1.${plain} 安装 tox
 ${green} 2.${plain} 更新 tox
 ${green} 3.${plain} 卸载 tox
 ${green} 4.${plain} 启动 tox
 ${green} 5.${plain} 停止 tox
 ${green} 6.${plain} 重启 tox
 ${green} 7.${plain} 查看 tox 状态
 ${green} 8.${plain} 查看 tox 日志
 ${green} 9.${plain} 设置 tox 开机自启
 ${green}10.${plain} 取消 tox 开机自启
 ${green}11.${plain} 一键安装 bbr (原版/魔改/plus/锐速)
 ${green}12.${plain} 查看 tox 版本 
 ${green}13.${plain} 生成 x25519 密钥
 ${green}14.${plain} 升级 tox 维护脚本
 ${green}15.${plain} 生成 tox 配置文件
 ${green}16.${plain} 放行 VPS 的所有网络端口
 ${green}17.${plain} 安装/重置 Nginx (8080端口)
 ${green}18.${plain} 卸载 Nginx
 ${green} 0.${plain} 修改配置
 "
    echo
    if systemctl is-active tox &>/dev/null ; then
        echo -e "tox 状态: ${green}已启动${plain}"
    else
        echo -e "tox 状态: ${red}未启动${plain}"
    fi
    echo && read -rp "请输入选择 [0-18]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) install_bbr ;;
        12) check_install && show_V2bX_version ;;
        13) check_install && generate_x25519_key ;;
        14) update_shell ;;
        15) generate_config_file ;;
        16) open_ports ;;
        17) install_reset_nginx ;;
        18) uninstall_nginx ;;
        *) echo -e "${red}请输入正确的数字 [0-18]${plain}" ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "update") check_install 0 && update 0 $2 ;;
        "config") config $* ;;
        "generate") generate_config_file ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        "x25519") check_install 0 && generate_x25519_key 0 ;;
        "version") check_install 0 && show_V2bX_version 0 ;;
        "update_shell") update_shell ;;
        *) show_usage
    esac
else
    show_menu
fi
