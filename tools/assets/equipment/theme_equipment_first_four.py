"""Assign existing, stable equipment IDs to the approved four prototype races."""
from pathlib import Path
import json

ROOT = next(p for p in Path(__file__).resolve().parents if (p / 'project.godot').is_file())
path = ROOT / 'data/equipment/equipment.json'
items = json.loads(path.read_text(encoding='utf-8'))
sets_path = ROOT / 'data/equipment/sets.json'
sets = json.loads(sets_path.read_text(encoding='utf-8'))
themes = {
    'B01': ('晴辉构装', 'Sunlit Constructs', '白石、黄铜齿轮与青蓝魔晶'),
    'B02': ('琥珀虫族', 'Amber Brood', '彩色甲壳、虫翼、琥珀与蚁酸晶体'),
    'B03': ('南瓜守夜', 'Pumpkin Watch', '南瓜灯、缝补布料、木桶与薄荷铜扣'),
    'B04': ('赤岩战寨', 'Redrock Warband', '赤陶、战鼓皮革、兽牙与靛蓝图腾'),
}
set_themes = {
    'S01': ('B01', '日曜炉心', 'Solar Hearth'),
    'S02': ('B01', '鸣钟机关', 'Chiming Clockwork'),
    'S03': ('B02', '凝露虫翼', 'Dewwing Carapace'),
    'S04': ('B02', '蚁酸甲壳', 'Formic Shell'),
    'S05': ('B03', '南瓜守夜', 'Pumpkin Watch'),
    'S06': ('B03', '缝补回声', 'Patchwork Echo'),
    'S07': ('B04', '战鼓猎牙', 'Wardrum Fang'),
    'S08': ('B04', '风嚎图腾', 'Windhowl Totem'),
}
forms = {
    'weapon': ('核心', 'Core'), 'head': ('冠盔', 'Helm'),
    'chest': ('胸甲', 'Armor'), 'hands': ('护手', 'Gauntlets'),
    'feet': ('战靴', 'Boots'), 'charm': ('护符', 'Charm'),
}
common = ['EQ01', 'EQ02', 'EQ11', 'EQ12', 'EQ21', 'EQ22',
          'EQ31', 'EQ32', 'EQ41', 'EQ42', 'EQ51', 'EQ52']
common_races = {item_id: f'B{1 + index % 4:02}' for index, item_id in enumerate(common)}
for item_id, item in items.items():
    set_id = item.get('set_id', '')
    if set_id in set_themes:
        race, name, name_en = set_themes[set_id]
    else:
        race = common_races[item_id]
        name, name_en, _ = themes[race]
        name += '旅者'
        name_en += ' Traveler'
    form, form_en = forms[item['slot']]
    item.setdefault('original_name', item['name'])
    item['name'] = name + form
    item['name_en'] = name_en + ' ' + form_en
    item['race_id'] = race
    item['race_name'] = themes[race][0]
    item['race_name_en'] = themes[race][1]
    item['race_material'] = themes[race][2]
    item['visual'] = themes[race][2] + '；' + item['name']
    item['drop_origin'] = race
for set_id, (race, name, name_en) in set_themes.items():
    definition = sets[set_id]
    definition.setdefault('original_name', definition['name'])
    definition.update(name=name, name_en=name_en, race_id=race, visual=themes[race][2])
    for count, threshold in definition['thresholds'].items():
        threshold['name'] = f'{name} · {count} 件'
        threshold['name_en'] = f'{name_en} · {count} pieces'
    # Preserve stable gameplay IDs and proc descriptions; the race material
    # provides the fiction for fire, shock, dew-chill, acid, guard and pressure.

path.write_text(json.dumps(items, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
sets_path.write_text(json.dumps(sets, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
mapping = {key: {field: value[field] for field in
           ('name', 'name_en', 'race_id', 'race_name', 'race_name_en', 'race_material', 'slot')}
           for key, value in items.items()}
(ROOT / 'artifacts/first_four_equipment_names.json').write_text(
    json.dumps(mapping, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'items': len(items), 'races': {
    race: sum(item['race_id'] == race for item in items.values()) for race in themes}}, ensure_ascii=False))
