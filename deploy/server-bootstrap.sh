#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

DOMAIN="${DOMAIN:-}"
SUB_DOMAIN="${SUB_DOMAIN:-${DOMAIN}}"
XRAY_VERSION="v26.3.27"
HYSTERIA_VERSION="v2.12.1"
XRAY_PORT="${XRAY_PORT:-2053}"
ROTATE_SECRETS="${ROTATE_SECRETS:-0}"
STACK_DIR="/etc/proxy-stack"
SECRETS_FILE="${STACK_DIR}/secrets.env"
LOCK_FILE="/var/lock/proxy-stack-bootstrap.lock"
BACKUP_PARENT_DIR="${BACKUP_PARENT_DIR:-/root}"

if [[ ${EUID} -ne 0 ]]; then
  echo "This script must run as root." >&2
  exit 1
fi

if [[ ! "${DOMAIN}" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] ||
   [[ ! "${SUB_DOMAIN}" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]]; then
  echo "DOMAIN and SUB_DOMAIN must be valid DNS names." >&2
  exit 1
fi
if [[ ! "${XRAY_PORT}" =~ ^[0-9]+$ ]] || (( XRAY_PORT < 1 || XRAY_PORT > 65535 )); then
  echo "XRAY_PORT must be between 1 and 65535." >&2
  exit 1
fi
if (( XRAY_PORT == 22 || XRAY_PORT == 80 || XRAY_PORT == 443 || XRAY_PORT == 8080 || XRAY_PORT == 8443 || XRAY_PORT == 10443 )); then
  echo "XRAY_PORT ${XRAY_PORT} conflicts with a reserved TCP port (22, 80, 443 closed, 8080, 8443, Trojan 10443)." >&2
  exit 1
fi
if [[ "${ROTATE_SECRETS}" != "0" && "${ROTATE_SECRETS}" != "1" ]]; then
  echo "ROTATE_SECRETS must be 0 or 1." >&2
  exit 1
fi

# Read-only gate BEFORE locks, backups, packages, credentials or service changes.
# Copy preflight.py alongside this file. Never curl an unreviewed script into sudo.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export DOMAIN SUB_DOMAIN XRAY_PORT
python3 -B "${script_dir}/preflight.py"
if [[ "${PREFLIGHT_ONLY:-0}" == "1" ]]; then
  exit 0
fi

# Keep the lock file as a harmless audit marker. The open file descriptor is
# released automatically when this shell exits, including on an error path.
if ! command -v flock >/dev/null 2>&1; then
  echo "flock is required to prevent concurrent proxy-stack deployments; exiting safely." >&2
  exit 1
fi
if ! exec 9>"${LOCK_FILE}"; then
  echo "Unable to open deployment lock ${LOCK_FILE}; exiting safely." >&2
  exit 1
fi
if ! flock -n 9; then
  echo "Another proxy-stack deployment is already running; exiting without changes." >&2
  exit 1
fi

# mktemp adds an unpredictable suffix in addition to UTC ordering, so even
# sequential starts in the same second never share a rollback directory.
backup_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="$(mktemp -d "${BACKUP_PARENT_DIR}/proxy-stack-backup-${backup_timestamp}-XXXXXX")"
mkdir -p "${STACK_DIR}"
for path in \
  /etc/xray \
  /etc/hysteria \
  /etc/nginx/sites-available/proxy-stack \
  /etc/letsencrypt/renewal-hooks/deploy/proxy-stack \
  /etc/systemd/system/xray.service \
  /etc/systemd/system/hysteria-server.service \
  /etc/systemd/system/proxy-firewall.service \
  /usr/local/sbin/proxy-firewall \
  /etc/ssh/sshd_config.d/60-proxy-hardening.conf \
  /etc/sysctl.d/60-proxy-stack.conf \
  "${STACK_DIR}/firewall.nft" \
  /var/lib/proxy-subscription \
  /usr/local/bin/xray \
  /usr/local/bin/hysteria; do
  if [[ -e "${path}" ]]; then
    cp -a --parents "${path}" "${BACKUP_DIR}/"
  fi
done

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates certbot curl nginx nftables openssl unzip vnstat

# Historical incident remediation is opt-in, not a policy for every user's VM.
if [[ "${DISABLE_GOOGLE_OPS_AGENT:-0}" == "1" ]]; then
  systemctl disable --now google-cloud-ops-agent.service 2>/dev/null || true
  systemctl mask google-cloud-ops-agent.service >/dev/null 2>&1 || true
fi

if ! getent passwd xray >/dev/null; then
  useradd --system --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin xray
fi
if ! getent passwd hysteria >/dev/null; then
  useradd --system --home-dir /var/lib/hysteria --create-home --shell /usr/sbin/nologin hysteria
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

curl --fail --location --retry 3 --output "${tmp_dir}/xray.zip" \
  "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"
curl --fail --location --retry 3 --output "${tmp_dir}/xray.zip.dgst" \
  "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip.dgst"
xray_sha256="$(awk -F'= ' '$1 == "SHA2-256" { print $2 }' "${tmp_dir}/xray.zip.dgst")"
[[ -n "${xray_sha256}" ]]
printf '%s  %s\n' "${xray_sha256}" "${tmp_dir}/xray.zip" | sha256sum --check --status
unzip -q "${tmp_dir}/xray.zip" -d "${tmp_dir}/xray"
install -m 0755 "${tmp_dir}/xray/xray" /usr/local/bin/xray
mkdir -p /usr/local/share/xray
for dat in geoip.dat geosite.dat; do
  [[ -f "${tmp_dir}/xray/${dat}" ]] && install -m 0644 "${tmp_dir}/xray/${dat}" "/usr/local/share/xray/${dat}"
done

curl --fail --location --retry 3 --output "${tmp_dir}/hysteria" \
  "https://github.com/apernet/hysteria/releases/download/app/${HYSTERIA_VERSION}/hysteria-linux-amd64"
curl --fail --location --retry 3 --output "${tmp_dir}/hysteria-hashes.txt" \
  "https://github.com/apernet/hysteria/releases/download/app/${HYSTERIA_VERSION}/hashes.txt"
hysteria_sha256="$(awk '$2 == "build/hysteria-linux-amd64" { print $1 }' "${tmp_dir}/hysteria-hashes.txt")"
[[ -n "${hysteria_sha256}" ]]
printf '%s  %s\n' "${hysteria_sha256}" "${tmp_dir}/hysteria" | sha256sum --check --status
install -m 0755 "${tmp_dir}/hysteria" /usr/local/bin/hysteria

if [[ "${ROTATE_SECRETS}" == "1" && -s "${SECRETS_FILE}" ]]; then
  install -m 0600 "${SECRETS_FILE}" "${BACKUP_DIR}/secrets.env.compromised"
  rm -f "${SECRETS_FILE}"
fi

if [[ ! -s "${SECRETS_FILE}" ]]; then
  key_output="$(/usr/local/bin/xray x25519)"
  xray_private_key="$(awk -F': ' '/^PrivateKey:/ { print $2; exit }' <<<"${key_output}")"
  xray_public_key="$(awk -F': ' '/^(Password|PublicKey)/ { print $2; exit }' <<<"${key_output}")"
  [[ -n "${xray_private_key}" && -n "${xray_public_key}" ]]
  cat >"${SECRETS_FILE}" <<EOF
XRAY_UUID=$(cat /proc/sys/kernel/random/uuid)
XRAY_PRIVATE_KEY=${xray_private_key}
XRAY_PUBLIC_KEY=${xray_public_key}
XRAY_SHORT_ID=$(openssl rand -hex 8)
HYSTERIA_PASSWORD=$(openssl rand -hex 32)
TROJAN_PASSWORD=$(openssl rand -hex 32)
SUBSCRIPTION_TOKEN=$(openssl rand -hex 32)
BACKUP_SUBSCRIPTION_TOKEN=$(openssl rand -hex 32)
EOF
  chmod 0600 "${SECRETS_FILE}"
fi

# Existing installations predate Trojan. Keep all established credentials and
# append only the new, independently generated password on first migration.
if ! grep -q '^TROJAN_PASSWORD=' "${SECRETS_FILE}"; then
  trojan_password="$(openssl rand -hex 32)"
  printf '\nTROJAN_PASSWORD=%s\n' "${trojan_password}" >>"${SECRETS_FILE}"
  chmod 0600 "${SECRETS_FILE}"
fi

set -a
# shellcheck disable=SC1090
source "${SECRETS_FILE}"
set +a

mkdir -p /etc/xray/certs /etc/hysteria/certs /var/lib/hysteria /var/lib/proxy-subscription
chown root:xray /etc/xray
chmod 0750 /etc/xray
chown root:xray /etc/xray/certs
chmod 0750 /etc/xray/certs
chown root:hysteria /etc/hysteria /etc/hysteria/certs
chmod 0750 /etc/hysteria /etc/hysteria/certs
chown -R hysteria:hysteria /var/lib/hysteria

cat >/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "trojan-tls-in",
      "listen": "0.0.0.0",
      "port": 10443,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "${TROJAN_PASSWORD}",
            "email": "home-trojan"
          }
        ],
        "fallbacks": [
          { "dest": "127.0.0.1:8080" }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "minVersion": "1.2",
          "certificates": [
            {
              "certificateFile": "/etc/xray/certs/fullchain.pem",
              "keyFile": "/etc/xray/certs/privkey.pem"
            }
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"],
        "routeOnly": true
      }
    },
    {
      "tag": "vless-reality-in",
      "listen": "0.0.0.0",
      "port": ${XRAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${XRAY_UUID}",
            "email": "home-clash",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "method": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "127.0.0.1:8443",
          "xver": 0,
          "serverNames": ["${DOMAIN}"],
          "privateKey": "${XRAY_PRIVATE_KEY}",
          "shortIds": ["${XRAY_SHORT_ID}"],
          "maxTimeDiff": 60000
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8",
          "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24",
          "192.168.0.0/16", "224.0.0.0/4", "240.0.0.0/4",
          "::/128", "::1/128", "fc00::/7", "fe80::/10", "ff00::/8"
        ],
        "outboundTag": "block"
      },
      { "type": "field", "port": "25", "outboundTag": "block" }
    ]
  }
}
EOF
chown root:xray /etc/xray/config.json
chmod 0640 /etc/xray/config.json

cat >/etc/hysteria/config.yaml <<EOF
listen: 0.0.0.0:443

tls:
  cert: /etc/hysteria/certs/fullchain.pem
  key: /etc/hysteria/certs/privkey.pem

auth:
  type: password
  password: ${HYSTERIA_PASSWORD}

acl:
  inline:
    - reject(0.0.0.0/8)
    - reject(10.0.0.0/8)
    - reject(100.64.0.0/10)
    - reject(127.0.0.0/8)
    - reject(169.254.0.0/16)
    - reject(172.16.0.0/12)
    - reject(192.0.0.0/24)
    - reject(192.168.0.0/16)
    - reject(224.0.0.0/4)
    - reject(240.0.0.0/4)
    - reject(::/128)
    - reject(::1/128)
    - reject(fc00::/7)
    - reject(fe80::/10)
    - reject(ff00::/8)
    - reject(all, tcp/25)
    - direct(all)

masquerade:
  type: proxy
  proxy:
    url: http://127.0.0.1:8080/
    rewriteHost: true
EOF
chown root:hysteria /etc/hysteria/config.yaml
chmod 0640 /etc/hysteria/config.yaml

cat >/etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Trojan TLS and VLESS REALITY Server
Documentation=https://xtls.github.io/
Requires=proxy-firewall.service
After=network-online.target nss-lookup.target proxy-firewall.service
Wants=network-online.target

[Service]
Type=simple
User=xray
Group=xray
ExecStart=/usr/local/bin/xray run -c /etc/xray/config.json
Restart=on-failure
RestartSec=3s
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictAddressFamilies=AF_INET AF_INET6
MemoryMax=256M
LimitNOFILE=8192
TasksMax=512

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/hysteria-server.service <<'EOF'
[Unit]
Description=Hysteria 2 Server
Documentation=https://v2.hysteria.network/
Requires=proxy-firewall.service
After=network-online.target nginx.service proxy-firewall.service
Wants=network-online.target

[Service]
Type=simple
User=hysteria
Group=hysteria
WorkingDirectory=/var/lib/hysteria
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=3s
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadWritePaths=/var/lib/hysteria
RestrictSUIDSGID=true
LockPersonality=true
RestrictAddressFamilies=AF_INET AF_INET6
MemoryMax=256M

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /var/www/acme/.well-known/acme-challenge /var/www/proxy
cat >/var/www/proxy/index.html <<'EOF'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Service Online</title><style>body{font:16px system-ui;margin:12vh auto;max-width:40rem;padding:2rem;color:#253047}h1{font-size:2rem}p{line-height:1.7}</style></head>
<body><h1>Service Online</h1><p>The requested service is available.</p></body></html>
EOF
chown -R www-data:www-data /var/www/acme /var/www/proxy

rm -f /etc/nginx/sites-enabled/default
cat >/etc/nginx/sites-available/proxy-stack <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    location ^~ /.well-known/acme-challenge/ { root /var/www/acme; }
    location / { root /var/www/proxy; try_files \$uri /index.html; }
}
EOF
ln -sfn /etc/nginx/sites-available/proxy-stack /etc/nginx/sites-enabled/proxy-stack
nginx -t
systemctl enable --now nginx
systemctl reload nginx

certbot certonly --webroot --webroot-path /var/www/acme \
  --domain "${DOMAIN}" --non-interactive --agree-tos \
  --register-unsafely-without-email --keep-until-expiring

install -o root -g hysteria -m 0640 "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" /etc/hysteria/certs/fullchain.pem
install -o root -g hysteria -m 0640 "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" /etc/hysteria/certs/privkey.pem
install -o root -g xray -m 0640 "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" /etc/xray/certs/fullchain.pem
install -o root -g xray -m 0640 "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" /etc/xray/certs/privkey.pem

cat >/etc/letsencrypt/renewal-hooks/deploy/proxy-stack <<EOF
#!/bin/sh
set -eu
install -o root -g hysteria -m 0640 /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /etc/hysteria/certs/fullchain.pem
install -o root -g hysteria -m 0640 /etc/letsencrypt/live/${DOMAIN}/privkey.pem /etc/hysteria/certs/privkey.pem
install -o root -g xray -m 0640 /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /etc/xray/certs/fullchain.pem
install -o root -g xray -m 0640 /etc/letsencrypt/live/${DOMAIN}/privkey.pem /etc/xray/certs/privkey.pem
systemctl restart xray
systemctl restart hysteria-server
systemctl reload nginx
EOF
chmod 0750 /etc/letsencrypt/renewal-hooks/deploy/proxy-stack

cat >/var/lib/proxy-subscription/clash.yaml <<EOF
mixed-port: 7890
allow-lan: false
mode: rule
log-level: warning
ipv6: false
unified-delay: true
tcp-concurrent: true
external-controller: 127.0.0.1:9090

profile:
  store-selected: true
  store-fake-ip: true

geodata-mode: true
geo-auto-update: true
geo-update-interval: 24

dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter-mode: blacklist
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - 'localhost.ptlogin2.qq.com'
    - '+.stun.*.*'
    - '+.stun.*.*.*'
    - 'time.*.com'
    - 'ntp.*.com'
  respect-rules: true
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  proxy-server-nameserver:
    - https://dns.alidns.com/dns-query
  nameserver:
    - https://dns.alidns.com/dns-query
  nameserver-policy:
    'geosite:cn,private':
      - https://dns.alidns.com/dns-query
    'geosite:geolocation-!cn':
      - https://1.1.1.1/dns-query
      - https://8.8.8.8/dns-query

proxies:
  - name: US-Hysteria2
    type: hysteria2
    server: ${DOMAIN}
    port: 443
    password: ${HYSTERIA_PASSWORD}
    sni: ${DOMAIN}
    skip-cert-verify: false
    alpn:
      - h3

  - name: US-Trojan
    type: trojan
    server: ${DOMAIN}
    port: 10443
    password: ${TROJAN_PASSWORD}
    sni: ${DOMAIN}
    udp: true
    skip-cert-verify: false
    client-fingerprint: chrome

  - name: US-Reality
    type: vless
    server: ${DOMAIN}
    port: ${XRAY_PORT}
    uuid: ${XRAY_UUID}
    network: tcp
    udp: true
    tls: true
    servername: ${DOMAIN}
    flow: xtls-rprx-vision
    client-fingerprint: chrome
    reality-opts:
      public-key: ${XRAY_PUBLIC_KEY}
      short-id: ${XRAY_SHORT_ID}

proxy-groups:
  - name: US-Auto
    type: fallback
    url: https://cp.cloudflare.com/generate_204
    interval: 300
    lazy: true
    proxies:
      - US-Hysteria2
      - US-Trojan
      - US-Reality

  - name: Proxy-Select
    type: select
    proxies:
      - US-Auto
      - US-Hysteria2
      - US-Trojan
      - US-Reality
      - DIRECT

  - name: ChatGPT
    type: select
    proxies:
      - US-Auto

rules:
  - DOMAIN-SUFFIX,auth.openai.com,ChatGPT
  - DOMAIN-SUFFIX,chatgpt.com,ChatGPT
  - DOMAIN-SUFFIX,openai.com,ChatGPT
  - DOMAIN-SUFFIX,oaistatic.com,ChatGPT
  - DOMAIN-SUFFIX,oaiusercontent.com,ChatGPT
  - DOMAIN-SUFFIX,oaistatsig.com,ChatGPT
  - DOMAIN-SUFFIX,openaimerge.com,ChatGPT
  - DOMAIN,cdn.workos.com,ChatGPT
  - DOMAIN,forwarder.workos.com,ChatGPT
  - DOMAIN,images.workoscdn.com,ChatGPT
  - DOMAIN,setup.workos.com,ChatGPT
  - DOMAIN,workos.imgix.net,ChatGPT
  - DOMAIN,chatgpt.livekit.cloud,ChatGPT
  - DOMAIN,challenges.cloudflare.com,ChatGPT
  - DOMAIN-SUFFIX,intercom.io,ChatGPT
  - DOMAIN-SUFFIX,intercomcdn.com,ChatGPT
  - DOMAIN,js.stripe.com,ChatGPT
  - DOMAIN-SUFFIX,ingest.sentry.io,ChatGPT
  - DOMAIN,rum.browser-intake-datadoghq.com,ChatGPT
  - GEOSITE,private,DIRECT
  - GEOIP,private,DIRECT,no-resolve
  - GEOSITE,cn,DIRECT
  - GEOIP,CN,DIRECT,no-resolve
  - MATCH,Proxy-Select
EOF
chown root:www-data /var/lib/proxy-subscription/clash.yaml
chmod 0640 /var/lib/proxy-subscription/clash.yaml

{
  printf 'hysteria2://%s@%s:443/?sni=%s&alpn=h3#US-Hysteria2\n' "${HYSTERIA_PASSWORD}" "${DOMAIN}" "${DOMAIN}"
  printf 'trojan://%s@%s:10443?security=tls&sni=%s&type=tcp#US-Trojan\n' "${TROJAN_PASSWORD}" "${DOMAIN}" "${DOMAIN}"
  printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#US-Reality\n' \
    "${XRAY_UUID}" "${DOMAIN}" "${XRAY_PORT}" "${DOMAIN}" "${XRAY_PUBLIC_KEY}" "${XRAY_SHORT_ID}"
} | base64 -w 0 >/var/lib/proxy-subscription/v2ray.txt
chown root:www-data /var/lib/proxy-subscription/v2ray.txt
chmod 0640 /var/lib/proxy-subscription/v2ray.txt
chown root:www-data /var/lib/proxy-subscription
chmod 0750 /var/lib/proxy-subscription

cat >/etc/nginx/sites-available/proxy-stack <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    location ^~ /.well-known/acme-challenge/ { root /var/www/acme; }
    location / { return 301 https://\$host:8443\$request_uri; }
}

server {
    listen 127.0.0.1:8080;
    server_name localhost;
    root /var/www/proxy;
    location / { try_files \$uri /index.html; }
}

server {
    listen 8443 ssl;
    listen [::]:8443 ssl;
    server_name ${DOMAIN};
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;

    location = /${BACKUP_SUBSCRIPTION_TOKEN}/clash.yaml {
        access_log off;
        alias /var/lib/proxy-subscription/clash.yaml;
        default_type 'text/yaml; charset=utf-8';
        add_header Cache-Control 'no-store, no-cache, must-revalidate, max-age=0' always;
        add_header X-Content-Type-Options 'nosniff' always;
        add_header X-Frame-Options 'DENY' always;
        add_header Referrer-Policy 'no-referrer' always;
    }

    location = /${BACKUP_SUBSCRIPTION_TOKEN}/v2ray.txt {
        access_log off;
        alias /var/lib/proxy-subscription/v2ray.txt;
        default_type 'text/plain; charset=utf-8';
        add_header Cache-Control 'no-store, no-cache, must-revalidate, max-age=0' always;
        add_header X-Content-Type-Options 'nosniff' always;
        add_header X-Frame-Options 'DENY' always;
        add_header Referrer-Policy 'no-referrer' always;
    }

    location / {
        root /var/www/proxy;
        try_files \$uri /index.html;
    }
}
EOF
nginx -t
systemctl reload nginx

cat >/etc/sysctl.d/60-proxy-stack.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
EOF
sysctl --system >/dev/null

mkdir -p /etc/systemd/journald.conf.d
cat >/etc/systemd/journald.conf.d/60-proxy-stack.conf <<'EOF'
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=50M
MaxRetentionSec=7day
EOF

cat >/etc/ssh/sshd_config.d/60-proxy-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
MaxAuthTries 3
LoginGraceTime 30
EOF
/usr/sbin/sshd -t
systemctl reload ssh

cat >"${STACK_DIR}/firewall.nft" <<EOF
table inet proxy_guard {
  chain input {
    type filter hook input priority -10; policy drop;
    iifname "lo" accept
    ct state invalid drop
    ct state established,related accept
    ip protocol icmp accept
    ip6 nexthdr ipv6-icmp accept
    udp sport 67 udp dport 68 accept
    tcp dport 22 ct state new meter ssh4 { ip saddr limit rate 30/minute burst 20 packets } accept
    tcp dport 22 ct state new meter ssh6 { ip6 saddr limit rate 30/minute burst 20 packets } accept
    tcp dport 22 drop
    tcp dport { 80, 8443 } accept
    tcp dport 10443 ct state new limit rate 60/second burst 120 packets accept
    tcp dport 10443 drop
    tcp dport ${XRAY_PORT} ct state new limit rate 60/second burst 120 packets accept
    tcp dport ${XRAY_PORT} drop
    udp dport 443 accept
  }
}
EOF

cat >/usr/local/sbin/proxy-firewall <<'EOF'
#!/bin/sh
set -eu
case "${1:-start}" in
  start|reload)
    /usr/sbin/nft delete table inet proxy_guard 2>/dev/null || true
    /usr/sbin/nft -f /etc/proxy-stack/firewall.nft
    ;;
  stop)
    /usr/sbin/nft delete table inet proxy_guard 2>/dev/null || true
    ;;
  *) exit 2 ;;
esac
EOF
chmod 0750 /usr/local/sbin/proxy-firewall

cat >/etc/systemd/system/proxy-firewall.service <<'EOF'
[Unit]
Description=Proxy Stack nftables Input Firewall
After=network-online.target
Before=xray.service hysteria-server.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/proxy-firewall start
ExecReload=/usr/local/sbin/proxy-firewall reload
ExecStop=/usr/local/sbin/proxy-firewall stop

[Install]
WantedBy=multi-user.target
EOF

/usr/local/bin/xray run -test -c /etc/xray/config.json
systemctl daemon-reload
systemctl enable xray hysteria-server
systemctl enable --now vnstat certbot.timer
systemctl enable --now proxy-firewall
systemctl reload proxy-firewall
# enable --now does not replace an already active process's configuration.
# Restart only after the new config passed validation and TCP 10443 is guarded.
systemctl restart xray hysteria-server

cat >"${STACK_DIR}/subscription-urls.txt" <<EOF
PRIMARY_SUBSCRIPTION=https://${SUB_DOMAIN}/${SUBSCRIPTION_TOKEN}/subscription
PRIMARY_CLASH=https://${SUB_DOMAIN}/${SUBSCRIPTION_TOKEN}/clash.yaml
PRIMARY_V2RAY=https://${SUB_DOMAIN}/${SUBSCRIPTION_TOKEN}/v2ray.txt
BACKUP_CLASH=https://${DOMAIN}:8443/${BACKUP_SUBSCRIPTION_TOKEN}/clash.yaml
BACKUP_V2RAY=https://${DOMAIN}:8443/${BACKUP_SUBSCRIPTION_TOKEN}/v2ray.txt
EOF
chmod 0600 "${STACK_DIR}/subscription-urls.txt"

{
  echo "xray=$(/usr/local/bin/xray version | head -n1)"
  echo "hysteria=$(/usr/local/bin/hysteria version | head -n1)"
  echo "deployed_at=$(date -u +%FT%TZ)"
  echo "backup_dir=${BACKUP_DIR}"
} >"${STACK_DIR}/versions.txt"
chmod 0644 "${STACK_DIR}/versions.txt"

systemctl --no-pager --full status xray hysteria-server nginx proxy-firewall vnstat | sed -n '1,100p'
ss -lntup | grep -E ":(22|80|443|8443|10443|${XRAY_PORT}|20201|20202)\\b" || true
