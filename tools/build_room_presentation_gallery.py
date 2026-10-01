"""Build an ignored local gallery from the genuine room_presentation GPU captures."""
from __future__ import annotations

import argparse
import html
import json
from pathlib import Path


def contact_sheets(output: Path) -> list[Path]:
    """Readable QA thumbnails; original GPU PNGs remain alongside each sheet."""
    from PIL import Image, ImageDraw, ImageFont

    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    font_path = Path("C:/Windows/Fonts/msyh.ttc")
    font = ImageFont.truetype(str(font_path), 21) if font_path.is_file() else ImageFont.load_default()
    groups: dict[str, list[tuple[str, str]]] = {}
    for room in manifest["rooms"]:
        for field in ("center", "overview"):
            groups.setdefault(f'{room["biome"]}_{field}', []).append((room[field], f'{room["id"]} · {room["name"]}'))
    for path in sorted(output.glob("*_ui_*.png")):
        groups.setdefault(path.stem.split("_ui_")[0] + "_ui", []).append((path.name, path.stem))
    results = []
    for key, sources in groups.items():
        card_height = 495 if key.endswith("overview") else 410
        sheet = Image.new("RGB", (1360, ((len(sources) + 1) // 2) * card_height), "#f5eddf")
        draw = ImageDraw.Draw(sheet)
        for index, (filename, label) in enumerate(sources):
            x, y = (index % 2) * 680 + 16, (index // 2) * card_height
            draw.text((x, y + 8), label, fill="#392843", font=font)
            with Image.open(output / filename) as source:
                source.thumbnail((648, card_height - 50), Image.Resampling.LANCZOS)
                sheet.paste(source, (x, y + 42))
        destination = output / f"contact_{key}.png"
        sheet.save(destination)
        results.append(destination)
    return results


def build(output: Path) -> Path:
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    rooms = manifest["rooms"]
    gallery_title = f'{len(rooms)}房实际运行图册' if rooms else "房间UI定向检查图册"
    scope = "预备定向检查 · " if manifest.get("partial") else ""
    cards = []
    for room in rooms:
        name = html.escape(f'{room["id"]} · {room["name"]}')
        caption = html.escape(room["caption"])
        emblem = html.escape(room["emblem"])
        shots = []
        for field, label in (("center", "实际中心镜头 · HUD"), ("overview", "全场概览 · 拉远镜头 / 青线为真实可走边界")):
            filename = room[field]
            if not (output / filename).is_file():
                raise FileNotFoundError(output / filename)
            shots.append(f'<figure><a href="{html.escape(filename)}" target="_blank"><img loading="lazy" src="{html.escape(filename)}" alt="{name} {label}"></a><figcaption>{label}</figcaption></figure>')
        cards.append(f'<article data-biome="{room["biome"]}"><h2>{name}</h2><p>{caption}<span>{emblem}</span></p><div class="shots">{"".join(shots)}</div></article>')
    extra = sorted(output.glob("*_ui_*.png"))
    extra_cards = "".join(f'<figure><a href="{p.name}" target="_blank"><img loading="lazy" src="{p.name}" alt="{p.stem}"></a><figcaption>{p.stem}</figcaption></figure>' for p in extra)
    page = f'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{gallery_title}</title>
<style>body{{margin:0;background:#f5eddf;color:#392843;font:16px/1.6 system-ui,sans-serif}}header{{position:sticky;top:0;z-index:2;background:#fff8eaeF;border-bottom:1px solid #baa27f;padding:12px 3vw;backdrop-filter:blur(12px)}}h1{{margin:0;font-size:23px}}nav{{display:flex;gap:8px;flex-wrap:wrap}}button{{background:#fff3d7;color:#392843;border:1px solid #baa27f;border-radius:6px;padding:5px 15px;font:inherit;cursor:pointer}}button[aria-pressed="true"]{{background:#398f96;color:white}}main{{max-width:1800px;margin:24px auto;padding:0 3vw}}article{{margin:0 0 26px;padding:18px;background:#fff9ed;border:1px solid #ceb992;border-radius:12px}}h2{{margin:0;font-size:21px}}p{{margin:4px 0 14px}}span{{font-size:12px;color:#766474;float:right}}.shots{{display:grid;grid-template-columns:1fr 1fr;gap:16px}}figure{{margin:0}}img{{width:100%;height:auto;display:block;border-radius:6px;background:#392843}}figcaption{{color:#766474;font-size:13px;margin:6px 0}}#extra{{display:grid;grid-template-columns:1fr 1fr;gap:20px}}small{{display:block;color:#766474}}@media(max-width:900px){{.shots,#extra{{grid-template-columns:1fr}}}}</style>
<header><h1>{gallery_title}</h1><small>{scope}GPU 实机：{manifest["gpu"]} · {manifest["checks"]} 项检查 / {manifest["failures"]} 失败 · 中心镜头使用运行 HUD；概览临时拉远相机，青线标真实可走边界，浅金点标入口、出口与目标。</small><nav><button data-filter="all" aria-pressed="true">全部 {len(rooms)} 房</button><button data-filter="B01">晴辉遗庭</button><button data-filter="B02">琥珀虫巢</button><button data-filter="B03">南瓜墓镇</button><button data-filter="B04">赤岩战寨</button><button data-filter="ui">三窗口与中英文</button></nav></header>
<main><section id="rooms">{"".join(cards)}</section><section id="extra" hidden>{extra_cards}</section></main>
<script>document.querySelectorAll('button').forEach(button=>button.onclick=()=>{{const filter=button.dataset.filter;document.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));document.querySelector('#rooms').hidden=filter==='ui';document.querySelector('#extra').hidden=filter!=='ui';document.querySelectorAll('article').forEach(card=>card.hidden=filter!=='all'&&card.dataset.biome!==filter);}});</script></html>'''
    # Explicit rule overrides the gallery's grid display for hidden sections.
    page = page.replace("</style>", "[hidden]{display:none!important}</style>")
    destination = output / "index.html"
    destination.write_text(page, encoding="utf-8")
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent.parent / "artifacts" / "room-presentation")
    parser.add_argument("--contact-sheets", action="store_true", help="Also make QA contact sheets (Pillow is in the bundled workspace Python runtime).")
    args = parser.parse_args()
    output = args.output.resolve()
    print(build(output))
    if args.contact_sheets:
        for result in contact_sheets(output):
            print(result)
