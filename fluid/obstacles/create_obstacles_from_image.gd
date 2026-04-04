@tool
extends EditorScript


const WIDTH = 2048;
const HEIGHT = 256;
const centre = Vector2i(64,128);
const RADIUS = 12.0;

const OBSTACLE : int = 1;
const E: int   = 1<<1;
const N: int   = 1<<2;
const W: int   = 1<<3;
const S: int   = 1<<4;

func _run():
	var img = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_R8)
	var input = preload("res://fluid/obstacles/input_1.png")
	
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var px = Vector2i(x, y)
			
			if input.get_pixelv(px).a8 == 0:
				img.set_pixel(x, y, 0)
			else:
				img.set_pixel(x, y, Color.from_rgba8(OBSTACLE, 0, 0, 0))
	
	for y in range(1, HEIGHT-1):
		for x in range(1, WIDTH-1):
			var r = img.get_pixel(x, y).r8

			if img.get_pixel(x+1, y).r8 & OBSTACLE > 0:
				r |= E
			if img.get_pixel(x-1, y).r8 & OBSTACLE > 0:
				r |= W
			if img.get_pixel(x, y+1).r8 & OBSTACLE > 0:
				r |= S
			if img.get_pixel(x, y-1).r8 & OBSTACLE > 0:
				r |= N

			img.set_pixel(x, y, Color.from_rgba8(r, 0, 0, 0))

	img.save_png("res://fluid/obstacles/obstacles_1.png")
