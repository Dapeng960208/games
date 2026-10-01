"""Build the six reviewed shop sets and register their ImageGen atlas regions.

Usage: python tools/build_shop_equipment.py --sources artifacts/shop_equipment_sources.json
Source inputs are generation records. PNGs are copied unchanged; alpha bounds
are inspected to select atlas regions, preserving the generated RGBA pixels.
"""
import argparse
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SLOTS = ['weapon', 'head', 'chest', 'hands', 'feet', 'charm']
SUFFIXES = ['核心', '头冠', '衣甲', '手套', '长靴', '护符']
SUFFIXES_EN = ['Core', 'Crown', 'Armor', 'Gloves', 'Boots', 'Charm']
PRICES = [180, 140, 180, 120, 120, 160]
PASSIVES = [('damage_bonus', .01, '伤害', 'damage'), ('slow_resistance', .04, '减速抗性', 'slow resistance'),
            ('damage_reduction_bonus', .01, '伤害减免', 'damage reduction'), ('attack_speed_bonus', .012, '攻击速度', 'attack speed'),
            ('move_speed_bonus', .012, '移动速度', 'movement speed'), ('crit_bonus', .01, '暴击率', 'critical chance')]
SETS = [
    dict(id='S09', name='晨曦守誓', en='Dawn Oathkeeper', role='护盾防守 · 稳健反击', role_en='Shield defense · Steady counterattacks',
         condition='shielded', condition_zh='拥有护盾时', condition_en='While shielded', stat='damage_reduction_bonus', amount=.04,
         color='#F4CE74', material='暖白石甲、黄铜日轮与青蓝珐琅',
         stats=[{'attack':7,'armor':3},{'max_hp':15,'magic_resist':4},{'max_hp':24,'armor':8},{'attack':3,'armor':3},{'max_hp':12,'move_speed':.035},{'max_hp':18,'cooldown_reduction':.02}],
         tiers=[('拥有护盾时伤害减免 +4%。','While shielded, damage reduction +4%.'),('受到敌人有效伤害时获得最大生命 5% 的护盾，持续 4 秒；冷却 8 秒。','Taking enemy damage grants a shield equal to 5% of max HP for 4 s; cooldown 8 s.'),('拥有护盾时伤害 +8%。','While shielded, damage +8%.')]),
    dict(id='S10', name='苔叶远行', en='Mossleaf Wayfarer', role='机动走位 · 闪避护身', role_en='Mobility · Dash protection',
         condition='moving', condition_zh='移动时', condition_en='While moving', stat='move_speed_bonus', amount=.05,
         color='#90CC9D', material='嫩绿叶革、透光虫翼与琥珀扣件',
         stats=[{'attack':6,'attack_speed':.04},{'max_hp':12,'crit_chance':.025},{'max_hp':18,'magic_resist':5},{'attack_speed':.04,'attack':2},{'move_speed':.06,'armor':3},{'cooldown_reduction':.035,'max_hp':12}],
         tiers=[('移动时移动速度 +5%。','While moving, movement speed +5%.'),('闪避后移动速度 +10%，持续 3 秒；冷却 6 秒。','Dashing grants +10% movement speed for 3 s; cooldown 6 s.'),('闪避时获得最大生命 4% 的护盾，持续 4 秒；冷却 8 秒。','Dashing grants a shield equal to 4% of max HP for 4 s; cooldown 8 s.')]),
    dict(id='S11', name='星铃织法', en='Starbell Weaver', role='技能周转 · 资源管理', role_en='Spell cycling · Resource management',
         condition='resource_half', condition_zh='职业资源不少于一半时', condition_en='At 50% or more class resource', stat='damage_bonus', amount=.05,
         color='#ADB7ED', material='淡紫星纹布、瓷白镶边与黄铜小铃',
         stats=[{'ability_power':12,'magic_penetration':3},{'max_mana':12,'cooldown_reduction':.025},{'max_hp':16,'magic_resist':6},{'ability_power':5,'cooldown_reduction':.025},{'move_speed':.035,'magic_resist':3},{'ability_power':6,'max_mana':15}],
         tiers=[('职业资源不少于一半时伤害 +5%。','At 50% or more class resource, damage +5%.'),('成功消耗资源释放技能后伤害 +8%，持续 3 秒；冷却 6 秒。','Successfully casting a paid skill grants +8% damage for 3 s; cooldown 6 s.'),('每第 4 次有效普攻命中，使剩余冷却最长的主动技能减少 0.35 秒；冷却 5 秒。','Every fourth valid basic hit refunds 0.35 s from the active skill with the longest remaining cooldown; cooldown 5 s.')]),
    dict(id='S12', name='蜜翼锐眼', en='Honeywing Sharpsight', role='暴击连击 · 精准追击', role_en='Critical combos · Precision follow-up',
         condition='full_hp', condition_zh='生命全满时', condition_en='At full HP', stat='crit_bonus', amount=.05,
         color='#F1CA60', material='蜜黄甲壳、琥珀镜片与薄荷虫翼',
         stats=[{'attack':7,'crit_chance':.04},{'crit_chance':.03,'armor':3},{'max_hp':20,'armor':5},{'attack_speed':.045,'crit_multiplier':.10},{'move_speed':.04,'max_hp':10},{'crit_chance':.03,'armor_penetration':3}],
         tiers=[('生命全满时暴击率 +5%。','At full HP, critical chance +5%.'),('有效攻击暴击后攻击速度 +8%，持续 3 秒；冷却 6 秒。','A valid critical hit grants +8% attack speed for 3 s; cooldown 6 s.'),('有效攻击暴击时对首目标追加本次原始伤害 30% 的非暴击伤害；冷却 5 秒。','A valid critical hit adds non-critical damage equal to 30% of its raw strike to the primary target; cooldown 5 s.')]),
    dict(id='S13', name='南瓜缝卫', en='Pumpkin Stitchwarden', role='续航恢复 · 击杀补给', role_en='Sustain · Kill recovery',
         condition='injured', condition_zh='生命未满且存活时', condition_en='While alive and injured', stat='attack_speed_bonus', amount=.05,
         color='#F3AF71', material='赭橘绗缝皮甲、亚麻缝线与南瓜籽刻纹',
         stats=[{'attack':6,'max_hp':10},{'max_hp':18,'magic_resist':3},{'max_hp':26,'armor':5},{'attack':3,'attack_speed':.03},{'move_speed':.035,'max_hp':12},{'max_hp':20,'magic_resist':4}],
         tiers=[('生命未满且存活时攻击速度 +5%。','While alive and injured, attack speed +5%.'),('有效攻击击杀敌人后恢复最大生命 2%；冷却 5 秒，遵守每秒 3% 装备治疗上限。','A valid attack kill restores 2% max HP; cooldown 5 s, subject to the 3% per-second equipment healing cap.'),('有效攻击击杀敌人后获得最大生命 5% 的护盾，持续 4 秒；冷却 8 秒。','A valid attack kill grants a shield equal to 5% max HP for 4 s; cooldown 8 s.')]),
    dict(id='S14', name='赤陶战意', en='Terracotta Battleheart', role='低血反击 · 战鼓爆发', role_en='Low-HP counterattack · Drum burst',
         condition='low_hp', condition_zh='存活且生命不高于一半时', condition_en='While alive at 50% HP or less', stat='damage_bonus', amount=.06,
         color='#ED957A', material='珊瑚赤陶、靛蓝战鼓皮与圆润兽牙',
         stats=[{'attack':8,'armor_penetration':3},{'max_hp':16,'armor':4},{'max_hp':22,'armor':7},{'attack':4,'attack_speed':.03},{'move_speed':.035,'armor':3},{'damage_bonus':.025,'max_hp':15}],
         tiers=[('存活且生命不高于一半时伤害 +6%。','While alive at 50% HP or less, damage +6%.'),('生命不高于一半时受到敌人有效伤害，攻击速度 +10%，持续 3 秒；冷却 8 秒。','Taking enemy damage at 50% HP or less grants +10% attack speed for 3 s; cooldown 8 s.'),('存活且生命不高于一半时，有效攻击向最多 3 名敌人各追加本次原始伤害 25% 的非暴击伤害；冷却 6 秒。','While alive at 50% HP or less, a valid hit adds non-critical damage equal to 25% of the raw strike to up to 3 enemies; cooldown 6 s.')]),
]


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def build(sources_path):
    from PIL import Image
    equipment = read(ROOT/'data/equipment.json')
    sets = read(ROOT/'data/sets.json')
    sources = read(sources_path)
    manifest = dict(version=2, enabled=True, created_date='2026-10-01', art_direction='18–30 岁青年奇幻；利落成人比例、精致锻造、可信材质，保留暖阳与明亮配色，去除萌化表情和玩具比例', items={})
    for index, spec in enumerate(SETS):
        set_id = spec['id']
        record = sources[set_id]
        source = Path(record['source'].split(' as ')[-1])
        target = ROOT/f'assets/generated/equipment/storybook_shop_{set_id}_v2.png'
        shutil.copyfile(source, target)
        with Image.open(target) as image:
            assert image.mode == 'RGBA' and image.size == (1536, 1024), (target, image.mode, image.size)
            alpha = image.getchannel('A')
            assert alpha.getextrema()[0] == 0, 'Atlas must retain genuine transparency'
            thresholds = {str(t): dict(name=f'{spec["name"]} · {t} 件', name_en=f'{spec["en"]} · {t} pieces', text=zh, text_en=en)
                          for t, (zh, en) in zip([2, 4, 6], spec['tiers'])}
            sets[set_id] = dict(id=set_id, name=spec['name'], name_en=spec['en'], status_id='shop_'+set_id,
                               status_name=spec['role'].split(' · ')[0], status_name_en=spec['role_en'].split(' · ')[0],
                               shop_role=spec['role'], shop_role_en=spec['role_en'], color=spec['color'], visual=spec['material'],
                               thresholds=thresholds, unlock_boss='', shop_passive=dict(condition=spec['condition'], stat=spec['stat'], amount=spec['amount']))
            for slot_index, slot in enumerate(SLOTS):
                eq_id = f'EQ{61+index*6+slot_index:02d}'
                stat, amount, caption, caption_en = PASSIVES[slot_index]
                affix = f'套装织纹：{spec["condition_zh"]}，{caption} +{amount*100:g}%。'
                affix_en = f'Set weave: {spec["condition_en"]}, {caption_en} +{amount*100:g}%.'
                item = dict(id=eq_id, name=spec['name']+SUFFIXES[slot_index], name_en=spec['en']+' '+SUFFIXES_EN[slot_index],
                            description=spec['role']+'。'+affix, description_en=spec['role_en']+'. '+affix_en,
                            slot=slot, set_id=set_id, price=PRICES[slot_index], base_stats=spec['stats'][slot_index],
                            affix_id='FX_'+eq_id, affix_text=affix, affix_text_en=affix_en, unlock_boss='', shop_only=True,
                            tier=set_id, tier_en=set_id, visual=spec['material'],
                            combat_passive=dict(condition=spec['condition'], stat=stat, amount=amount))
                equipment[eq_id] = item
                x, y = slot_index % 3 * 512, slot_index // 3 * 512
                bounds = alpha.crop((x, y, x+512, y+512)).point(lambda a: 255 if a >= 16 else 0).getbbox()
                assert bounds and (bounds[2]-bounds[0]) > 200 and (bounds[3]-bounds[1]) > 200
                region = [x+bounds[0], y+bounds[1], bounds[2]-bounds[0], bounds[3]-bounds[1]]
                manifest['items'][eq_id] = dict(texture='res://'+target.relative_to(ROOT).as_posix(), region=region,
                                              slot=slot, name=item['name'], name_en=item['name_en'], set_id=set_id,
                                              source_size=list(image.size), cell=[x,y,512,512], alpha_threshold=16)
        write(target.with_suffix('.prompt.json'), dict(tool=record['tool'], prompt=record['prompt'], transparent_background=True,
                                                      created_date=record['created_date'], output=target.name, source_generation=source.name))
    write(ROOT/'data/equipment.json', equipment)
    write(ROOT/'data/sets.json', sets)
    write(ROOT/'assets/generated/equipment/storybook_shop_sets_v2.manifest.json', manifest)
    print('Shop equipment: 36 new items / 6 sets / 6 unchanged RGBA atlases registered; total 96 items / 14 sets.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--sources', type=Path, required=True)
    build(parser.parse_args().sources)
