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
fetch "$WORKDIR/cn-domain.list" https://raw.githubusercontent.com/Rabbit-Spec/Surge/Master/Rules/China.list
fetch "$WORKDIR/cn-ip.raw" https://raw.githubusercontent.com/nekolsd/geoip/release/text/cn.txt
fetch "$WORKDIR/telegram.list" https://raw.githubusercontent.com/Rabbit-Spec/Surge/Master/Rules/Telegram.list
fetch "$WORKDIR/domestic-media.list" https://raw.githubusercontent.com/Rabbit-Spec/Surge/Master/Rules/ChinaMedia.list
fetch "$WORKDIR/foreign-media.list" https://raw.githubusercontent.com/Rabbit-Spec/Surge/Master/Rules/GlobalMedia.list
fetch "$WORKDIR/proxy.list" https://raw.githubusercontent.com/Rabbit-Spec/Surge/Master/Rules/Proxy.list
fetch "$WORKDIR/apple-cn.list" https://raw.githubusercontent.com/DustinWin/domain-list-custom/domains/apple-cn.list
fetch "$WORKDIR/games-cn.list" https://raw.githubusercontent.com/DustinWin/domain-list-custom/domains/games-cn.list
fetch "$WORKDIR/category-porn.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-porn.list
fetch "$WORKDIR/private.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/private.list
fetch "$WORKDIR/privateip.raw" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/private.list
fetch "$WORKDIR/ai.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ai-!cn.list
fetch "$WORKDIR/ads.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ads-all.list
fetch "$WORKDIR/download.list" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-android-app-download.list
for f in Telegram Facebook Instagram Meta; do
  fetch "$WORKDIR/$f.list" "https://raw.githubusercontent.com/Rabbit-Spec/Surge/Master/Rules/$f.list" || true
done
for f in Discord Whatsapp Twitter; do
  fetch "$WORKDIR/$f.list" "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Surge/$f/$f.list" || true
done
cat "$WORKDIR"/Telegram.list "$WORKDIR"/Facebook.list "$WORKDIR"/Instagram.list "$WORKDIR"/Meta.list "$WORKDIR"/Discord.list "$WORKDIR"/Whatsapp.list "$WORKDIR"/Twitter.list 2>/dev/null | sort -u > "$WORKDIR/foreign-chat.list"

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

def parse_surge(path):
    d={'domain':[], 'domain_suffix':[], 'domain_keyword':[], 'ip_cidr':[]}
    for raw in path.read_text(errors='ignore').splitlines():
        line=clean_line(raw)
        if not line: continue
        parts=[p.strip() for p in line.split(',')]
        if len(parts)<2: continue
        typ,val=parts[0].upper(),parts[1]
        if typ=='DOMAIN' and valid_domain(val): d['domain'].append(val)
        elif typ=='DOMAIN-SUFFIX' and valid_domain(val): d['domain_suffix'].append(val)
        elif typ=='DOMAIN-KEYWORD' and val: d['domain_keyword'].append(val)
        elif typ in ('IP-CIDR','IP-CIDR6'):
            try: ipaddress.ip_network(val, strict=False); d['ip_cidr'].append(val)
            except Exception: pass
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

names=['cn-domain','telegram','domestic-media','foreign-media','foreign-chat','proxy','apple-cn','games-cn']
for n in names:
    write_outputs(n, parse_surge(wd/f'{n}.list'))
for n in ['category-porn','private','ai','ads','download']:
    write_outputs(n, parse_plain_domains(wd/f'{n}.list'))

cidrs=[]
for raw in (wd/'cn-ip.raw').read_text().splitlines():
    line=raw.strip()
    if not line or line.startswith('#'): continue
    try: ipaddress.ip_network(line, strict=False); cidrs.append(line)
    except Exception: pass
cidrs=sorted(set(cidrs))
(wd/'cn-ip.json').write_text(json.dumps({'version':1,'rules':[{'ip_cidr':cidrs}]}, separators=(',',':')))
ip_text='\n'.join(cidrs)
(wd/'cn-ip.ip.txt').write_text(ip_text + ('\n' if ip_text else ''))
(wd/'cn-ip.domain.txt').write_text('')
(wd/'cn-ip.surge.list').write_text('\n'.join(surge_ip_rule(x) for x in cidrs) + ('\n' if cidrs else ''))

privateip=[]
for raw in (wd/'privateip.raw').read_text().splitlines():
    line=raw.strip()
    if not line or line.startswith('#'): continue
    try: ipaddress.ip_network(line, strict=False); privateip.append(line)
    except Exception: pass
privateip=sorted(set(privateip))
(wd/'privateip.json').write_text(json.dumps({'version':1,'rules':[{'ip_cidr':privateip}]}, separators=(',',':')))
privateip_text='\n'.join(privateip)
(wd/'privateip.ip.txt').write_text(privateip_text + ('\n' if privateip_text else ''))
(wd/'privateip.domain.txt').write_text('')
(wd/'privateip.surge.list').write_text('\n'.join(surge_ip_rule(x) for x in privateip) + ('\n' if privateip else ''))
PY

rm -rf mihomo sing-box surge
mkdir -p mihomo sing-box surge
for name in cn-domain telegram domestic-media foreign-media foreign-chat proxy apple-cn games-cn category-porn private ai ads download; do
cp "$WORKDIR/$name.surge.list" "surge/$name.list"
  if [ -s "$WORKDIR/$name.domain.txt" ]; then
    $MH convert-ruleset domain text "$WORKDIR/$name.domain.txt" "mihomo/$name.mrs"
  elif [ -s "$WORKDIR/$name.ip.txt" ]; then
    $MH convert-ruleset ipcidr text "$WORKDIR/$name.ip.txt" "mihomo/$name.mrs"
  else
    echo "Warning: $name has no convertible mihomo rules" >&2
    : > "mihomo/$name.mrs.skip"
  fi
  $SB rule-set compile "$WORKDIR/$name.json" -o "sing-box/$name.srs"
  $SB rule-set decompile "sing-box/$name.srs" -o "$WORKDIR/$name.check.json" >/dev/null
done
cp "$WORKDIR/cn-ip.surge.list" surge/cn-ip.list
$MH convert-ruleset ipcidr text "$WORKDIR/cn-ip.ip.txt" mihomo/cn-ip.mrs
$SB rule-set compile "$WORKDIR/cn-ip.json" -o sing-box/cn-ip.srs
$SB rule-set decompile sing-box/cn-ip.srs -o "$WORKDIR/cn-ip.check.json" >/dev/null
cp "$WORKDIR/privateip.surge.list" surge/privateip.list
$MH convert-ruleset ipcidr text "$WORKDIR/privateip.ip.txt" mihomo/privateip.mrs
$SB rule-set compile "$WORKDIR/privateip.json" -o sing-box/privateip.srs
$SB rule-set decompile sing-box/privateip.srs -o "$WORKDIR/privateip.check.json" >/dev/null

sha256sum mihomo/*.mrs sing-box/*.srs surge/*.list > SHA256SUMS
