import json, urllib.parse, urllib.request
import os, sys
# Downloads the public-domain paintings the website dithers. Usage: python3 tools/site/fetch-art.py
OUT = os.path.join(os.path.dirname(__file__), "../../build/site-art/")
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "SowerSiteBuild/1.0 (jemmy@gazhenko.dev)"}
items = {
    "millet-sower.jpg": "File:Jean-François Millet - The Sower - Google Art Project.jpg",
    "vangogh-sower.jpg": "File:Vincent van Gogh - Le Semeur dans un champ de blé au soleil couchant (1888).jpg",
    "vangogh-wheatfield.jpg": "File:Vincent van Gogh - Wheatfield under thunderclouds - Google Art Project.jpg",
    "vangogh-sower-painting.jpg": "File:Vincent van Gogh - The Sower - c. 17-28 June 1888.jpg",
    "millet-gleaners.jpg": "File:Jean-François Millet - Gleaners - Google Art Project.jpg",
}
credits = {}
for out, title in items.items():
    q = "https://commons.wikimedia.org/w/api.php?action=query&prop=imageinfo&iiprop=url|extmetadata&iiurlwidth=2400&format=json&titles=" + urllib.parse.quote(title)
    data = json.load(urllib.request.urlopen(urllib.request.Request(q, headers=UA)))
    info = list(data["query"]["pages"].values())[0]["imageinfo"][0]
    meta = info["extmetadata"]
    url = info.get("thumburl") or info["url"]

    with urllib.request.urlopen(urllib.request.Request(url, headers=UA)) as r, open(OUT + out, "wb") as f:
        f.write(r.read())
    credits[out] = {"title": title, "page": info.get("descriptionurl"), "license": meta.get("LicenseShortName", {}).get("value"), "date": meta.get("DateTimeOriginal", {}).get("value", "")[:60]}
    print(out, credits[out]["license"], credits[out]["page"])
json.dump(credits, open(OUT + "credits.json", "w"), indent=2, ensure_ascii=False)
