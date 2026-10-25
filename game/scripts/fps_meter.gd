class_name FpsMeter
extends Control
## Frame time in the corner. Off until Settings or the F4 key asks for it. The number is a half-second average;
## the 1% low is the average of the slowest hundredth of the last few seconds, and the strip is those frame times.

const WINDOW := 240

var _samples: Array[float] = []
var _avg := 0.0
var _shown := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Inside the 3D view, under the time-compression row, so it does not cover the condition clock.
	position = Vector2(948, 122)
	size = Vector2(160, 44)

func _process(delta: float) -> void:
	if not visible: return
	_samples.append(delta)
	if _samples.size() > WINDOW: _samples.pop_front()
	_avg = lerpf(_avg if _avg > 0.0 else delta, delta, 1.0 - exp(-delta / 0.4))
	_shown = _avg
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.02, 0.035, 0.05, 0.82))
	draw_rect(r, W.LINE, false, 1.0)
	var fps := 1.0 / _shown if _shown > 1.0e-4 else 0.0
	var low := _low_fps()
	draw_string(W.FM, Vector2(8, 16), "%d FPS  %.1f ms" % [int(round(fps)), _shown * 1000.0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, W.TEXT)
	draw_string(W.FM, Vector2(8, 30), "1%% LOW  %d" % [int(round(low))], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, W.MUTED)
	if _samples.size() < 2: return
	var plot := Rect2(8, 34, size.x - 16, 12)
	var worst := 0.001
	for s in _samples: worst = maxf(worst, s)
	var n := _samples.size()
	for i in n - 1:
		var x0 := plot.position.x + plot.size.x * float(i) / float(n - 1)
		var x1 := plot.position.x + plot.size.x * float(i + 1) / float(n - 1)
		var y0 := plot.end.y - plot.size.y * clampf(_samples[i] / worst, 0.0, 1.0)
		var y1 := plot.end.y - plot.size.y * clampf(_samples[i + 1] / worst, 0.0, 1.0)
		draw_line(Vector2(x0, y0), Vector2(x1, y1), W.SEC, 1.0)

func _low_fps() -> float:
	if _samples.is_empty(): return 0.0
	var ordered := _samples.duplicate()
	ordered.sort()
	var tail := maxi(1, int(ceil(ordered.size() * 0.01)))
	var acc := 0.0
	for i in tail: acc += ordered[ordered.size() - 1 - i]
	var ms := acc / tail
	return 1.0 / ms if ms > 1.0e-4 else 0.0
