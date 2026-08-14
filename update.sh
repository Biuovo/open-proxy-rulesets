#!/usr/bin/env bash
set -euo pipefail

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) GOARCH=amd64 ;;
  aarch64|arm64) GOARCH=arm64 ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

fetch() { curl -fL --retry 5 --retry-delay 5 -o "$1" "$2"; }

install_tools() {
  if [ -x "${MIHOMO_BIN:-}" ]; then
    MH="$MIHOMO_BIN"
  elif command -v mihomo >/dev/null 2>&1; then
    MH=$(command -v mihomo)
  else
    python3 - "$GOARCH" "$WORKDIR/mihomo.gz" <<'PY'
import json, sys, urllib.request
arch, out = sys.argv[1], sys.argv[2]
data=json.load(urllib.request.urlopen('https://api.github.com/repos/MetaCubeX/mihomo/releases/latest'))
assets=[a for a in data['assets'] if a['name'].endswith('.gz')]
prefs=[f'mihomo-linux-{arch}-compatible-', f'mihomo-linux-{arch}-'] if arch=='amd64' else [f'mihomo-linux-{arch}-']
url=None
for pref in prefs:
    m=[a for a in assets if a['name'].startswith(pref)]
    if m:
        url=m[0]['browser_download_url']; break
if not url: raise SystemExit('mihomo asset not found')
urllib.request.urlretrieve(url, out)
PY
    gunzip -f "$WORKDIR/mihomo.gz"
    chmod +x "$WORKDIR/mihomo"
    MH="$WORKDIR/mihomo"
  fi

  if [ -x "${SING_BOX_BIN:-}" ]; then
    SB="$SING_BOX_BIN"
  elif command -v sing-box >/dev/null 2>&1; then
    SB=$(command -v sing-box)
  else
    SB_VER=$(python3 - <<'PY'
import json, urllib.request
print(json.load(urllib.request.urlopen('https://api.github.com/repos/SagerNet/sing-box/releases/latest'))['tag_name'].lstrip('v'))
PY
)
    fetch "$WORKDIR/sing-box.tar.gz" "https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-${SB_VER}-linux-${GOARCH}-musl.tar.gz"
    mkdir -p "$WORKDIR/singbox"
    tar -xzf "$WORKDIR/sing-box.tar.gz" -C "$WORKDIR/singbox"
    SB=$(find "$WORKDIR/singbox" -type f -name sing-box | head -n1)
    chmod +x "$SB"
  fi
}

install_tools

echo "Using mihomo: $($MH -v | head -n1)"
echo "Using sing-box: $($SB version | head -n1)"

# Source mapping
fetch "$WORKDIR/CN.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/cn.list
# CNIP intentionally keeps nekolsd as its upstream source.
fetch "$WORKDIR/CNIP.raw" https://raw.githubusercontent.com/nekolsd/geoip/release/text/cn.txt
fetch "$WORKDIR/TelegramIP.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/telegram.list
fetch "$WORKDIR/Telegram.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/telegram.list
fetch "$WORKDIR/ChinaMedia.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-media-cn.list
fetch "$WORKDIR/GlobalMedia.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-media.list
fetch "$WORKDIR/Proxy.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/geolocation-!cn.list
fetch "$WORKDIR/AppleCN.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/apple-cn.list
fetch "$WORKDIR/GamesCN.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-games-cn.list
fetch "$WORKDIR/CategoryPorn.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-porn.list
fetch "$WORKDIR/Private.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/private.list
fetch "$WORKDIR/PrivateIP.raw" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/private.list
fetch "$WORKDIR/AI.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ai-!cn.list
fetch "$WORKDIR/Ads.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ads.list
fetch "$WORKDIR/Download.list" https://raw.githubusercontent.com/DustinWin/domain-list-custom/domains/trackerslist.list
fetch "$WORKDIR/Speedtest.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-speedtest.list
fetch "$WORKDIR/Google.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/google.list
fetch "$WORKDIR/YouTube.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/youtube.list
fetch "$WORKDIR/GitHub.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/github.list
fetch "$WORKDIR/TikTok.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/tiktok.list
fetch "$WORKDIR/Twitter.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/twitter.list
for f in Facebook Instagram Meta Discord Whatsapp; do
  fetch "$WORKDIR/$f.list" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/${f,,}.list"
done
cat "$WORKDIR"/Telegram.list "$WORKDIR"/Facebook.list "$WORKDIR"/Instagram.list "$WORKDIR"/Meta.list "$WORKDIR"/Discord.list "$WORKDIR"/Whatsapp.list "$WORKDIR"/Twitter.list | sort -u > "$WORKDIR/ForeignChat.list"

python3 - "$WORKDIR" <<'PY'
from pathlib import Path
import json, sys, ipaddress
wd = Path(sys.argv[1])

def valid_domain(v):
    if not v or v.startswith('http') or '/' in v and not v.startswith('*.'): return False
    return True

def clean_line(raw):
    s=raw.strip()
    if not s or s.startswith('#') or s.startswith('//') or s.startswith(';'):
        return None
    return s

def parse_plain_domains(path):
    d={'domain':[], 'domain_suffix':[], 'domain_keyword':[], 'ip_cidr':[]}
    for raw in path.read_text(errors='ignore').splitlines():
        line=clean_line(raw)
        if not line: continue
        if line.startswith('+.'):
            val=line[2:]
            if valid_domain(val): d['domain_suffix'].append(val)
        elif line.startswith('.'):
            val=line[1:]
            if valid_domain(val): d['domain_suffix'].append(val)
        elif valid_domain(line):
            d['domain'].append(line)
    return {k:sorted(set(v)) for k,v in d.items()}

def parse_classical_domains(path):
    d={'domain':[], 'domain_suffix':[], 'domain_keyword':[], 'ip_cidr':[]}
    for raw in path.read_text(errors='ignore').splitlines():
        line=clean_line(raw)
        if not line: continue
        parts=[p.strip() for p in line.split(',', 2)]
        if len(parts)<2: continue
        typ,val=parts[0].upper(),parts[1]
        if typ=='DOMAIN' and valid_domain(val): d['domain'].append(val)
        elif typ=='DOMAIN-SUFFIX' and valid_domain(val): d['domain_suffix'].append(val)
        elif typ=='DOMAIN-KEYWORD' and val: d['domain_keyword'].append(val)
    return {k:sorted(set(v)) for k,v in d.items()}

def parse_plain_ip(path):
    d={'domain':[], 'domain_suffix':[], 'domain_keyword':[], 'ip_cidr':[]}
    for raw in path.read_text(errors='ignore').splitlines():
        line=clean_line(raw)
        if not line: continue
        try:
            d['ip_cidr'].append(str(ipaddress.ip_network(line, strict=False)))
        except Exception:
            pass
    return {k:sorted(set(v)) for k,v in d.items()}

def surge_ip_rule(cidr):
    try:
        net=ipaddress.ip_network(cidr, strict=False)
        typ='IP-CIDR6' if net.version == 6 else 'IP-CIDR'
    except Exception:
        typ='IP-CIDR6' if ':' in cidr else 'IP-CIDR'
    return f'{typ},{cidr},no-resolve'

def write_outputs(name, parsed):
    rule={k:v for k,v in parsed.items() if v}
    (wd/f'{name}.json').write_text(json.dumps({'version':1,'rules':[rule] if rule else []}, ensure_ascii=False, separators=(',',':')))
    domains=[]
    for v in parsed.get('domain',[]): domains.append(v)
    for v in parsed.get('domain_suffix',[]): domains.append('.'+v)
    for v in parsed.get('domain_keyword',[]): domains.append('keyword:'+v)
    domain_text='\n'.join(sorted(set(domains)))
    (wd/f'{name}.domain.txt').write_text(domain_text + ('\n' if domain_text else ''))
    surge=[]
    for v in parsed.get('domain',[]): surge.append(f'DOMAIN,{v}')
    for v in parsed.get('domain_suffix',[]): surge.append(f'DOMAIN-SUFFIX,{v}')
    for v in parsed.get('domain_keyword',[]): surge.append(f'DOMAIN-KEYWORD,{v}')
    for v in parsed.get('ip_cidr',[]): surge.append(surge_ip_rule(v))
    surge_text='\n'.join(sorted(set(surge)))
    (wd/f'{name}.surge.list').write_text(surge_text + ('\n' if surge_text else ''))
    cidrs=parsed.get('ip_cidr',[])
    ip_text='\n'.join(cidrs)
    (wd/f'{name}.ip.txt').write_text(ip_text + ('\n' if ip_text else ''))

domain_names=['CN','ChinaMedia','GlobalMedia','ForeignChat','Proxy','AppleCN','GamesCN','Speedtest','Telegram','CategoryPorn','Private','AI','Ads','Google','YouTube','GitHub','TikTok','Twitter']
for n in domain_names:
    write_outputs(n, parse_plain_domains(wd/f'{n}.list'))
write_outputs('Download', parse_classical_domains(wd/'Download.list'))
write_outputs('TelegramIP', parse_plain_ip(wd/'TelegramIP.list'))

cidrs=[]
for raw in (wd/'CNIP.raw').read_text().splitlines():
    line=raw.strip()
    if not line or line.startswith('#'): continue
    try: ipaddress.ip_network(line, strict=False); cidrs.append(line)
    except Exception: pass
cidrs=sorted(set(cidrs))
(wd/'CNIP.json').write_text(json.dumps({'version':1,'rules':[{'ip_cidr':cidrs}]}, separators=(',',':')))
ip_text='\n'.join(cidrs)
(wd/'CNIP.ip.txt').write_text(ip_text + ('\n' if ip_text else ''))
(wd/'CNIP.domain.txt').write_text('')
(wd/'CNIP.surge.list').write_text('\n'.join(surge_ip_rule(x) for x in cidrs) + ('\n' if cidrs else ''))

privateip=[]
for raw in (wd/'PrivateIP.raw').read_text().splitlines():
    line=raw.strip()
    if not line or line.startswith('#'): continue
    try: ipaddress.ip_network(line, strict=False); privateip.append(line)
    except Exception: pass
privateip=sorted(set(privateip))
(wd/'PrivateIP.json').write_text(json.dumps({'version':1,'rules':[{'ip_cidr':privateip}]}, separators=(',',':')))
privateip_text='\n'.join(privateip)
(wd/'PrivateIP.ip.txt').write_text(privateip_text + ('\n' if privateip_text else ''))
(wd/'PrivateIP.domain.txt').write_text('')
(wd/'PrivateIP.surge.list').write_text('\n'.join(surge_ip_rule(x) for x in privateip) + ('\n' if privateip else ''))
PY

rm -rf mihomo sing-box surge
mkdir -p mihomo sing-box surge
for name in CN Telegram TelegramIP ChinaMedia GlobalMedia ForeignChat Proxy AppleCN GamesCN CategoryPorn Private AI Ads Download Speedtest Google YouTube GitHub TikTok Twitter; do
cp "$WORKDIR/$name.surge.list" "surge/$name.list"
  if [ -s "$WORKDIR/$name.domain.txt" ]; then
    $MH convert-ruleset domain text "$WORKDIR/$name.domain.txt" "mihomo/$name.mrs"
  elif [ -s "$WORKDIR/$name.ip.txt" ]; then
    $MH convert-ruleset ipcidr text "$WORKDIR/$name.ip.txt" "mihomo/$name.mrs"
  else
    echo "Warning: $name has no convertible mihomo rules" >&2
    : > "mihomo/$name.mrs.skip"
  fi
  $SB rule-set compile -o "$PWD/sing-box/$name.srs" "$WORKDIR/$name.json"
  $SB rule-set decompile -o "$WORKDIR/$name.check.json" "$PWD/sing-box/$name.srs" >/dev/null
done
cp "$WORKDIR/CNIP.surge.list" surge/CNIP.list
$MH convert-ruleset ipcidr text "$WORKDIR/CNIP.ip.txt" mihomo/CNIP.mrs
$SB rule-set compile -o "$PWD/sing-box/CNIP.srs" "$WORKDIR/CNIP.json"
$SB rule-set decompile -o "$WORKDIR/CNIP.check.json" "$PWD/sing-box/CNIP.srs" >/dev/null
cp "$WORKDIR/PrivateIP.surge.list" surge/PrivateIP.list
$MH convert-ruleset ipcidr text "$WORKDIR/PrivateIP.ip.txt" mihomo/PrivateIP.mrs
$SB rule-set compile -o "$PWD/sing-box/PrivateIP.srs" "$WORKDIR/PrivateIP.json"
$SB rule-set decompile -o "$WORKDIR/PrivateIP.check.json" "$PWD/sing-box/PrivateIP.srs" >/dev/null

sha256sum mihomo/*.mrs sing-box/*.srs surge/*.list > SHA256SUMS
