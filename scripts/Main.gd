extends Control

const SAVE_PATH = "user://clicker_skill_tree_save.json"
const CLICK_FLOAT_TIME = 0.65
const VICTORY_ESSENCE_THRESHOLD = 10000.0

# ─── Reservoir dessiné via _draw ─────────────────────────────────────────────
class ReservoirControl:
	extends Control
	var fill_ratio = 0.0
	var overflow_active = false
	var overflow_pulse = 0.0

	func _draw():
		var w = size.x
		var h = size.y
		var border = 4.0
		var inner_x = border
		var inner_y = border
		var inner_w = w - border * 2
		var inner_h = h - border * 2

		# Fond vide (gris-bleuté)
		draw_rect(Rect2(inner_x, inner_y, inner_w, inner_h), Color(0.18, 0.20, 0.26))

		# Bloc essence qui monte du bas (sombre)
		var liquid_h = inner_h * clamp(fill_ratio, 0.0, 1.0)
		var liquid_y = inner_y + inner_h - liquid_h
		if liquid_h > 0:
			var col = Color(0.05, 0.08, 0.15)
			if overflow_active:
				col = Color(0.15 + overflow_pulse * 0.55, 0.02, 0.02)
			elif fill_ratio > 0.85:
				col = Color(0.18, 0.06, 0.04)
			elif fill_ratio > 0.5:
				col = Color(0.05, 0.10, 0.22)
			draw_rect(Rect2(inner_x, liquid_y, inner_w, liquid_h), col)

		# Ligne MAX (rouge)
		var max_line_y = inner_y + inner_h * 0.08
		draw_rect(Rect2(inner_x, max_line_y, inner_w, 3), Color(0.90, 0.20, 0.08, 0.85))

		# Bordure extérieure
		draw_rect(Rect2(0, 0, w, border), Color(0.45, 0.55, 0.75))          # haut
		draw_rect(Rect2(0, h - border, w, border), Color(0.45, 0.55, 0.75)) # bas
		draw_rect(Rect2(0, 0, border, h), Color(0.45, 0.55, 0.75))          # gauche
		draw_rect(Rect2(w - border, 0, border, h), Color(0.45, 0.55, 0.75)) # droite

# ─── Skill Tree Canvas ────────────────────────────────────────────────────────
class SkillTreeCanvas:
	extends Control
	var game

	func _draw():
		if game == null:
			return
		for skill_id in game.skills.keys():
			var skill = game.skills[skill_id]
			for req_id in skill.get("requires", []):
				if not game.skills.has(req_id):
					continue
				var from_pos = game.skills[req_id]["pos"] + Vector2(72, 38)
				var to_pos = skill["pos"] + Vector2(72, 38)
				var done = int(game.skill_levels.get(req_id, 0)) > 0
				var col = Color(0.25, 0.95, 0.55, 0.95) if done else Color(0.35, 0.38, 0.48, 0.85)
				draw_line(from_pos, to_pos, col, 5.0, true)

# ─── Variables de jeu ────────────────────────────────────────────────────────
var essence = 0.0
var total_essence_earned = 0.0
var total_clicks = 0
var click_power = 1.0
var passive_income = 0.0
var crit_chance = 0.0
var crit_multiplier = 2.0
var combo = 0
var combo_timer = 0.0
var combo_window = 0.62
var max_combo_bonus = 0.20
var global_multiplier = 1.0
var selected_skill_id = "click_1"
var autosave_timer = 0.0
var ui_refresh_timer = 0.0
var rng = RandomNumberGenerator.new()
var game_start_time = 0.0
var victory_shown = false
var overflow_anim_timer = 0.0
var overflow_active = false
var drone_anim_timer = 0.0

# ─── Références UI ───────────────────────────────────────────────────────────
var stats_label
var click_button
var combo_label
var status_label
var skill_info_label
var buy_button
var tree_canvas
var skill_buttons = {}
var skill_tree_panel
var skill_tree_visible = false
var reservoir_node       # ReservoirControl
var reservoir_label
var drone_icons = []
var drone_container
var hand_label           # Label "[ CLIC ]"
var overflow_drops = []
var victory_overlay

var skill_levels = {}

var skills = {
	"click_1": {
		"name": "Doigts solides",
		"desc": "+1 puissance de clic par niveau.",
		"cost": 15, "cost_growth": 1.72, "max_level": 5,
		"requires": [], "pos": Vector2(30, 70),
		"effects": {"click_power": 1.0}
	},
	"auto_1": {
		"name": "Mini drone",
		"desc": "+0.4 essence / seconde par niveau.",
		"cost": 55, "cost_growth": 1.85, "max_level": 5,
		"requires": ["click_1"], "pos": Vector2(250, 20),
		"effects": {"passive_income": 0.4}
	},
	"combo_1": {
		"name": "Combo nerveux",
		"desc": "+4% bonus combo maximum par niveau.",
		"cost": 70, "cost_growth": 1.80, "max_level": 4,
		"requires": ["click_1"], "pos": Vector2(250, 145),
		"effects": {"combo_bonus": 0.04}
	},
	"auto_2": {
		"name": "Ferme automatique",
		"desc": "+2 essence / seconde par niveau.",
		"cost": 220, "cost_growth": 1.88, "max_level": 5,
		"requires": ["auto_1"], "pos": Vector2(470, 20),
		"effects": {"passive_income": 2.0}
	},
	"crit_1": {
		"name": "Clic critique",
		"desc": "+5% chance de critique par niveau.",
		"cost": 180, "cost_growth": 1.75, "max_level": 5,
		"requires": ["combo_1"], "pos": Vector2(470, 145),
		"effects": {"crit_chance": 0.05}
	},
	"gold_click": {
		"name": "Clic royal",
		"desc": "+5 puissance de clic par niveau.",
		"cost": 650, "cost_growth": 2.10, "max_level": 3,
		"requires": ["auto_2", "crit_1"], "pos": Vector2(690, 70),
		"effects": {"click_power": 5.0}
	},
	"crit_2": {
		"name": "Frappe lourde",
		"desc": "+0.5 multiplicateur critique par niveau.",
		"cost": 900, "cost_growth": 2.0, "max_level": 4,
		"requires": ["crit_1"], "pos": Vector2(690, 205),
		"effects": {"crit_multiplier": 0.5}
	},
	"ascension": {
		"name": "Ascension",
		"desc": "+25% a tous les gains par niveau.",
		"cost": 2500, "cost_growth": 2, "max_level": 3,
		"requires": ["gold_click", "crit_2"], "pos": Vector2(910, 135),
		"effects": {"global_multiplier": 0.25}
	}
}

# ─── _ready ──────────────────────────────────────────────────────────────────
func _ready():
	rng.randomize()
	game_start_time = Time.get_unix_time_from_system()
	for skill_id in skills.keys():
		skill_levels[skill_id] = 0
	build_ui()
	load_game()
	recalculate_stats()
	update_ui()
	set_process(true)

# ─── UI principale ───────────────────────────────────────────────────────────
func build_ui():
	var background = ColorRect.new()
	background.color = Color(0.045, 0.055, 0.09)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	margin.add_child(columns)

	# ── Panneau gauche ──
	var left_panel = PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(390, 0)
	left_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.075, 0.095, 0.15), Color(0.16, 0.22, 0.34)))
	columns.add_child(left_panel)

	var lm = MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		lm.add_theme_constant_override(s, 18)
	left_panel.add_child(lm)

	var left_box = VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 12)
	lm.add_child(left_box)

	var title = Label.new()
	title.text = "Clicker Essence"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	left_box.add_child(title)

	stats_label = Label.new()
	stats_label.text = "Chargement..."
	stats_label.add_theme_font_size_override("font_size", 15)
	left_box.add_child(stats_label)

	combo_label = Label.new()
	combo_label.text = "Combo x0"
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.add_theme_font_size_override("font_size", 18)
	left_box.add_child(combo_label)

	click_button = Button.new()
	click_button.text = "CLIQUE ICI\n+ essence"
	click_button.custom_minimum_size = Vector2(0, 140)
	click_button.add_theme_font_size_override("font_size", 28)
	click_button.pressed.connect(_on_click_button_pressed)
	left_box.add_child(click_button)

	var help = Label.new()
	help.text = "Espace = clic  |  S = sauver  |  R = reset"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(0.72, 0.78, 0.90)
	help.add_theme_font_size_override("font_size", 13)
	left_box.add_child(help)

	var brow = HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	left_box.add_child(brow)

	var skill_tree_btn = Button.new()
	skill_tree_btn.text = "[ Competences ]"
	skill_tree_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_tree_btn.add_theme_font_size_override("font_size", 15)
	skill_tree_btn.pressed.connect(_toggle_skill_tree)
	brow.add_child(skill_tree_btn)

	var save_btn = Button.new()
	save_btn.text = "Sauver"
	save_btn.pressed.connect(func(): save_game(true))
	brow.add_child(save_btn)

	var reset_btn = Button.new()
	reset_btn.text = "Reset"
	reset_btn.pressed.connect(reset_game)
	brow.add_child(reset_btn)

	status_label = Label.new()
	status_label.text = "Achete des competences pour accelerer tes gains !"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.modulate = Color(0.80, 0.86, 0.95)
	status_label.add_theme_font_size_override("font_size", 13)
	left_box.add_child(status_label)

	# ── Panneau droit ──
	var right_panel = PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.065, 0.075, 0.12), Color(0.16, 0.22, 0.34)))
	columns.add_child(right_panel)

	var rm = MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		rm.add_theme_constant_override(s, 18)
	right_panel.add_child(rm)

	var right_box = VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 10)
	rm.add_child(right_box)

	var res_title = Label.new()
	res_title.text = "Reservoir d'essence"
	res_title.add_theme_font_size_override("font_size", 22)
	res_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_box.add_child(res_title)

	var drone_title = Label.new()
	drone_title.text = "Automatisations actives :"
	drone_title.modulate = Color(0.72, 0.78, 0.90)
	drone_title.add_theme_font_size_override("font_size", 13)
	right_box.add_child(drone_title)

	drone_container = FlowContainer.new()
	drone_container.add_theme_constant_override("h_separation", 8)
	drone_container.add_theme_constant_override("v_separation", 4)
	drone_container.custom_minimum_size = Vector2(0, 32)
	drone_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.add_child(drone_container)

	# Réservoir dessiné
	reservoir_node = ReservoirControl.new()
	reservoir_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reservoir_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reservoir_node.custom_minimum_size = Vector2(0, 200)
	right_box.add_child(reservoir_node)



	reservoir_label = Label.new()
	reservoir_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reservoir_label.add_theme_font_size_override("font_size", 15)
	reservoir_label.text = "0 / 10.00K essence (0%)"
	right_box.add_child(reservoir_label)

	build_skill_tree_overlay()
	build_victory_overlay()

# ─── Skill Tree Overlay ───────────────────────────────────────────────────────
func build_skill_tree_overlay():
	skill_tree_panel = PanelContainer.new()
	skill_tree_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	skill_tree_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.04, 0.05, 0.09, 0.97), Color(0.25, 0.35, 0.55)))
	skill_tree_panel.visible = false
	add_child(skill_tree_panel)

	var om = MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		om.add_theme_constant_override(s, 24)
	skill_tree_panel.add_child(om)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	om.add_child(vbox)

	var hdr = HBoxContainer.new()
	vbox.add_child(hdr)

	var ttitle = Label.new()
	ttitle.text = "Arbre de competences"
	ttitle.add_theme_font_size_override("font_size", 26)
	ttitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(ttitle)

	var close_btn = Button.new()
	close_btn.text = "X Fermer"
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.pressed.connect(_toggle_skill_tree)
	hdr.add_child(close_btn)

	var hint = Label.new()
	hint.text = "Clique sur une competence, puis achete-la si tu as assez d'essence et les prerequis."
	hint.modulate = Color(0.72, 0.78, 0.90)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	tree_canvas = SkillTreeCanvas.new()
	tree_canvas.game = self
	tree_canvas.custom_minimum_size = Vector2(1100, 320)
	scroll.add_child(tree_canvas)

	for skill_id in skills.keys():
		var sb = Button.new()
		sb.custom_minimum_size = Vector2(145, 76)
		sb.position = skills[skill_id]["pos"]
		sb.pressed.connect(_on_skill_selected.bind(skill_id))
		tree_canvas.add_child(sb)
		skill_buttons[skill_id] = sb

	var info_panel = PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.08, 0.10, 0.16), Color(0.20, 0.30, 0.48)))
	vbox.add_child(info_panel)

	var im = MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		im.add_theme_constant_override(s, 12)
	info_panel.add_child(im)

	var ibox = HBoxContainer.new()
	ibox.add_theme_constant_override("separation", 14)
	im.add_child(ibox)

	skill_info_label = Label.new()
	skill_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_info_label.text = "Selectionne une competence."
	ibox.add_child(skill_info_label)

	buy_button = Button.new()
	buy_button.text = "Acheter"
	buy_button.custom_minimum_size = Vector2(140, 50)
	buy_button.pressed.connect(_on_buy_skill_pressed)
	ibox.add_child(buy_button)

# ─── Overlay Victoire ─────────────────────────────────────────────────────────
func build_victory_overlay():
	victory_overlay = PanelContainer.new()
	victory_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	victory_overlay.add_theme_stylebox_override("panel", make_panel_style(Color(0.02, 0.06, 0.04, 0.96), Color(0.20, 0.85, 0.45)))
	victory_overlay.visible = false
	add_child(victory_overlay)

	var vm = MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		vm.add_theme_constant_override(s, 60)
	victory_overlay.add_child(vm)

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vm.add_child(vb)

	var trophy = Label.new()
	trophy.text = "VICTOIRE !"
	trophy.add_theme_font_size_override("font_size", 70)
	trophy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trophy.modulate = Color(0.95, 0.85, 0.2)
	vb.add_child(trophy)

	var sub = Label.new()
	sub.text = "Le reservoir deborde !"
	sub.add_theme_font_size_override("font_size", 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.3, 1.0, 0.55)
	vb.add_child(sub)

	var win_stats = Label.new()
	win_stats.name = "WinStats"
	win_stats.text = ""
	win_stats.add_theme_font_size_override("font_size", 20)
	win_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_stats.modulate = Color(0.9, 0.95, 0.85)
	vb.add_child(win_stats)

	var replay_btn = Button.new()
	replay_btn.text = "Rejouer"
	replay_btn.add_theme_font_size_override("font_size", 20)
	replay_btn.custom_minimum_size = Vector2(180, 55)
	replay_btn.pressed.connect(reset_game)
	vb.add_child(replay_btn)

# ─── Toggle menu ─────────────────────────────────────────────────────────────
func _toggle_skill_tree():
	skill_tree_visible = !skill_tree_visible
	skill_tree_panel.visible = skill_tree_visible
	if skill_tree_visible:
		update_skill_buttons()

# ─── _process ─────────────────────────────────────────────────────────────────
func _process(delta):
	if passive_income > 0.0 and not victory_shown:
		essence += passive_income * global_multiplier * delta
		total_essence_earned += passive_income * global_multiplier * delta

	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0

	drone_anim_timer += delta

	# Anim débordement
	if overflow_active:
		overflow_anim_timer += delta
		reservoir_node.overflow_pulse = (sin(overflow_anim_timer * 8.0) + 1.0) / 2.0
		reservoir_node.queue_redraw()
		if int(overflow_anim_timer * 6) % 2 == 0 and overflow_drops.size() < 12:
			spawn_overflow_drop()

	# Check victoire
	if not victory_shown and essence >= VICTORY_ESSENCE_THRESHOLD and are_all_skills_maxed():
		trigger_victory()

	ui_refresh_timer += delta
	if ui_refresh_timer >= 0.08:
		ui_refresh_timer = 0.0
		update_ui()

	autosave_timer += delta
	if autosave_timer >= 8.0:
		autosave_timer = 0.0
		save_game(false)

func are_all_skills_maxed():
	for skill_id in skills.keys():
		if int(skill_levels.get(skill_id, 0)) < int(skills[skill_id]["max_level"]):
			return false
	return true

func spawn_overflow_drop():
	var drop = ColorRect.new()
	drop.custom_minimum_size = Vector2(10, 16)
	var cols = [Color(0.1, 0.2, 0.85), Color(0.85, 0.25, 0.05), Color(0.75, 0.70, 0.1)]
	drop.color = cols[rng.randi() % 3]
	drop.position = Vector2(rng.randf_range(300, 800), 80)
	add_child(drop)
	overflow_drops.append(drop)
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(drop, "position", drop.position + Vector2(rng.randf_range(-60, 60), 280), 1.1)
	tw.tween_property(drop, "modulate:a", 0.0, 1.1)
	tw.finished.connect(func():
		if is_instance_valid(drop):
			overflow_drops.erase(drop)
			drop.queue_free()
	)

func trigger_victory():
	victory_shown = true
	overflow_active = true
	reservoir_node.overflow_active = true
	skill_tree_panel.visible = false

	var elapsed = Time.get_unix_time_from_system() - game_start_time
	var minutes = int(elapsed) / 60
	var seconds = int(elapsed) % 60

	var win_stats = victory_overlay.find_child("WinStats") as Label
	if win_stats:
		win_stats.text = "Temps : %d min %02d sec\nEssence totale gagnee : %s\nClics : %d" % [
			minutes, seconds, format_number(total_essence_earned), total_clicks
		]

	await get_tree().create_timer(1.5).timeout
	victory_overlay.visible = true

# ─── Input ───────────────────────────────────────────────────────────────────
func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_on_click_button_pressed()
		elif event.keycode == KEY_S:
			save_game(true)
		elif event.keycode == KEY_R:
			reset_game()
		elif event.keycode == KEY_ESCAPE and skill_tree_visible:
			_toggle_skill_tree()

# ─── Clic ────────────────────────────────────────────────────────────────────
func _on_click_button_pressed():
	if victory_shown:
		return
	combo = combo + 1 if combo_timer > 0.0 else 1
	combo_timer = combo_window

	var combo_bonus = min(max_combo_bonus, float(combo) * 0.01)
	var gain = click_power * global_multiplier * (1.0 + combo_bonus)
	var is_crit = rng.randf() < crit_chance
	if is_crit:
		gain *= crit_multiplier

	essence += gain
	total_essence_earned += gain
	total_clicks += 1
	spawn_floating_text("+%s%s" % [format_number(gain), " CRIT!" if is_crit else ""])


	update_ui()

func spawn_floating_text(txt):
	var fl = Label.new()
	fl.text = txt
	fl.add_theme_font_size_override("font_size", 22)
	fl.modulate = Color(0.95, 0.85, 0.30) if txt.contains("CRIT") else Color(0.65, 0.90, 1.0)
	add_child(fl)

	var cr = click_button.get_global_rect()
	fl.global_position = cr.position + Vector2(rng.randf_range(30.0, cr.size.x - 80.0), rng.randf_range(20.0, cr.size.y - 30.0))

	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(fl, "global_position", fl.global_position + Vector2(0, -55), CLICK_FLOAT_TIME)
	tw.tween_property(fl, "modulate:a", 0.0, CLICK_FLOAT_TIME)
	tw.finished.connect(fl.queue_free)

# ─── Skill events ─────────────────────────────────────────────────────────────
func _on_skill_selected(skill_id):
	selected_skill_id = skill_id
	update_skill_info()
	update_skill_buttons()

func _on_buy_skill_pressed():
	if selected_skill_id == "":
		return
	if not can_buy_skill(selected_skill_id):
		status_label.text = "Pas encore possible : verifie le cout ou les prerequis."
		return
	var cost = get_skill_cost(selected_skill_id)
	essence -= cost
	skill_levels[selected_skill_id] = int(skill_levels[selected_skill_id]) + 1
	recalculate_stats()
	status_label.text = "Competence achetee : %s !" % skills[selected_skill_id]["name"]
	update_ui()
	update_drones()
	save_game(false)

# ─── Stats ───────────────────────────────────────────────────────────────────
func recalculate_stats():
	click_power = 1.0
	passive_income = 0.0
	crit_chance = 0.0
	crit_multiplier = 2.0
	max_combo_bonus = 0.20
	global_multiplier = 1.0

	for skill_id in skills.keys():
		var level = int(skill_levels.get(skill_id, 0))
		if level <= 0:
			continue
		var effects = skills[skill_id].get("effects", {})
		for effect_name in effects.keys():
			var value = float(effects[effect_name]) * float(level)
			if effect_name == "click_power":
				click_power += value
			elif effect_name == "passive_income":
				passive_income += value
			elif effect_name == "crit_chance":
				crit_chance += value
			elif effect_name == "crit_multiplier":
				crit_multiplier += value
			elif effect_name == "combo_bonus":
				max_combo_bonus += value
			elif effect_name == "global_multiplier":
				global_multiplier += value

	crit_chance = clamp(crit_chance, 0.0, 0.95)

# ─── Update UI ───────────────────────────────────────────────────────────────
func update_ui():
	stats_label.text = "Essence : %s\nPuissance clic : %s\nPassif : %s / sec\nCritique : %d%% x%s\nClics totaux : %d" % [
		format_number(essence),
		format_number(click_power * global_multiplier),
		format_number(passive_income * global_multiplier),
		int(round(crit_chance * 100.0)),
		format_number(crit_multiplier),
		total_clicks
	]
	combo_label.text = "Combo x%d  |  bonus +%d%%" % [combo, int(round(min(max_combo_bonus, float(combo) * 0.01) * 100.0))]
	click_button.text = "CLIQUE ICI\n+%s essence" % format_number(click_power * global_multiplier)

	update_reservoir()
	update_drones()

	if skill_tree_visible:
		update_skill_info()
		update_skill_buttons()
		if tree_canvas != null:
			tree_canvas.queue_redraw()

func update_reservoir():
	if not is_instance_valid(reservoir_node):
		return
	var fill_ratio = clamp(essence / VICTORY_ESSENCE_THRESHOLD, 0.0, 1.0)
	if not overflow_active:
		reservoir_node.fill_ratio = fill_ratio
		reservoir_node.queue_redraw()
	if is_instance_valid(reservoir_label):
		reservoir_label.text = "%s / %s essence  (%d%%)" % [
			format_number(essence),
			format_number(VICTORY_ESSENCE_THRESHOLD),
			int(fill_ratio * 100)
		]

func make_drone_badge(txt, col, tip):
	var badge = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = col
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = col.lightened(0.3)
	badge.add_theme_stylebox_override("panel", style)
	var lbl = Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", 12)
	badge.add_child(lbl)
	badge.tooltip_text = tip
	return badge

func update_drones():
	for child in drone_container.get_children():
		child.queue_free()
	drone_icons.clear()

	var drone_count = int(skill_levels.get("auto_1", 0))
	if drone_count > 0:
		var total_ps = drone_count * 0.4 * global_multiplier
		var d = make_drone_badge("Drones x%d  (+%.1f/s)" % [drone_count, total_ps], Color(0.15, 0.35, 0.60), "Mini drones : %d x +0.4/s" % drone_count)
		drone_container.add_child(d)
		drone_icons.append(d)

	var farm_count = int(skill_levels.get("auto_2", 0))
	if farm_count > 0:
		var total_ps = farm_count * 2.0 * global_multiplier
		var d = make_drone_badge("Fermes x%d  (+%.1f/s)" % [farm_count, total_ps], Color(0.18, 0.42, 0.22), "Fermes auto : %d x +2/s" % farm_count)
		drone_container.add_child(d)
		drone_icons.append(d)

	if int(skill_levels.get("ascension", 0)) > 0:
		var lvl = int(skill_levels.get("ascension", 0))
		var d = make_drone_badge("Ascension x%d  (+%d%% global)" % [lvl, lvl * 25], Color(0.48, 0.28, 0.08), "Ascension niveau %d" % lvl)
		drone_container.add_child(d)
		drone_icons.append(d)

	if int(skill_levels.get("crit_1", 0)) > 0:
		var pct = int(crit_chance * 100)
		var mult = snappedf(crit_multiplier, 0.1)
		var d = make_drone_badge("Critique %d%%  (x%.1f)" % [pct, mult], Color(0.48, 0.12, 0.12), "Critiques actifs")
		drone_container.add_child(d)
		drone_icons.append(d)

	if int(skill_levels.get("combo_1", 0)) > 0:
		var lvl = int(skill_levels.get("combo_1", 0))
		var d = make_drone_badge("Combo max +%d%%" % int(max_combo_bonus * 100), Color(0.30, 0.18, 0.48), "Combo nerveux niveau %d" % lvl)
		drone_container.add_child(d)
		drone_icons.append(d)

	if drone_icons.is_empty():
		var empty = Label.new()
		empty.text = "Aucune — achete des competences !"
		empty.modulate = Color(0.55, 0.58, 0.65)
		drone_container.add_child(empty)

func update_skill_info():
	if selected_skill_id == "" or not skills.has(selected_skill_id):
		skill_info_label.text = "Selectionne une competence."
		buy_button.disabled = true
		return

	var skill = skills[selected_skill_id]
	var level = int(skill_levels.get(selected_skill_id, 0))
	var max_level = int(skill["max_level"])
	var req_text = get_requirement_text(selected_skill_id)
	var cost_text = "MAX" if level >= max_level else format_number(get_skill_cost(selected_skill_id))

	skill_info_label.text = "%s\n%s\nNiveau : %d/%d  |  Cout : %s\nPrerequis : %s" % [
		skill["name"], skill["desc"], level, max_level, cost_text, req_text
	]
	buy_button.disabled = not can_buy_skill(selected_skill_id)
	buy_button.text = "Acheter" if level < max_level else "Max"

func update_skill_buttons():
	for skill_id in skill_buttons.keys():
		var button = skill_buttons[skill_id]
		var skill = skills[skill_id]
		var level = int(skill_levels.get(skill_id, 0))
		var max_level = int(skill["max_level"])
		var prefix = "* " if skill_id == selected_skill_id else ""
		button.text = "%s%s\nLv %d/%d" % [prefix, skill["name"], level, max_level]
		button.tooltip_text = skill["desc"]

		if level >= max_level:
			button.modulate = Color(0.70, 1.0, 0.70)
		elif not are_requirements_met(skill_id):
			button.modulate = Color(0.50, 0.52, 0.58)
		elif essence >= get_skill_cost(skill_id):
			button.modulate = Color(0.70, 0.88, 1.0)
		else:
			button.modulate = Color(1.0, 1.0, 1.0)

# ─── Skill helpers ────────────────────────────────────────────────────────────
func get_skill_cost(skill_id):
	if not skills.has(skill_id):
		return 999999999
	var skill = skills[skill_id]
	var level = int(skill_levels.get(skill_id, 0))
	if level >= int(skill["max_level"]):
		return 999999999
	return int(round(float(skill["cost"]) * pow(float(skill["cost_growth"]), float(level))))

func can_buy_skill(skill_id):
	if not skills.has(skill_id):
		return false
	if int(skill_levels.get(skill_id, 0)) >= int(skills[skill_id]["max_level"]):
		return false
	if not are_requirements_met(skill_id):
		return false
	return essence >= float(get_skill_cost(skill_id))

func are_requirements_met(skill_id):
	if not skills.has(skill_id):
		return false
	for req_id in skills[skill_id].get("requires", []):
		if int(skill_levels.get(req_id, 0)) <= 0:
			return false
	return true

func get_requirement_text(skill_id):
	var reqs = skills[skill_id].get("requires", [])
	if reqs.is_empty():
		return "Aucun"
	var names = []
	for req_id in reqs:
		names.append(skills[req_id]["name"])
	return ", ".join(names)

# ─── Save / Load / Reset ─────────────────────────────────────────────────────
func save_game(show_msg):
	var data = {
		"essence": essence,
		"total_clicks": total_clicks,
		"total_essence_earned": total_essence_earned,
		"game_start_time": game_start_time,
		"skill_levels": skill_levels
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		status_label.text = "Impossible de sauvegarder."
		return
	file.store_string(JSON.stringify(data, "\t"))
	if show_msg:
		status_label.text = "Sauvegarde OK."

func load_game(show_msg = false):
	if not FileAccess.file_exists(SAVE_PATH):
		if show_msg:
			status_label.text = "Aucune sauvegarde trouvee."
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		status_label.text = "Impossible de charger."
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		status_label.text = "Sauvegarde invalide."
		return
	essence = float(parsed.get("essence", 0.0))
	total_clicks = int(parsed.get("total_clicks", 0))
	total_essence_earned = float(parsed.get("total_essence_earned", essence))
	game_start_time = float(parsed.get("game_start_time", Time.get_unix_time_from_system()))
	var loaded = parsed.get("skill_levels", {})
	for skill_id in skills.keys():
		skill_levels[skill_id] = int(loaded.get(skill_id, 0))
	recalculate_stats()
	update_drones()
	if show_msg:
		status_label.text = "Sauvegarde chargee."
	update_ui()

func reset_game():
	essence = 0.0
	total_clicks = 0
	total_essence_earned = 0.0
	combo = 0
	combo_timer = 0.0
	victory_shown = false
	overflow_active = false
	overflow_anim_timer = 0.0
	game_start_time = Time.get_unix_time_from_system()
	victory_overlay.visible = false
	skill_tree_panel.visible = false
	skill_tree_visible = false
	reservoir_node.overflow_active = false
	reservoir_node.fill_ratio = 0.0
	reservoir_node.queue_redraw()
	for drop in overflow_drops:
		if is_instance_valid(drop):
			drop.queue_free()
	overflow_drops.clear()
	for skill_id in skills.keys():
		skill_levels[skill_id] = 0
	recalculate_stats()
	update_drones()
	status_label.text = "Partie remise a zero."
	save_game(false)
	update_ui()

# ─── Helpers ─────────────────────────────────────────────────────────────────
func make_panel_style(bg, border):
	var style = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	return style

func format_number(value):
	if value >= 1000000000.0:
		return "%.2fB" % (value / 1000000000.0)
	if value >= 1000000.0:
		return "%.2fM" % (value / 1000000.0)
	if value >= 1000.0:
		return "%.2fK" % (value / 1000.0)
	if abs(value - round(value)) < 0.01:
		return str(int(round(value)))
	return "%.1f" % value
