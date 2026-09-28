# 原创角色素材 / Character Art

生成日期：2026-09-28  
用途：M1 原生 Godot 2D 游戏中的 1 名拾荒者与 1 种近战敌人。  
方式：内置 `image_gen`；两张图片独立生成；未使用参考 IP、第三方角色或网络素材。  
处理：生成后直接复制 PNG，保持原始 RGBA 与透明度，没有抠图、重绘、裁剪或重新编码。  
两张实际输出尺寸均为 **1254 × 1254**（提示词请求 1024 方图，工具实际提供 1254 方图；工程按显示尺寸缩放）。

## 拾荒者

- 工程路径：`assets/characters/salvager.png`
- 暂存绝对路径：`D:\dev\test-game\assets\characters\salvager.png`
- 原图路径：`C:\Users\guojianpeng\.codex\generated_images\01a0e74f-01cb-71e2-82e4-45b016596dbb\exec-3adbf8aa-7bf9-430b-a3fc-4e1146f2c877.png`
- SHA-256：`AFC21EAD0CF5E7A8A49A95F8921648919D796F24C17597858677EBC9CD02E9E1`
- 原创设计：铜质窄镜矿工头盔、重型短外套、机械风箱背包、独特铁铜提灯；右手空置以便游戏实时绘制指向武器。
- 透明检查：32-bit ARGB；908,521 个 alpha=0 像素；左上角 alpha=0；有效主体边界（alpha>10）为 x=198..1064, y=13..1240。
- 视觉检查：已用 `view_image` 打开工程 PNG；完整单体、脚和背包没有裁切，铜盔、冷青镜片与暖灯明显。实际为偏高角度的前向俯视立绘。64px 实机缩放效果由主工程渲染验证。

### 最终生成提示词

```text
Use case: stylized-concept. Asset type: final production transparent PNG sprite for an original native 2D top-down action game, Abyss Salvager. Style: high-quality hand-painted 2D game sprite, bold economical brushwork, crisp easily readable silhouette at 64 pixels, simplified material detailing, restrained rim light, neither photorealistic nor extremely chibi. Orthographic camera looking downward at about 65 degrees from horizontal; subject faces toward the bottom of the image and top of head/shoulders visible. Square 1024 by 1024 canvas, one complete subject centered, subject fills about 80 percent with all appendages contained. Actual fully transparent alpha background, no background colors, no floor, no cast ground shadow, no scenery, no text, no watermark, no logo, no UI border. Palette: deep charcoal blue #17232C industrial surfaces, worn copper #B7884B, amber #E6AA4A light and small cool cyan #67C7D5 accents. Fully original character design, no references to existing intellectual property. Subject: a solitary practical mine-scavenger adventurer, short sturdy proportions, heavy dark protective mining coat and scuffed chunky mine boots. A copper miner helmet has a single very narrow cyan visor; faceless. Small mechanical bellows and coil backpack visible behind shoulders. A distinctive caged iron-and-copper lantern hangs on the character's left side, warm amber light confined to the lantern and nearby coat. Right hand empty, no gun, no long weapon. Hands low in neutral action-ready standing pose, both feet distinct, facing image bottom. Industrial and worn, mysterious underground miner, not a space marine. Prioritize recognizable helmet, bulky coat, lantern silhouette and clear top-down view.
```

## 锈壳寄生体

- 工程路径：`assets/characters/rust_mite.png`
- 暂存绝对路径：`D:\dev\test-game\assets\characters\rust_mite.png`
- 原图路径：`C:\Users\guojianpeng\.codex\generated_images\01a0e74f-01cb-71e2-82e4-45b016596dbb\exec-235ed3f7-b7c4-4757-9a58-181c5b0e311f.png`
- SHA-256：`28929226A7B755F3FC5BBB47488666DD00FBE69889111A5BB8BD1AAD5CA74186`
- 原创设计：废弃采掘机械被冷青荧光真菌寄生，六只短节肢、矿镐状前肢、开裂铜铁甲壳、橙色眼缝；轮廓与拾荒者明显不同。
- 透明检查：32-bit ARGB；851,448 个 alpha=0 像素；左上角 alpha=0；有效主体边界（alpha>10）为 x=50..1204, y=34..1183。
- 视觉检查：已用 `view_image` 打开工程 PNG；六肢完整可辨、俯视朝向画面下方、无地面投影、无背景。64px 实机缩放效果由主工程渲染验证。

### 最终生成提示词

```text
Use case: stylized-concept. Asset type: final production transparent PNG sprite for an original native 2D top-down action game, Abyss Salvager. Style: high-quality hand-painted 2D game sprite, bold economical brushwork, crisp easily readable silhouette at 64 pixels, simplified material detailing, restrained rim light, neither photorealistic nor extremely chibi. Orthographic camera looking downward at about 65 degrees from horizontal; subject faces toward the bottom of the image and top of head/shoulders visible. Square 1024 by 1024 canvas, one complete subject centered, subject fills about 80 percent with all appendages contained. Actual fully transparent alpha background, no background colors, no floor, no cast ground shadow, no scenery, no text, no watermark, no logo, no UI border. Palette: deep charcoal blue #17232C industrial surfaces, worn copper #B7884B, amber #E6AA4A light and small cool cyan #67C7D5 accents. Fully original character design, no references to existing intellectual property. Subject: a fully original dangerous but non-gory 'Rustshell Parasite', a low crouching mechanical carapace predator formed from abandoned mine excavation machinery colonized by luminous fungus. Six clearly countable short segmented legs with the front pair ending in compact mining-pick claws. Broad rounded diamond body silhouette, very different from a humanoid. Central broken shell of copper and dark iron plates, a single narrow dark amber-orange eye slit near the front lower edge. A few restrained small cyan luminous fungal sacs protrude from cracks on the back. Faces image bottom, elevated top-down view exposes the shell top and six leg attachments. No humanoid body, no held weapons, no gun, no skull or gore. Chunky bold silhouette, expressive threatening posture, all six legs fully visible.
```

## 集成边界

- 图片是静态全身角色素材；移动、受击、攻击、死亡反馈由 Godot 脚本与原生绘制实现。
- 未添加额外角色、怪物种类或 M2–M4 内容。
- PNG 的原始 alpha 已保留；黑色预览底色不是 PNG 背景。
- 最终工程目录由主任务迁移到 `D:\dev\zgame\abyss-delver\godot`；工程内相对路径保持不变。

