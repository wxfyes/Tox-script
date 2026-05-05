#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

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

arch=$(uname -m)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
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

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release wget curl unzip tar crontabs socat ca-certificates -y >/dev/null 2>&1
        update-ca-trust force-enable >/dev/null 2>&1
    elif [[ x"${release}" == x"alpine" ]]; then
        apk add wget curl unzip tar socat ca-certificates >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"debian" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt install wget curl unzip tar cron socat ca-certificates -y >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"ubuntu" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt install wget curl unzip tar cron socat -y >/dev/null 2>&1
        apt-get install ca-certificates wget -y >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"arch" ]]; then
        pacman -Sy --noconfirm >/dev/null 2>&1
        pacman -S --noconfirm --needed wget curl unzip tar cron socat >/dev/null 2>&1
        pacman -S --noconfirm --needed ca-certificates wget >/dev/null 2>&1
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
        temp=$(systemctl status tox | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

install_V2bX() {
    if [[ -e /usr/local/tox/ ]]; then
        rm -rf /usr/local/tox/
    fi

    mkdir /usr/local/tox/ -p
    cd /usr/local/tox/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/wxfyes/Tox/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 tox 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 tox 版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 tox 最新版本：${last_version}，开始安装"
        wget --no-check-certificate -N --progress=bar -O /usr/local/tox/Tox-linux.zip https://github.com/wxfyes/Tox/releases/download/${last_version}/Tox-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 Tox 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/wxfyes/Tox/releases/download/${last_version}/Tox-linux-${arch}.zip"
        echo -e "开始安装 tox $1"
        wget --no-check-certificate -N --progress=bar -O /usr/local/tox/Tox-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 tox $1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    unzip Tox-linux.zip
    rm Tox-linux.zip -f
    # Rename binary to tox
    if [[ -f Tox ]]; then
        mv Tox tox
    fi
    chmod +x tox
    mkdir /etc/tox/ -p
    cp geoip.dat /etc/tox/
    cp geosite.dat /etc/tox/
    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/tox -f
        cat <<EOF > /etc/init.d/tox
#!/sbin/openrc-run

name="tox"
description="tox"

command="/usr/local/tox/tox"
command_args="server"
command_user="root"

pidfile="/run/tox.pid"
command_background="yes"

depend() {
        need net
}
EOF
        chmod +x /etc/init.d/tox
        rc-update add tox default
        echo -e "${green}tox ${last_version}${plain} 安装完成，已设置开机自启"
    else
        rm /etc/systemd/system/tox.service -f
        cat <<EOF > /etc/systemd/system/tox.service
[Unit]
Description=tox Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/tox/
ExecStart=/usr/local/tox/tox server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl stop tox
        systemctl enable tox
        echo -e "${green}tox ${last_version}${plain} 安装完成，已设置开机自启"
    fi

    if [[ ! -f /etc/tox/config.json ]]; then
        cp config.json /etc/tox/
        echo -e ""
        echo -e "全新安装，请先参看教程：https://v2bx.v-50.me/，配置必要的内容"
        first_install=true
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service tox start
        else
            systemctl start tox
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}tox 重启成功${plain}"
        else
            echo -e "${red}tox 可能启动失败，请稍后使用 tox log 查看日志信息，若无法启动，则可能更改了配置格式，请前往 wiki 查看：https://github.com/V2bX-project/V2bX/wiki${plain}"
        fi
        first_install=false
    fi

    if [[ ! -f /etc/tox/dns.json ]]; then
        cp dns.json /etc/tox/
    fi
    if [[ ! -f /etc/tox/route.json ]]; then
        cp route.json /etc/tox/
    fi
    if [[ ! -f /etc/tox/custom_outbound.json ]]; then
        cp custom_outbound.json /etc/tox/
    fi
    if [[ ! -f /etc/tox/custom_inbound.json ]]; then
        cp custom_inbound.json /etc/tox/
    fi
    # 替换脚本下载地址
    curl -o /usr/bin/tox -Ls https://raw.githubusercontent.com/wxfyes/Tox-script/master/tox.sh
    chmod +x /usr/bin/tox
    if [ ! -L /usr/bin/v2bx ]; then
        ln -s /usr/bin/tox /usr/bin/v2bx
        chmod +x /usr/bin/v2bx
    fi

    # Install Masquerade Site (Nginx)
    read -rp "是否安装 Nginx 作为回落伪装站点 (占用 8080 端口)? (y/n): " install_nginx
    if [[ $install_nginx == [Yy] ]]; then
        echo -e "${yellow}正在部署伪装站点 (Nginx)...${plain}"
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
            echo -e "${yellow}跳过伪装站点部署${plain}"
        else
            # Configure Nginx for local fallback 8080
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
        
        cat > /etc/nginx/nginx.conf <<EOF
user root;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    server {
        listen 127.0.0.1:8080 default_server;
        server_name _;
        root /usr/share/nginx/html;
        index index.html;
        
        access_log /var/log/nginx/access_8080.log main;
        
        location / {
            try_files \$uri \$uri/ =404;
        }
    }
}
EOF
        systemctl restart nginx
        systemctl enable nginx
        echo -e "${green}伪装站点部署完成 (监听 127.0.0.1:8080)${plain}"
        fi
    else
        echo -e "${yellow}跳过 Nginx 安装${plain}"
    fi

    cd $cur_dir
    rm -f install.sh
    echo -e ""
    echo "tox 管理脚本使用方法 (兼容使用V2bX执行，大小写不敏感): "
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
    echo "tox generate     - 生成 tox 配置文件"
    echo "tox update       - 更新 tox"
    echo "tox update x.x.x - 更新 tox 指定版本"
    echo "tox install      - 安装 tox"
    echo "tox uninstall    - 卸载 tox"
    echo "tox version      - 查看 tox 版本"
    echo "------------------------------------------"
    # 首次安装询问是否生成配置文件
    if [[ $first_install == true ]]; then
        read -rp "检测到你为第一次安装tox,是否自动直接生成配置文件？(y/n): " if_generate
        if [[ $if_generate == [Yy] ]]; then
            # 替换初始化脚本地址
            curl -o ./initconfig.sh -Ls https://raw.githubusercontent.com/wxfyes/Tox-script/master/initconfig.sh
            source initconfig.sh
            rm initconfig.sh -f
            generate_config_file
        fi
    fi
}

echo -e "${green}开始安装${plain}"
install_base
install_V2bX $1
