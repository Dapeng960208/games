# 深渊拾荒者：原创配乐

四首音乐均由本项目原创旋律、和声、节奏与标准库合成器生成，无外部录音或采样。音乐资源及生成器输出采用 CC0-1.0，可随游戏分发。源配器与每个音符见 `tools/compose_audio.py` 和 `score.json`。

| 场景 | 曲名 | 速度 | 配器与变化 |
| --- | --- | --- | --- |
| 营地 | 余烬工坊 / Ember Workshop | 82 BPM | 毛毡键、木质敲击、悬浮和弦；缓慢留白 |
| 探索 | 潮下回声 / Below the Tide | 96 BPM | 闷弦、玻璃应答、半拍脉冲；较稀疏 |
| 战斗 | 钢与回响 / Steel and Echo | 124 BPM | 切分贝斯、鼓组、玻璃旋律、和弦短奏 |
| 首领 | 深渊引擎 / Abyss Engine | 136 BPM | 低音固定音型、铜管短奏、更密集的鼓与旋律呼应 |

每曲为 16 小节、4/4 拍，以 D Dorian 调式和 D–A–G–E 主题联系，具有 A / A 变奏 / B / A 解决式结构。不是循环单音提示。所有 WAV 为 24kHz、16bit、双声道；每首约 28–47 秒。循环尾音通过环形混音保留，首尾每个声道的 PCM 样本完全一致。`score.json` 包含实际峰值、RMS、DC、最大相邻样本差、每秒能量、完整音符事件以及 PCM SHA-256。

四份 `.wav.import` 显式设置 `compress/mode=0`，保留无损 16bit PCM；不要使用 Godot 默认有损压缩覆盖该设置。验收测试比较导入资源和原始 WAV 的完整 PCM 字节，验证编译/导入后仍满足相同峰值和循环边界。循环结束位置按解码后的实际帧数计算，不依赖压缩字节数量。

## 重建与检验

```powershell
python tools/compose_audio.py
python tools/compose_audio.py --verify-only
./tools/test.ps1 -Suite combat_audio,audio_identity -SkipImport -SkipRestart
```

只需要 Python 标准库，固定种子可重建。音乐测试读取真实 WAV；音效试听由 Godot 的生产合成器导出。未声明真人听感验收。

命中、部署声音、释放时序及播放调度已做定向检查，结果集中记录在本地验收文档。三职业重击已采用各自的频段与包络，移除此前共用的低频尾音；直接轻命中与重击仍可使用保留声部，总声部上限不变。信号与调度检查不代表真人听感或职业平衡验收。

`assets/audio/previews/music_showcase.wav` 按营地、探索、战斗、首领顺序各截取12秒；较早的`sfx_showcase.wav`为逐项隔离音色预览，不代表最新技能时序或重击设计。更新后的GPU录音为[CH01](../../artifacts/skill_feedback_CH01_native_mix.wav)、[CH02](../../artifacts/skill_feedback_CH02_native_mix.wav)、[CH03](../../artifacts/skill_feedback_CH03_native_mix.wav)：每份13.9947秒、48kHz、16bit立体声，按正常时钟直接录制含生产音乐与音效的Master输出，无增益处理。录制仍用Lv8训练、关闭AI、10000HP靶、资源补满并重置CH02第二次R冷却以验证取消；CH02未使用F陷阱，陷阱声音由专项验证。录音不作为正常平衡或真人听感结论，预览、录音与截图均仅留本地，不属于核心运行资源。

## 运行接口与混音

常驻 `MusicDirector` 只分配两个 `AudioStreamPlayer`。调用 `configure(game)` 后，`set_context("camp" | "explore" | "combat" | "boss")` 以 1.25 秒互补幅度淡入淡出；相同请求幂等，快速请求只保留最新目标。暂停将同一条音乐平滑降至 22%，恢复后继续相位，不重新播放或叠加。

`set_mix(master, music, sfx)` 接受 0–1 的值；调用者同时保存 `profile.settings.master_volume/music_volume/sfx_volume`。MusicDirector 响应 Game.changed；CombatAudio 在每帧读取相同设置。默认主音量 1、音乐 0.55、音效 0.85，支持 muted、music_muted、sfx_muted。

音乐峰值上限0.58、播放器增益0.18；音效峰值上限0.74、八声部各增益0.14。因此即使全部同相峰值且所有音量拉满，合计幅度仍小于0.95。音效保留两个玩家声部给攻击、施法、受伤及直接轻/重命中；被动命中、部署物声音、死亡和拾取共用最多六声部，总上限仍为八。枪击间隔至少75ms；每类声音轮换四个实际PCM波形变体，播放`pitch_scale`固定为1，不靠变调模拟变化。节点或轻击不会吞掉55ms内到来的重击，重击后的群体命中仍聚合，不抢占正在播放的音轨来截断波形。

技能音效由准备音及每次实际释放音组成，取消后的未来释放不再发声；12个技能各四种准备音，共48个PCM样本。真实部署事件`trap_trigger`、`node_fire`、`field_pulse`各新增四个变体，共12个样本；各自按100ms独立节流，低优先级播放且不压低背景音乐。领域追帧在一次`advance`中最多发一声，伤害结算不变。死亡音效有三种材质、各四个变体、每个0.30秒，按100ms节流。连同职业声音、受伤和拾取，总缓存为212个样本。普通、精英和召唤怪视觉退场持续0.44秒；降低特效时为0.18秒静态淡出，最多20个且不带碰撞，不包含首领和静态对象。

只有已获音轨、实际接受播放的直接命中`impact`／`heavy`会触发音乐让位，被动命中、挥空、被节流或无空闲音轨的请求不触发。轻击增益目标0.708（约−3dB），重击0.596（约−4.5dB）；进入目标的时长为8ms，按画面更新推进，并非采样级包络。轻击保持55ms、恢复160ms；重击保持75ms、恢复180ms。轻重两条包络取较低值，群怪命中不会相乘叠加降音；持续轻击也不会延长重击的深度。暂停或回营地清除临时包络，音乐/主音量设置和原配乐文件不变。
