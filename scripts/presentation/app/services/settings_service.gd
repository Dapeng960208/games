extends RefCounted
## Settings behavior owned by this host.
## The host retains state and lifecycle; this service never owns its Node.
var host

func _init(context: Node) -> void:
	host = context

func show_settings() -> void:
	var panel = host._push_modal("SETTINGS",Vector2(1080,644))
	panel.name = "SettingsPanel"
	host.audio_sliders.clear()
	var settings: Dictionary = Game.profile.get("settings",{})
	var general = GameStyle.button(panel,"",Vector2(28,82),Vector2(402,44),func(): host._switch_settings_tab("general"))
	general.text = host._ex_text("战斗与显示","COMBAT & DISPLAY")
	var controls = GameStyle.button(panel,"",Vector2(450,82),Vector2(402,44),func(): host._switch_settings_tab("controls"))
	controls.name = "ControlBindingsTab"
	controls.text = host._ex_text("操作与按键","CONTROLS & KEYS")
	GameStyle.selected(general if host.settings_tab == "general" else controls)
	if host.settings_tab == "controls":
		host._build_control_settings(panel)
		host._layout_settings_atlas(panel,general,controls)
		return
	for index in range(3):
		var key: String = ["master_volume","music_volume","sfx_volume"][index]
		var title: String = [host._ex_text("总音量","Master"),host._ex_text("音乐","Music"),host._ex_text("战斗音效","Combat SFX")][index]
		GameStyle.literal(panel,title,Vector2(28,151+index*54),Vector2(169,34),18)
		var slider = HSlider.new()
		slider.name = key
		slider.position = Vector2(208,153+index*54)
		slider.size = Vector2(544,32)
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = float(settings.get(key,[1.0,0.55,0.85][index]))
		panel.add_child(slider)
		host.audio_sliders[key] = slider
		var number = GameStyle.literal(panel,str(roundi(slider.value*100))+"%",Vector2(772,151+index*54),Vector2(80,34),18,GameStyle.CYAN)
		var debounce = Timer.new()
		debounce.wait_time = 0.18
		debounce.one_shot = true
		panel.add_child(debounce)
		debounce.timeout.connect(func(): Game.set_setting(key,slider.value))
		slider.value_changed.connect(func(value: float):
			number.text = str(roundi(value*100))+"%"
			if is_instance_valid(host.music): host.music.set_mix(host.audio_sliders.master_volume.value,host.audio_sliders.music_volume.value,host.audio_sliders.sfx_volume.value)
			debounce.start())
	var language = GameStyle.button(panel,"",Vector2(28,328),Vector2(264,48),host._toggle_language)
	language.text = host._ex_text("语言：简体中文","Language: English")
	language.tooltip_text = host._ex_text("点击切换为 English","Switch to 简体中文")
	language.grab_focus()
	var display = GameStyle.button(panel,"",Vector2(308,328),Vector2(264,48),host._toggle_fullscreen)
	display.text = host._ex_text("显示：全屏","Display: Fullscreen") if settings.get("fullscreen",false) else host._ex_text("显示：窗口","Display: Windowed")
	var effects = GameStyle.button(panel,"",Vector2(588,328),Vector2(264,48),host._toggle_fx)
	effects.text = host._ex_text("特效：简化","Effects: Reduced") if settings.get("reduced_fx",false) else host._ex_text("特效：完整","Effects: Full")
	var shake = GameStyle.button(panel,"",Vector2(28,392),Vector2(264,48),host._toggle_camera_shake)
	shake.name = "CameraShakeSetting"
	shake.text = host._ex_text("镜头震动：开启","Camera shake: On") if bool(settings.get("camera_shake",false)) else host._ex_text("镜头震动：关闭","Camera shake: Off")
	var automatic = GameStyle.button(panel,"",Vector2(308,392),Vector2(264,48),func(): host._toggle_combat_setting("auto_attack"))
	automatic.name = "AutoAttackSetting"
	automatic.text = host._ex_text("自动普攻：开启","Auto attack: On") if bool(settings.get("auto_attack",false)) else host._ex_text("自动普攻：关闭","Auto attack: Off")
	automatic.tooltip_text = host._ex_text("自动攻击攻击范围内的敌人；移动与技能仍由你控制。","Automatically attack nearby enemies in reach. You control movement and skills.")
	var paths = GameStyle.button(panel,"",Vector2(588,392),Vector2(264,48),func(): host._toggle_combat_setting("enemy_skill_paths"))
	paths.name = "EnemySkillPathsSetting"
	paths.text = host._ex_text("敌技能路径：显示","Enemy paths: On") if bool(settings.get("enemy_skill_paths",true)) else host._ex_text("敌技能路径：隐藏","Enemy paths: Off")
	paths.tooltip_text = host._ex_text("隐藏野怪技能预警线与范围标记；技能伤害与判定不变。","Hide enemy warning lines and area markers. Damage and hit detection remain active.")
	GameStyle.literal(panel,host._current_control_summary()+"\n"+host._ex_text("「操作与按键」可自定义；Esc 始终返回。关闭震动、自动普攻可减轻连续操作。", "Customize in Controls & Keys; Esc always returns. Disable shake or enable auto attacks for comfort."),Vector2(28,464),Vector2(824,84),16,GameStyle.MUTED)
	GameStyle.button(panel,"BACK",Vector2(612,566),Vector2(240,48),host._pop_modal)
	host._layout_settings_atlas(panel,general,controls)
