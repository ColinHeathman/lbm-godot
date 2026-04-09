extends Label

var prev = Time.get_ticks_usec()
var _fps: float = 0.0
var i: int = 100

func update() -> void:
	var now = Time.get_ticks_usec()
	var frame_time = now - prev
	prev = now
	
	var current_fps = 1000000.0 / frame_time
	_fps = (_fps * 9.0 + current_fps) / 10.0
	i += 1
	if i > 100:
		i = 0
		self.text = "%4.0f UPS" % _fps
