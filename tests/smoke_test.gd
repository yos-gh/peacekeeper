extends SceneTree


func _init() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	assert(game.title_screen)
	assert(is_equal_approx(game.title_input_delay, game.TITLE_INPUT_DELAY))
	game.title_screen = false
	assert(game.cells.size() == game.COLS * game.ROWS)
	var counts: Array[int] = game._territory_counts()
	assert(game.WAR_ROWS == 15)
	assert(game.ROWS - game.WAR_ROWS == 11)
	assert(counts[game.LEFT] == game.COLS / 2 * game.WAR_ROWS)
	assert(counts[game.RIGHT] == game.COLS / 2 * game.WAR_ROWS)
	assert(counts[game.PEACE] == game.COLS * (game.ROWS - game.WAR_ROWS))
	assert(game.cells[game._index(game.COLS / 2, 3)] == game.LEFT)
	assert(game.cells[game._index(game.COLS / 2 - 1, 9)] == game.RIGHT)
	assert(game.cells[game._index(3, game.WAR_ROWS - 1)] == game.PEACE)
	assert(game.cells[game._index(7, game.WAR_ROWS)] == game.LEFT)
	assert(game._format_clock(0.0) == "00:00:00")
	assert(game._format_clock(game.DOOM_LIMIT) == "24:00:00")
	assert(game._find_peace_spawn().x >= 0)
	game.run_seconds = 120.0
	assert(is_equal_approx(game._speed_multiplier(), 2.0))
	assert(is_equal_approx(game._speed_multiplier(false), 4.0))
	game.run_seconds = 100000.0
	assert(is_equal_approx(game._speed_multiplier(true), 2.0))
	assert(is_equal_approx(game._speed_multiplier(false), 8.0))
	var fast_war_ball: Dictionary = game.war_balls[0].duplicate(true)
	for frame in 300:
		game._step_ball(fast_war_ball, 1.0 / 60.0, false)
	assert(fast_war_ball.position.x >= game.BALL_RADIUS)
	assert(fast_war_ball.position.x <= game.FIELD_SIZE.x - game.BALL_RADIUS)
	assert(fast_war_ball.position.y >= game.BALL_RADIUS)
	assert(fast_war_ball.position.y <= game.FIELD_SIZE.y - game.BALL_RADIUS)
	game.reset_game()
	assert(is_equal_approx(game._imbalance_clock_rate(0.0), 0.0))
	assert(is_equal_approx(game._imbalance_clock_rate(10.0), 180.0))
	assert(is_equal_approx(game._imbalance_clock_rate(20.0), 720.0))
	assert(is_equal_approx(game._imbalance_clock_rate(20.0) * 5.0, 60.0 * 60.0))
	assert(is_equal_approx(game._imbalance_clock_rate(40.0), 2880.0))
	game.paddle_x = game.FIELD_SIZE.x * 0.5
	game.previous_paddle_x = game.paddle_x
	var paddle_y: float = game.FIELD_SIZE.y - 33.0
	var paddle_top: float = game.FIELD_SIZE.y - 33.0 - game.PADDLE_HEIGHT * 0.5
	var paddle_bottom: float = paddle_y + game.PADDLE_HEIGHT * 0.5
	var paddle_left: float = game.paddle_x - game.PADDLE_WIDTH * 0.5
	var top_hit: Dictionary = game._paddle_sweep(Vector2(game.paddle_x, paddle_top - game.BALL_RADIUS - 2.0), Vector2(game.paddle_x, paddle_top - game.BALL_RADIUS + 2.0))
	assert(top_hit.hit and top_hit.normal == Vector2.UP)
	var bottom_hit: Dictionary = game._paddle_sweep(Vector2(game.paddle_x, paddle_bottom + game.BALL_RADIUS + 2.0), Vector2(game.paddle_x, paddle_bottom + game.BALL_RADIUS - 2.0))
	assert(bottom_hit.hit and bottom_hit.normal == Vector2.DOWN)
	var side_hit: Dictionary = game._paddle_sweep(Vector2(paddle_left - game.BALL_RADIUS - 2.0, paddle_y), Vector2(paddle_left - game.BALL_RADIUS + 2.0, paddle_y))
	assert(side_hit.hit and side_hit.normal == Vector2.LEFT)
	var corner_hit: Dictionary = game._paddle_sweep(Vector2(paddle_left - game.BALL_RADIUS - 2.0, paddle_top - game.BALL_RADIUS - 2.0), Vector2(paddle_left - game.BALL_RADIUS + 2.0, paddle_top - game.BALL_RADIUS + 2.0))
	assert(corner_hit.hit)
	# Regression: a moving paddle catches an overlapping diagonal graze.
	game.previous_paddle_x = game.paddle_x - game.PADDLE_WIDTH
	assert(game._paddle_sweep(Vector2(game.paddle_x, paddle_top - game.BALL_RADIUS + 1.0), Vector2(game.paddle_x, paddle_top - game.BALL_RADIUS + 2.0)).hit)
	# A moving paddle must not pull a separated ball down to its face.
	assert(not game._paddle_sweep(Vector2(game.paddle_x, paddle_top - game.BALL_RADIUS - 3.0), Vector2(game.paddle_x, paddle_top - game.BALL_RADIUS - 2.0)).hit)
	game.run_seconds = 0.0
	for frame in 120:
		game._process(1.0 / 60.0)
	assert(not game.game_over)
	game._begin_player_respawn()
	assert(not game.player_ball_active)
	assert(is_equal_approx(game.respawn_time_remaining, game.RESPAWN_DELAY))
	game._process(0.25)
	assert(not game.player_ball_active)
	game._process(0.26)
	assert(game.player_ball_active)
	game._end_game("TEST")
	assert(game.game_over)
	assert(is_equal_approx(game.game_over_input_delay, game.GAME_OVER_INPUT_DELAY))
	game._process(0.5)
	assert(game.game_over)
	assert(game.game_over_input_delay > 0.0)
	game._return_to_title()
	assert(game.title_screen)
	assert(not game.game_over)
	assert(is_equal_approx(game.title_input_delay, game.TITLE_INPUT_DELAY))
	print("PASS: Peacekeeper smoke test")
	quit()
