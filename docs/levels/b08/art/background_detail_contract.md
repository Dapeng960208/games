# B08 背景与详情资源接入合同

状态：**L43 独立母图候选已登记并完成定向几何检查；独立背景终验 0/7，原生详情层终验 0/7。** 最新接入见 [L43 配准候选](l43_registered_painting.md)。 不能把独立原画理解为只需要一张整图，也不能把当前 L43 分层道具包当作前四关的高清详情层。

## 实际参照 B02/L07

已读取 `assets/levels/b02/rooms/l07` 全目录、元数据、资源索引及消费代码，并查看整张背景、`top_left.webp`、`bottom_middle.webp` 的实际像素。

- `background/environment.png` 是 1536×1024 独立房间原画；`environment.json` 保存身份、原图尺寸、placement 和干地边界；`environment.prompt.json` 保存来源。
- `detail/manifest.json` 对应六张 `top_left/top_middle/top_right/bottom_left/bottom_middle/bottom_right.webp`。它们是同一原画对应区域的原生高清重绘，不是道具贴片，也不是简单放大后裁成六张。
- 六个源区域为 `[0,0,520,528]`、`[504,0,528,528]`、`[1016,0,520,528]`、`[0,504,520,520]`、`[504,504,528,520]`、`[1016,504,520,520]`；有 16/24 源像素的窄羽化重叠。原生输出约 1244–1265 像素，清单保留实际尺寸、原 PNG 哈希、无损 WebP/解码 RGB 哈希与提示词。
- `assets/manifest.json` 中 `world/rooms/l07_environment_v1.*` 指向 background，`world/rooms_2k/l07/*` 指向 detail。消费链为 `WorldArt.environment_definition` → `EnvironmentBackdrop` → `EnvironmentChunks` → `environment_detail.gd`。
- 详情层目的位置 = 完整原画世界矩形位置 + `source_rect.position/source_size × 原画世界尺寸`；缩放同理。背景、六个显示分区和详情重绘共用同一目的矩形，再由相同房间映射提供边界、锚点和镜头。
- 只有 `approved=true` 或明确候选许可才加载详情，且缺少任一张六区域纹理会清理整组。原画仍作为羽化缝与缺少详情时的真实回退。这里不是流式加载。

## B08 逐房登记

七房的目标物理目录、逻辑 ID 和实际缺失状态见 [逐房资源层清单](../rooms/resource_layers.json)。每房按 `background/{environment.png,environment.json,environment.prompt.json}` 和 `detail/{manifest.json,六张区域重绘}` 组织。源图尚未通过时只登记当前设计清单，不创建假资源或把未知路径写入正式资产索引。

现有 L43 `detail` 中的岩基/桥腹/塔殿/铺石是旧分层拼装候选，仍由自己的显式闸门使用；不更名冒充六区域详情，不删原字节。待独立背景与边界合同通过，新的六区域详情采用对应母图的 `source_rect` 注册，旧模块继续清楚标注用途，再按实际引用整理物理目录。

先让本房原画轮廓与运行边界达成明确合同，再重绘详情；否则高清层只会固定错位。详情不得改变路线、边界、阴影方向、地表关键结构或加入障碍物。动态演员、旗/风标/出口、风纹与预警继续由运行时按真实脚点单独绘制。

## 当前 L43 源图状态

以下是原先三张固定几何配准失败的源图记录，均完整保留。之后用户单独批准保留避风路线的外边界修订及中央孔精确蒙版编辑；选中的派生母图已在额外显式闸门下接入。不能将下列原始失败状态改写为原图已通过：

| 文件 | 原生尺寸 | SHA-256 |
|---|---|---|
| environment_candidate_01.png | 1536×1024 RGB | d920957e54930ee26b04f05adca8fb3113f641508a792de91c045766c9aa1c2c |
| environment_candidate_02.png | 1536×1024 RGB | bb5a59f25a968827fec48b99a4b5de79c0c927a086f1648d329b7cda1f6a0cb2 |
| environment_candidate_03.png | 1536×1024 RGB | fd36bc4dd59ff6755342002d48e0e1b3ed2baa3562b3732dabe2fae666cad6fa |

原图、完整 prompt、provenance、技术配准图与逐张 QA 保留在本次美术工作目录。第三版整体光照/风格更统一，但左右外扩、南缘上移、云缝偏移；在固定 mapping 下会误导通行。当前已停止继续生成，正在只读量算按第三版轮廓重标边界的影响；B08 尚未批准几何修改，B07 的单独许可不适用于这里。

`room_art_mapping.gd` 只是未接入的本地验证器：从现有 WorldArt 获取统一映射，核对六矩形并集与入口/出口/风标/旗。它不改碰撞。当前缺少通过的独立原画时明确拒绝，`b08_room_art_gate` 两项检查已通过（批次 `20261003T120508109380Z-5e3fba57`，退出 0）。不把验证器准备好当作资源或运行接入完成。
