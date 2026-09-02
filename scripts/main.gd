extends Node2D

# Core tuning. The simulation is deliberately grid based, like Pong Wars.
const COLS := 24
const ROWS := 26
const WAR_ROWS := 15
const CELL := 24.0
const FIELD_SIZE := Vector2(COLS * CELL, ROWS * CELL)
const FIELD_ORIGIN := Vector2(192.0, 12.0)
const BALL_RADIUS := CELL * 0.42
const ENEMY_START_SPEED := 178.0
const PLAYER_START_SPEED := 235.0
const SPEEDUP_TO_DOUBLE_SECONDS := 120.0
const PLAYER_MAX_SPEED_MULTIPLIER := 2.0
const WAR_SPEED_AT_120_SECONDS := 4.0
const WAR_MAX_SPEED_MULTIPLIER := 8.0
const WAR_BOUNCE_JITTER := deg_to_rad(4.0)
const PADDLE_SPEED := 645.0
const PADDLE_WIDTH := 104.0
const PADDLE_HEIGHT := 12.0
const DOOM_LIMIT := 24.0 * 60.0 * 60.0
const MISS_PENALTY := 38.0 * 60.0
const RESPAWN_DELAY := 0.5
const PADDLE_CONTACT_COOLDOWN := 0.08
const TITLE_INPUT_DELAY := 0.4
const GAME_OVER_INPUT_DELAY := 0.75
const FULLSCREEN_INPUT_COOLDOWN := 0.2
const FULLSCREEN_BUTTON_RECT := Rect2(876.0, 14.0, 48.0, 48.0)
const TOUCH_STICK_CENTER := Vector2(96.0, 594.0)
const TOUCH_STICK_ACTIVATION_RADIUS := 110.0
const TOUCH_STICK_AXIS_RANGE := 100.0
const MAX_BOUNCE_ANGLE := deg_to_rad(67.0)
const CLOCK_REFERENCE_TERRITORY_DIFFERENCE := 20.0
const CLOCK_RATE_AT_REFERENCE_DIFFERENCE := 60.0 * 60.0 / 5.0

const LEFT := 0
const RIGHT := 1
const PEACE := 2
const COLORS := [Color("#d9e8e3"), Color("#172b36"), Color("#d8ae78")]
const BALL_COLORS := [Color("#172b36"), Color("#f1f6f4"), Color("#fff7dc")]
const BG := Color("#0d2028")
const INK := Color("#f1f6f4")
const MUTED := Color("#8da4a5")
const DANGER := Color("#ff7a59")

var cells: Array[int] = []
var war_balls: Array[Dictionary] = []
var player_ball := {"position": Vector2.ZERO, "velocity": Vector2.ZERO, "team": PEACE}
var player_ball_active := false
var respawn_time_remaining := 0.0
var paddle_x := FIELD_SIZE.x * 0.5
var previous_paddle_x := FIELD_SIZE.x * 0.5
var paddle_velocity := 0.0
var paddle_contact_cooldown := 0.0
var doom_seconds := 0.0
var run_seconds := 0.0
var misses := 0
var game_over := false
var game_over_reason := ""
var game_over_input_delay := 0.0
var title_screen := true
var title_input_delay := TITLE_INPUT_DELAY
var touch_id := -1
var touch_axis := 0.0
var show_touch_controls := false
var fullscreen_input_cooldown := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	show_touch_controls = _is_mobile_device()
	reset_game()
	title_screen = true
	title_input_delay = TITLE_INPUT_DELAY
	set_process(true)


func reset_game() -> void:
	rng.randomize()
	cells.resize(COLS * ROWS)
	for y in ROWS:
		for x in COLS:
			cells[_index(x, y)] = PEACE if y >= WAR_ROWS else (LEFT if x < COLS / 2 else RIGHT)
	_apply_initial_protrusions()
	war_balls = [
		{"position": Vector2(FIELD_SIZE.x * 0.25, WAR_ROWS * CELL * 0.48), "velocity": _random_war_velocity(1.0), "team": LEFT},
		{"position": Vector2(FIELD_SIZE.x * 0.75, WAR_ROWS * CELL * 0.52), "velocity": _random_war_velocity(-1.0), "team": RIGHT},
	]
	paddle_x = FIELD_SIZE.x * 0.5
	previous_paddle_x = paddle_x
	paddle_contact_cooldown = 0.0
	doom_seconds = 0.0
	run_seconds = 0.0
	misses = 0
	respawn_time_remaining = 0.0
	game_over = false
	game_over_reason = ""
	game_over_input_delay = 0.0
	_respawn_player()
	queue_redraw()


func _process(delta: float) -> void:
	fullscreen_input_cooldown = maxf(0.0, fullscreen_input_cooldown - delta)
	if Input.is_action_just_pressed("back"):
		if title_screen:
			get_tree().quit()
		else:
			_return_to_title()
		return
	if title_screen:
		title_input_delay = maxf(0.0, title_input_delay - delta)
		queue_redraw()
		return
	if game_over:
		game_over_input_delay = maxf(0.0, game_over_input_delay - delta)
		if game_over_input_delay <= 0.0 and (Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_right")):
			_return_to_title()
		queue_redraw()
		return

	var keyboard_axis := Input.get_axis("move_left", "move_right")
	var axis := touch_axis if absf(touch_axis) > absf(keyboard_axis) else keyboard_axis
	previous_paddle_x = paddle_x
	paddle_x = clampf(paddle_x + axis * PADDLE_SPEED * delta, PADDLE_WIDTH * 0.5, FIELD_SIZE.x - PADDLE_WIDTH * 0.5)
	paddle_velocity = (paddle_x - previous_paddle_x) / maxf(delta, 0.0001)
	paddle_contact_cooldown = maxf(0.0, paddle_contact_cooldown - delta)

	run_seconds += delta
	var counts := _territory_counts()
	var territory_difference := absi(counts[LEFT] - counts[RIGHT])
	# A 20-cell difference advances the clock by one hour every five real seconds.
	doom_seconds += delta * _imbalance_clock_rate(territory_difference)

	for ball in war_balls:
		_step_ball(ball, delta, false)
	if player_ball_active:
		_step_ball(player_ball, delta, true)
	else:
		respawn_time_remaining -= delta
		if respawn_time_remaining <= 0.0:
			_respawn_player()
	_check_game_over()
	queue_redraw()


func _step_ball(ball: Dictionary, delta: float, is_player: bool) -> void:
	var velocity: Vector2 = ball.velocity
	var multiplier := _speed_multiplier(is_player)
	var travel := velocity * multiplier * delta
	var steps := maxi(1, ceili(travel.length() / (CELL * 0.28)))
	var step := travel / float(steps)
	for step_index in steps:
		var position: Vector2 = ball.position
		var next := position + step
		var war_bounced := false
		if next.x < BALL_RADIUS or next.x > FIELD_SIZE.x - BALL_RADIUS:
			velocity.x = -velocity.x
			step.x = -step.x
			next.x = clampf(position.x + step.x, BALL_RADIUS, FIELD_SIZE.x - BALL_RADIUS)
			war_bounced = true
		if next.y < BALL_RADIUS:
			velocity.y = absf(velocity.y)
			step.y = absf(step.y)
			next.y = BALL_RADIUS
			war_bounced = true
		if not is_player and next.y > FIELD_SIZE.y - BALL_RADIUS:
			velocity.y = -absf(velocity.y)
			step.y = -absf(step.y)
			next.y = FIELD_SIZE.y - BALL_RADIUS
			war_bounced = true
		if is_player and paddle_contact_cooldown <= 0.0:
			var progress_from := float(step_index) / float(steps)
			var progress_to := float(step_index + 1) / float(steps)
			var paddle_hit := _paddle_sweep(position, next, progress_from, progress_to)
			if paddle_hit.hit:
				var normal: Vector2 = paddle_hit.normal
				var contact: Vector2 = paddle_hit.position
				var contact_ratio: float = paddle_hit.time
				var speed: float = velocity.length()
				if normal.y < -0.5:
					var offset := clampf((contact.x - float(paddle_hit.paddle_x)) / (PADDLE_WIDTH * 0.5), -1.0, 1.0)
					var angle := offset * MAX_BOUNCE_ANGLE
					velocity = Vector2(sin(angle), -cos(angle)) * speed
					velocity.x += paddle_velocity * 0.12
					velocity = velocity.normalized() * speed
				else:
					velocity = velocity.bounce(normal)
				step = velocity * multiplier * delta / float(steps)
				next = contact + normal * 0.05 + step * (1.0 - contact_ratio)
				paddle_contact_cooldown = PADDLE_CONTACT_COOLDOWN
		if is_player and next.y > FIELD_SIZE.y + BALL_RADIUS:
			misses += 1
			doom_seconds += MISS_PENALTY
			_begin_player_respawn()
			return

		var hit := _find_hostile_cell(next, velocity, int(ball.team))
		if hit.x >= 0:
			cells[_index(hit.x, hit.y)] = int(ball.team)
			var cell_center := Vector2((hit.x + 0.5) * CELL, (hit.y + 0.5) * CELL)
			var difference := next - cell_center
			if absf(difference.x) > absf(difference.y):
				velocity.x = -velocity.x
				step.x = -step.x
			else:
				velocity.y = -velocity.y
				step.y = -step.y
			next = position + step
			war_bounced = true
		if not is_player and war_bounced:
			velocity = _jitter_war_velocity(velocity)
			step = velocity * multiplier * delta / float(steps)
		ball.position = next
	ball.velocity = velocity


func _find_hostile_cell(position: Vector2, velocity: Vector2, team: int) -> Vector2i:
	var directions: Array[Vector2] = [velocity.normalized(), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	for direction in directions:
		var probe: Vector2 = position + direction * BALL_RADIUS
		var x := floori(probe.x / CELL)
		var y := floori(probe.y / CELL)
		if x >= 0 and x < COLS and y >= 0 and y < ROWS and cells[_index(x, y)] != team:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


func _paddle_sweep(from: Vector2, to: Vector2, progress_from: float = 0.0, progress_to: float = 1.0) -> Dictionary:
	var paddle_from_x := lerpf(previous_paddle_x, paddle_x, progress_from)
	var paddle_to_x := lerpf(previous_paddle_x, paddle_x, progress_to)
	var relative_from := from - Vector2(paddle_from_x, 0.0)
	var relative_to := to - Vector2(paddle_to_x, 0.0)
	var paddle_y := FIELD_SIZE.y - 33.0
	var expanded := Rect2(
		Vector2(-PADDLE_WIDTH * 0.5 - BALL_RADIUS, paddle_y - PADDLE_HEIGHT * 0.5 - BALL_RADIUS),
		Vector2(PADDLE_WIDTH + BALL_RADIUS * 2.0, PADDLE_HEIGHT + BALL_RADIUS * 2.0)
	)
	var hit := _segment_rect_collision(relative_from, relative_to, expanded)
	if not hit.hit:
		return {"hit": false}
	var hit_time: float = hit.time
	var normal: Vector2 = hit.normal
	if normal == Vector2.ZERO:
		normal = _nearest_rect_normal(relative_from, expanded)
	var paddle_at_hit := lerpf(paddle_from_x, paddle_to_x, hit_time)
	var relative_contact := relative_from.lerp(relative_to, hit_time)
	return {
		"hit": true,
		"time": hit_time,
		"normal": normal,
		"position": relative_contact + Vector2(paddle_at_hit, 0.0),
		"paddle_x": paddle_at_hit,
	}


func _segment_rect_collision(from: Vector2, to: Vector2, rect: Rect2) -> Dictionary:
	var direction := to - from
	var t_enter := 0.0
	var t_exit := 1.0
	var hit_normal := Vector2.ZERO
	for axis in 2:
		var origin_value := from.x if axis == 0 else from.y
		var direction_value := direction.x if axis == 0 else direction.y
		var minimum := rect.position.x if axis == 0 else rect.position.y
		var maximum := rect.end.x if axis == 0 else rect.end.y
		if absf(direction_value) < 0.00001:
			if origin_value < minimum or origin_value > maximum:
				return {"hit": false}
			continue
		var near_time := (minimum - origin_value) / direction_value
		var far_time := (maximum - origin_value) / direction_value
		var near_normal := Vector2(-1.0, 0.0) if axis == 0 else Vector2(0.0, -1.0)
		if near_time > far_time:
			var swap := near_time
			near_time = far_time
			far_time = swap
			near_normal = Vector2(1.0, 0.0) if axis == 0 else Vector2(0.0, 1.0)
		if near_time > t_enter:
			t_enter = near_time
			hit_normal = near_normal
		t_exit = minf(t_exit, far_time)
		if t_enter > t_exit:
			return {"hit": false}
	if t_exit < 0.0 or t_enter > 1.0:
		return {"hit": false}
	return {"hit": true, "time": clampf(t_enter, 0.0, 1.0), "normal": hit_normal}


func _nearest_rect_normal(point: Vector2, rect: Rect2) -> Vector2:
	var distances := [
		absf(point.x - rect.position.x),
		absf(rect.end.x - point.x),
		absf(point.y - rect.position.y),
		absf(rect.end.y - point.y),
	]
	var normals := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	var closest := 0
	for index in range(1, distances.size()):
		if distances[index] < distances[closest]:
			closest = index
	return normals[closest]


func _speed_multiplier(is_player: bool = true) -> float:
	if is_player:
		return minf(1.0 + run_seconds / SPEEDUP_TO_DOUBLE_SECONDS, PLAYER_MAX_SPEED_MULTIPLIER)
	var war_acceleration := WAR_SPEED_AT_120_SECONDS - 1.0
	return minf(1.0 + run_seconds / SPEEDUP_TO_DOUBLE_SECONDS * war_acceleration, WAR_MAX_SPEED_MULTIPLIER)


func _random_war_velocity(horizontal_sign: float) -> Vector2:
	var vertical := rng.randf_range(-1.0, 1.0)
	if absf(vertical) < 0.3:
		vertical = (1.0 if rng.randf() > 0.5 else -1.0) * 0.3
	return Vector2(horizontal_sign, vertical).normalized() * ENEMY_START_SPEED


func _jitter_war_velocity(velocity: Vector2) -> Vector2:
	var speed := velocity.length()
	var direction := velocity.normalized().rotated(rng.randf_range(-WAR_BOUNCE_JITTER, WAR_BOUNCE_JITTER))
	if absf(direction.x) < 0.16:
		direction.x = (1.0 if direction.x >= 0.0 else -1.0) * 0.16
	if absf(direction.y) < 0.16:
		direction.y = (1.0 if direction.y >= 0.0 else -1.0) * 0.16
	return direction.normalized() * speed


func _imbalance_clock_rate(territory_difference: float) -> float:
	var normalized_difference := territory_difference / CLOCK_REFERENCE_TERRITORY_DIFFERENCE
	return CLOCK_RATE_AT_REFERENCE_DIFFERENCE * normalized_difference * normalized_difference


func _is_mobile_device() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func _begin_player_respawn() -> void:
	player_ball_active = false
	respawn_time_remaining = RESPAWN_DELAY


func _respawn_player() -> void:
	var spawn := _find_peace_spawn()
	if spawn.x < 0:
		player_ball_active = false
		_end_game("NO PLACE FOR PEACE")
		return
	paddle_x = clampf((spawn.x + 0.5) * CELL, PADDLE_WIDTH * 0.5, FIELD_SIZE.x - PADDLE_WIDTH * 0.5)
	player_ball.position = Vector2((spawn.x + 0.5) * CELL, (spawn.y + 0.5) * CELL)
	var launch_x := -0.42 if misses % 2 == 0 else 0.42
	player_ball.velocity = Vector2(launch_x, -1.0).normalized() * PLAYER_START_SPEED
	player_ball_active = true
	respawn_time_remaining = 0.0


func _find_peace_spawn() -> Vector2i:
	# Prefer the lowest neutral row and a location nearest the current paddle.
	for y in range(ROWS - 3, WAR_ROWS - 1, -1):
		var best := Vector2i(-1, -1)
		var best_distance := INF
		for x in COLS:
			if cells[_index(x, y)] == PEACE:
				var distance := absf((x + 0.5) * CELL - paddle_x)
				if distance < best_distance:
					best = Vector2i(x, y)
					best_distance = distance
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _territory_counts() -> Array[int]:
	var counts: Array[int] = [0, 0, 0]
	for owner in cells:
		counts[owner] += 1
	return counts


func _apply_initial_protrusions() -> void:
	# Vertical war boundary: two-cell fingers alternate left-to-right and right-to-left.
	for y in range(3, 5):
		cells[_index(COLS / 2, y)] = LEFT
	for y in range(9, 11):
		cells[_index(COLS / 2 - 1, y)] = RIGHT
	# Peace boundary: equal exchanges keep all three initial territory counts unchanged.
	for y in range(WAR_ROWS - 2, WAR_ROWS):
		cells[_index(3, y)] = PEACE
		cells[_index(19, y)] = PEACE
	for y in range(WAR_ROWS, WAR_ROWS + 2):
		cells[_index(7, y)] = LEFT
		cells[_index(15, y)] = RIGHT


func _check_game_over() -> void:
	var counts := _territory_counts()
	if doom_seconds >= DOOM_LIMIT:
		_end_game("MIDNIGHT")
	elif counts[LEFT] == 0:
		_end_game("LEFT SILENCED")
	elif counts[RIGHT] == 0:
		_end_game("RIGHT SILENCED")
	elif counts[PEACE] == 0:
		_end_game("PEACE ERASED")


func _end_game(reason: String) -> void:
	game_over = true
	game_over_reason = reason
	game_over_input_delay = GAME_OVER_INPUT_DELAY


func _input(event: InputEvent) -> void:
	# Consume this before title/game-over taps so the button never changes scenes.
	if _is_fullscreen_event(event):
		get_viewport().set_input_as_handled()
		if fullscreen_input_cooldown <= 0.0:
			_toggle_fullscreen()
			fullscreen_input_cooldown = FULLSCREEN_INPUT_COOLDOWN
		return
	if title_screen:
		if title_input_delay <= 0.0 and _is_start_event(event):
			title_screen = false
			reset_game()
		return
	if game_over and game_over_input_delay <= 0.0 and _is_start_event(event):
		_return_to_title()
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if show_touch_controls and touch.pressed and _is_touch_stick_start(touch.position) and touch_id < 0:
			touch_id = touch.index
			touch_axis = _touch_axis_for_position(touch.position)
		elif not touch.pressed and touch.index == touch_id:
			touch_id = -1
			touch_axis = 0.0
	elif show_touch_controls and event is InputEventScreenDrag and event.index == touch_id:
		touch_axis = _touch_axis_for_position(event.position)


func _is_touch_stick_start(position: Vector2) -> bool:
	return position.distance_to(TOUCH_STICK_CENTER) <= TOUCH_STICK_ACTIVATION_RADIUS


func _touch_axis_for_position(position: Vector2) -> float:
	return clampf((position.x - TOUCH_STICK_CENTER.x) / TOUCH_STICK_AXIS_RANGE, -1.0, 1.0)


func _is_fullscreen_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		return touch.pressed and FULLSCREEN_BUTTON_RECT.has_point(touch.position)
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		return mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and FULLSCREEN_BUTTON_RECT.has_point(mouse.position)
	return false


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _is_start_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo and key.keycode != KEY_ESCAPE
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		return button.pressed and button.button_index != JOY_BUTTON_B
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		return mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


func _return_to_title() -> void:
	title_screen = true
	title_input_delay = TITLE_INPUT_DELAY
	game_over = false
	game_over_reason = ""
	game_over_input_delay = 0.0
	touch_id = -1
	touch_axis = 0.0
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(960, 720)), BG)
	if title_screen:
		_draw_title_screen()
		_draw_fullscreen_button()
		return
	for y in ROWS:
		for x in COLS:
			var rect := Rect2(FIELD_ORIGIN + Vector2(x, y) * CELL, Vector2(CELL + 0.4, CELL + 0.4))
			draw_rect(rect, COLORS[cells[_index(x, y)]])
	for ball in war_balls:
		draw_circle(FIELD_ORIGIN + Vector2(ball.position), BALL_RADIUS, BALL_COLORS[int(ball.team)])
	if player_ball_active:
		draw_circle(FIELD_ORIGIN + Vector2(player_ball.position), BALL_RADIUS, BALL_COLORS[PEACE])
	var paddle_y := FIELD_SIZE.y - 33.0
	draw_rect(Rect2(FIELD_ORIGIN + Vector2(paddle_x - PADDLE_WIDTH * 0.5, paddle_y - PADDLE_HEIGHT * 0.5), Vector2(PADDLE_WIDTH, PADDLE_HEIGHT)), BALL_COLORS[PEACE])

	var counts := _territory_counts()
	var font := ThemeDB.fallback_font
	const UI_FONT_SIZE := 18
	const SCORE_Y := 664.0
	const CLOCK_Y := 700.0
	var territory_text := "LEFT  %03d  |  %03d  RIGHT" % [counts[LEFT], counts[RIGHT]]
	draw_string(font, Vector2(192, SCORE_Y), territory_text, HORIZONTAL_ALIGNMENT_CENTER, 576, UI_FONT_SIZE, INK)
	var clock_color := DANGER if doom_seconds > DOOM_LIMIT * 0.75 else INK
	draw_string(font, Vector2(192, CLOCK_Y), _format_clock(doom_seconds), HORIZONTAL_ALIGNMENT_CENTER, 576, UI_FONT_SIZE, clock_color)

	if show_touch_controls:
		# Native mobile and mobile Web only; a touchscreen desktop remains uncluttered.
		draw_circle(TOUCH_STICK_CENTER, 28.0, Color(1, 1, 1, 0.08))
		draw_circle(TOUCH_STICK_CENTER + Vector2(touch_axis * 20.0, 0.0), 11.0, Color(1, 1, 1, 0.30))
	if game_over:
		draw_rect(Rect2(FIELD_ORIGIN, FIELD_SIZE), Color(0.03, 0.08, 0.10, 0.86))
		draw_string(font, Vector2(192, 304), "THE CLOCK STRIKES", HORIZONTAL_ALIGNMENT_CENTER, 576, 28, DANGER)
		draw_string(font, Vector2(192, 346), game_over_reason, HORIZONTAL_ALIGNMENT_CENTER, 576, 18, INK)
		var restart_text := "PRESS ANY KEY TO RETURN TO TITLE" if game_over_input_delay <= 0.0 else "·  ·  ·"
		draw_string(font, Vector2(192, 394), restart_text, HORIZONTAL_ALIGNMENT_CENTER, 576, 14, MUTED)
	_draw_fullscreen_button()


func _draw_fullscreen_button() -> void:
	var center := FULLSCREEN_BUTTON_RECT.get_center()
	var left := center.x - 9.0
	var right := center.x + 9.0
	var top := center.y - 9.0
	var bottom := center.y + 9.0
	const ARM := 6.0
	draw_circle(center, 22.0, Color(1, 1, 1, 0.10))
	draw_line(Vector2(left, top + ARM), Vector2(left, top), MUTED, 2.0)
	draw_line(Vector2(left, top), Vector2(left + ARM, top), MUTED, 2.0)
	draw_line(Vector2(right - ARM, top), Vector2(right, top), MUTED, 2.0)
	draw_line(Vector2(right, top), Vector2(right, top + ARM), MUTED, 2.0)
	draw_line(Vector2(left, bottom - ARM), Vector2(left, bottom), MUTED, 2.0)
	draw_line(Vector2(left, bottom), Vector2(left + ARM, bottom), MUTED, 2.0)
	draw_line(Vector2(right - ARM, bottom), Vector2(right, bottom), MUTED, 2.0)
	draw_line(Vector2(right, bottom - ARM), Vector2(right, bottom), MUTED, 2.0)


func _draw_title_screen() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(192, 154), "PEACEKEEPER", HORIZONTAL_ALIGNMENT_CENTER, 576, 36, INK)
	draw_string(font, Vector2(192, 190), "KEEP THE BALANCE", HORIZONTAL_ALIGNMENT_CENTER, 576, 13, MUTED)

	var mark := Rect2(Vector2(360, 236), Vector2(240, 180))
	draw_rect(Rect2(mark.position, Vector2(mark.size.x * 0.5, mark.size.y)), COLORS[LEFT])
	draw_rect(Rect2(mark.position + Vector2(mark.size.x * 0.5, 0), Vector2(mark.size.x * 0.5, mark.size.y)), COLORS[RIGHT])
	# Alternating notches echo the initial battlefield without adding decoration.
	draw_rect(Rect2(mark.position + Vector2(mark.size.x * 0.5, 42), Vector2(12, 24)), COLORS[LEFT])
	draw_rect(Rect2(mark.position + Vector2(mark.size.x * 0.5 - 12, 112), Vector2(12, 24)), COLORS[RIGHT])
	draw_circle(mark.position + Vector2(70, 56), 8.0, BALL_COLORS[LEFT])
	draw_circle(mark.position + Vector2(178, 128), 8.0, BALL_COLORS[RIGHT])

	var prompt := "PRESS ANY KEY" if title_input_delay <= 0.0 else ""
	draw_string(font, Vector2(192, 484), prompt, HORIZONTAL_ALIGNMENT_CENTER, 576, 15, INK)
	draw_string(font, Vector2(192, 530), "A / D  ·  ARROWS  ·  GAMEPAD", HORIZONTAL_ALIGNMENT_CENTER, 576, 12, MUTED)


func _format_clock(value: float) -> String:
	var seconds := clampi(floori(value), 0, int(DOOM_LIMIT))
	return "%02d:%02d:%02d" % [seconds / 3600, (seconds % 3600) / 60, seconds % 60]


func _index(x: int, y: int) -> int:
	return y * COLS + x
