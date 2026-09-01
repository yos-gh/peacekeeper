extends SceneTree


func _initialize() -> void:
	call_deferred("_verify_sentry")


func _verify_sentry() -> void:
	if not SentrySDK.is_enabled():
		SentrySDK.init()

	if not SentrySDK.is_enabled():
		push_error("Sentry SDK failed to initialize.")
		quit(1)
		return

	SentrySDK.add_breadcrumb(
		SentryBreadcrumb.create("PEACEKEEPER Sentry verification is about to run.")
	)
	var event_id := SentrySDK.capture_message("PEACEKEEPER Sentry integration verified.")
	if event_id.is_empty():
		push_error("Sentry verification did not return an event ID.")
		quit(1)
		return

	print("SENTRY_VERIFICATION_EVENT_ID: %s" % event_id)
	await create_timer(2.0).timeout
	SentrySDK.close()
	await create_timer(2.0).timeout
	quit(0)
