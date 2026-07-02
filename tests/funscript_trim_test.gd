extends GdUnitTestSuite

# Per-round video trim — the pure core: trim_action_points (window + rebase +
# boundary-stroke interpolation), trim_funscript_json (metadata preservation),
# and the trim-aware media fingerprint that keys the content pool.


func _pts(pairs: Array) -> Array:
	var out: Array = []
	for p: Array in pairs:
		out.append(Vector2(p[0], p[1]))
	return out


# Actions landing exactly on the cut points are kept and rebased; nothing is
# synthesized.
func test_exact_window_shift() -> void:
	var points := _pts([[0, 0], [1000, 100], [2000, 0], [3000, 100], [4000, 0]])
	var trimmed: Array = JourneyData.trim_action_points(points, 1000, 3000)
	assert_array(trimmed).is_equal(_pts([[0, 100], [1000, 0], [2000, 100]]))


# An in-cut landing mid-stroke synthesizes the interpolated position at t=0 so
# the device starts where the video shows it, not at home.
func test_in_cut_mid_stroke_interpolates() -> void:
	var trimmed: Array = JourneyData.trim_action_points(_pts([[0, 0], [2000, 100]]), 1000, 0)
	assert_array(trimmed).is_equal(_pts([[0, 50], [1000, 100]]))


# An out-cut landing mid-stroke synthesizes the interpolated end position.
func test_out_cut_mid_stroke_interpolates() -> void:
	var trimmed: Array = JourneyData.trim_action_points(
		_pts([[0, 0], [2000, 100], [4000, 0]]), 0, 3000
	)
	assert_array(trimmed).is_equal(_pts([[0, 0], [2000, 100], [3000, 50]]))


# A window entirely inside one long stroke yields the two interpolated anchors.
func test_window_inside_single_stroke() -> void:
	var trimmed: Array = JourneyData.trim_action_points(_pts([[0, 0], [4000, 100]]), 1000, 3000)
	assert_array(trimmed).is_equal(_pts([[0, 25], [2000, 75]]))


# out_ms <= 0 means "to the end": only the head is cut.
func test_out_zero_keeps_tail() -> void:
	var trimmed: Array = JourneyData.trim_action_points(
		_pts([[0, 0], [1000, 100], [2000, 0]]), 1000, 0
	)
	assert_array(trimmed).is_equal(_pts([[0, 100], [1000, 0]]))


# Degenerate windows produce an empty script (presave validation blocks them,
# but the pure function must not misbehave).
func test_invalid_window_is_empty() -> void:
	assert_array(JourneyData.trim_action_points(_pts([[0, 0], [1000, 100]]), 2000, 1000)).is_empty()
	assert_array(JourneyData.trim_action_points([], 0, 1000)).is_empty()


# trim_funscript_json rebases the actions as {at, pos} ints and preserves every
# other metadata key untouched.
func test_trim_funscript_json_preserves_metadata() -> void:
	var fs := {
		"version": "1.0",
		"inverted": false,
		"range": 90,
		"actions": [{"at": 0, "pos": 0}, {"at": 1000, "pos": 100}, {"at": 2000, "pos": 0}],
	}
	var trimmed: Dictionary = JourneyData.trim_funscript_json(fs, 1000, 2000)
	assert_str(str(trimmed["version"])).is_equal("1.0")
	assert_bool(bool(trimmed["inverted"])).is_false()
	assert_int(int(trimmed["range"])).is_equal(90)
	assert_array(trimmed["actions"]).is_equal([{"at": 0, "pos": 100}, {"at": 1000, "pos": 0}])


# The fingerprint keys the content pool: untrimmed stays byte-identical to the
# legacy form (existing pooled rels survive), identical trims share, different
# trims split.
# The mm:ss helpers behind the trim fields round-trip cleanly.
func test_mmss_helpers() -> void:
	assert_int(JourneyData.mmss_to_ms("2:30")).is_equal(150000)
	assert_int(JourneyData.mmss_to_ms("1:02:03")).is_equal(3723000)
	assert_int(JourneyData.mmss_to_ms("90")).is_equal(90000)
	assert_int(JourneyData.mmss_to_ms("")).is_equal(0)
	assert_str(JourneyData.ms_to_mmss(150000)).is_equal("2:30")
	assert_str(JourneyData.ms_to_mmss(0)).is_equal("0:00")
	assert_int(JourneyData.mmss_to_ms(JourneyData.ms_to_mmss(754000))).is_equal(754000)


func test_fingerprint_trim_awareness() -> void:
	var src := "user://some_video.mp4"
	assert_str(JourneyData.media_fingerprint(src, 0, 0)).is_equal(
		JourneyData.media_fingerprint(src)
	)
	assert_str(JourneyData.media_fingerprint(src, 1000, 3000)).is_equal(
		JourneyData.media_fingerprint(src, 1000, 3000)
	)
	(
		assert_bool(
			JourneyData.media_fingerprint(src, 1000, 3000) == JourneyData.media_fingerprint(src)
		)
		. is_false()
	)
	(
		assert_bool(
			(
				JourneyData.media_fingerprint(src, 1000, 3000)
				== JourneyData.media_fingerprint(src, 1000, 4000)
			)
		)
		. is_false()
	)
