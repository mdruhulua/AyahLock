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

# Tafsir sources
for slug in ["en-tafisr-ibn-kathir", "bn-tafseer-ibn-e-kaseer", "bn-tafsir-ahsanul-bayaan", "bn-tafsir-abu-bakr-zakaria", "en-tafsir-maarif-ul-quran"]:
    report("jsdelivr-ayah", f"https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir/{slug}/2/255.json", 300)
    report("jsdelivr-surah", f"https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir/{slug}/112.json", 300)
report("jsdelivr-editions", "https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir/editions.json", 1500)
report("qcom-tafsir", "https://api.quran.com/api/v4/tafsirs/169/by_ayah/2:255", 300)
report("qcom-tafsir-list", "https://api.quran.com/api/v4/resources/tafsirs", 300)
report("islamicapp-tafsir", "https://api.islamic.app/v1/verses/by_key/2:255?tafsirs=en-tafisr-ibn-kathir", 300)

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

note("Probe", "\n".join(out))
