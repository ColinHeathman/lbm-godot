@tool
extends EditorScript


const WIDTH = 256;
const HEIGHT = 256;
const centre = Vector2i(64,128);
const RADIUS = 12.0;

func _run():
	var img = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	
	for y in HEIGHT:
		for x in WIDTH:
			var px = Vector2i(x, y)
			var r = px - centre
			var r_len = r.length()
			if r_len > RADIUS:
				img.set_pixel(x, y, Color.TRANSPARENT)
			else:
				# l^2 = x^2 + y^2 + z^2
				# z^2 = l^2 - x^2 - y^2
				var z: float = sqrt(RADIUS*RADIUS - r.length_squared() as float)
				var n = Vector3(r.x as float, r.y as float, z).normalized()
				var c = Color.BLACK
				c.r = (n.x * 0.5) + 0.5
				c.g = (n.y * 0.5) + 0.5
				c.b = (n.z * 0.25) + 0.75
				img.set_pixel(x, y, c)
	
	img.save_png("res://compute/obstacles.png")
