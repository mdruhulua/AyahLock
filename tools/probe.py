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
for slug in ["en-tafisr-ibn-kathir", "en-tafsir-maarif-ul-quran", "bn-tafseer-ibn-e-kaseer", "bn-tafsir-ahsanul-bayaan", "bn-tafsir-abu-bakr-zakaria"]:
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

# IndoPak text sources
font = TTFont("App/Fonts/DigitalKhattIndoPak.ttf")
cmap = set(font.getBestCmap().keys())
for label, url in [
    ("qcom-indopak-nastaleeq", "https://api.quran.com/api/v4/quran/verses/indopak_nastaleeq"),
    ("qcom-indopak", "https://api.quran.com/api/v4/quran/verses/indopak"),
    ("islamicapp-indopak", "https://api.islamic.app/v1/quran/verses/indopak"),
]:
    status, text = report(label, url, 300)
    if status != 200:
        continue
    try:
        data = json.loads(text)
    except Exception as e:
        out.append(f"   not JSON: {e}")
        continue
    verses = data.get("verses") or data.get("ayahs") or (data.get("data") or {}).get("ayahs") or []
    key = next((k for k in (verses[0].keys() if verses else []) if k.startswith("text")), None)
    texts = [v.get(key, "") for v in verses]
    chars = set(ord(c) for t in texts for c in t)
    missing = sorted(c for c in chars - cmap if c not in (0x20,))
    sample = {v.get("verse_key"): v.get(key) for v in verses if v.get("verse_key") in ("1:1", "2:1", "112:1")}
    out.append(f"   verses={len(verses)} field={key} distinct_chars={len(chars)} missing_in_font={[hex(c) for c in missing]}\n   sample={json.dumps(sample, ensure_ascii=False)[:500]}\n   2:1 codes={' '.join('%04X' % ord(c) for c in (sample.get('2:1') or ''))}")

note("IndoPak", "\n".join(out))
