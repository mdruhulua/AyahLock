"""Checks data sources for tafsir and IndoPak text. Run by .github/workflows/probe.yml."""
import json, sys, urllib.request
from fontTools.ttLib import TTFont

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "AyahLock-probe"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:
        return 0, str(e).encode()

def note(title, msg):
    msg = msg.replace("%", "%25").replace("\n", "%0A")
    print(f"::notice title={title}::{msg}")

out = []
def report(label, url, show=400):
    status, body = get(url)
    text = body.decode("utf-8", "replace")
    out.append(f"{status} {label} {url}\n   {text[:show]}")
    return status, text

# Tafsir sources: whole-surah files, on jsDelivr and raw GitHub
for slug in []:
    for host in ["https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir", "https://raw.githubusercontent.com/spa5k/tafsir_api/main/tafsir"]:
        for surah in (2, 112):
            status, body = get(f"{host}/{slug}/{surah}.json")
            line = f"{status} {slug} s{surah} {host.split('/')[2]}"
            if status == 200:
                try:
                    rows = json.loads(body)
                    empty = [r.get("ayah") for r in rows if not (r.get("text") or "").strip()]
                    keys = sorted(rows[0].keys()) if rows else []
                    html = sum("<" in (r.get("text") or "") for r in rows)
                    a255 = next((r.get("text","")[:60] for r in rows if r.get("ayah") == 255), "")
                    line += f" rows={len(rows)} keys={keys} empty={len(empty)} first_empty={empty[:8]} html_rows={html} 255={a255!r}"
                except Exception as e:
                    line += f" parse error {e}"
            out.append(line)
note("Tafsir", "\n".join(out)); out.clear()

# Digital Khatt IndoPak text candidates
font = TTFont("App/Fonts/DigitalKhattIndoPak.ttf")
cmap = set(font.getBestCmap().keys())
def coverage(texts):
    chars = set(ord(c) for t in texts for c in t)
    missing = sorted(c for c in chars - cmap if c != 0x20)
    return f"n={len(texts)} distinct={len(chars)} missing={len(missing)} {[hex(c) for c in missing[:20]]}"
cands = [
 "https://api.quran.com/api/v4/quran/verses/digital_khatt_indopak?chapter_number=2",
 "https://api.quran.com/api/v4/quran/verses/text_digital_khatt_indopak?chapter_number=2",
 "https://api.quran.com/api/v4/verses/by_key/2:1?fields=text_digital_khatt_indopak",
 "https://api.quran.com/api/v4/verses/by_chapter/112?fields=text_digital_khatt_indopak,text_indopak_nastaleeq",
 "https://qul.tarteel.ai/api/v1/verses/2:1.json",
 "https://qul.tarteel.ai/api/v1/verses/2:1.json?script=text_digital_khatt_indopak",
 "https://qul.tarteel.ai/resources/quran-script/566/download?format=json",
 "https://qul.tarteel.ai/resources/quran-script/566.json",
 "https://api.islamic.app/v1/quran/verses/digital_khatt_indopak",
 "https://static-cdn.tarteel.ai/qul/fonts/dk/DigitalKhattIndoPak.otf",
]
for url in cands:
    status, body = get(url)
    ctype = ""
    text = body[:2000].decode("utf-8", "replace")
    line = f"{status} {url} bytes={len(body)}\n   {text[:260]!r}"
    if status == 200 and body[:1] in (b"{", b"["):
        try:
            data = json.loads(body)
            vs = data.get("verses") or ([data["verse"]] if "verse" in data else [])
            for k in ("text_digital_khatt_indopak", "text"):
                texts = [v.get(k) for v in vs if isinstance(v, dict) and v.get(k)]
                if texts:
                    line += f"\n   field={k} " + coverage(texts) + f" first={texts[0][:60]!r}"
                    break
        except Exception as e:
            line += f" json err {e}"
    out.append(line)
note("DK-IndoPak", "\n".join(out))
