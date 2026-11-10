class_name Charcos
extends Node3D

# ======================================================================
#  charcos.gd - Charcos de lluvia irregulares y reflectantes
# ======================================================================

const MAX_CHARCOS: int = 24
const N_FORMAS: int = 6
const RES: int = 64                   # 64x64: Carga más de 2x más rápido sin perder suavidad

var nivel_suelo: float = 0.8
var centro: Vector3 = Vector3.ZERO
var radio_min: float = 7.0
var radio_max: float = 34.0
var vel_aparicion: float = 1.0

# Clase interna tipada: elimina el acceso por diccionarios en cada cuadro
class CharcoData:
	var nodo: Decal
	var edad: float = 0.0
	var vida: float = 0.0
	var tam: float = 2.0
	var ex: float = 1.0
	var ez: float = 1.0
	var fase: float = 0.0
	var activo: bool = false

var _formas: Array[Dictionary] = []
var _orm: Texture2D
var _charcos: Array[CharcoData] = []
var _timer: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	for i in range(N_FORMAS):
		_formas.append(_crear_forma(101 + i * 37))

	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(1.0, 0.02, 0.0))
	_orm = ImageTexture.create_from_image(img)

	for i in range(MAX_CHARCOS):
		var d := Decal.new()
		d.texture_orm = _orm
		d.size = Vector3(2.0, 3.0, 2.0)
		d.modulate = Color(1.0, 1.0, 1.0, 0.0)
		d.emission_energy = 0.0
		d.visible = false
		add_child(d)

		var c := CharcoData.new()
		c.nodo = d
		_charcos.append(c)

func _crear_forma(semilla: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var fases: Array[float] = [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var amp: Array[float] = [
		rng.randf_range(0.10, 0.22), rng.randf_range(0.08, 0.16),
		rng.randf_range(0.04, 0.10), rng.randf_range(0.02, 0.06)
	]
	var ruido := FastNoiseLite.new()
	ruido.seed = semilla
	ruido.frequency = 0.05

	var alb := Image.create_empty(RES, RES, false, Image.FORMAT_RGBA8)
	var emi := Image.create_empty(RES, RES, false, Image.FORMAT_RGB8)
	var azul := Color(0.55, 0.68, 0.88)

	for y in range(RES):
		for x in range(RES):
			var dx: float = (float(x) + 0.5) / float(RES) * 2.0 - 1.0
			var dy: float = (float(y) + 0.5) / float(RES) * 2.0 - 1.0
			var r: float = sqrt(dx * dx + dy * dy)
			var a: float = atan2(dy, dx)
			var R: float = 0.58 * (1.0 + amp[0] * sin(2.0 * a + fases[0]) + amp[1] * sin(3.0 * a + fases[1])
				+ amp[2] * sin(5.0 * a + fases[2]) + amp[3] * sin(7.0 * a + fases[3]))
			R += ruido.get_noise_2d(x, y) * 0.06
			var m: float = 1.0 - smoothstep(R * 0.72, R, r)
			alb.set_pixel(x, y, Color(0.09, 0.085, 0.08, m * 0.9))
			emi.set_pixel(x, y, Color(azul.r * m, azul.g * m, azul.b * m))

	return {
		"albedo": ImageTexture.create_from_image(alb),
		"emision": ImageTexture.create_from_image(emi),
	}

func _nuevo() -> void:
	for c in _charcos:
		if c.activo:
			continue
		var ang := randf() * TAU
		var r := randf_range(radio_min, radio_max)
		var forma: Dictionary = _formas[randi() % N_FORMAS]
		
		c.nodo.texture_albedo = forma["albedo"]
		c.nodo.texture_emission = forma["emision"]
		c.nodo.position = Vector3(centro.x + cos(ang) * r, nivel_suelo, centro.z + sin(ang) * r)
		c.nodo.rotation.y = randf() * TAU
		c.tam = randf_range(2.0, 5.5)
		c.ex = randf_range(0.7, 1.5)
		c.ez = randf_range(0.7, 1.5)
		c.fase = randf() * TAU
		c.edad = 0.0
		c.vida = randf_range(35.0, 80.0)
		c.activo = true
		c.nodo.visible = true
		return


func actualizar(delta: float, lluvia: float, nubes: float, luz_dia: float) -> void:
	_t += delta
	if lluvia > 0.25:
		_timer -= delta
		if _timer <= 0.0:
			_timer = randf_range(0.6, 2.0) / (lluvia * vel_aparicion)
			_nuevo()

	var seca := lluvia < 0.1
	var reflejo := luz_dia * (0.25 + 0.35 * (1.0 - nubes)) + 0.03

	for c in _charcos:
		if not c.activo:
			continue
		
		c.edad += delta * (3.0 if seca else 1.0)
		var t := c.edad
		var v := c.vida
		if t >= v:
			c.activo = false
			c.nodo.visible = false
			continue

		var entra := 1.0 - pow(1.0 - smoothstep(0.0, 2.5, t), 3.0)
		var sale := 1.0 - smoothstep(v - 12.0, v, t)
		var a := entra * sale
		var encoge := lerpf(1.0, 0.55, smoothstep(v - 12.0, v, t))

		var wx := 1.0 + 0.10 * sin(_t * 2.1 + c.fase)
		var wz := 1.0 + 0.10 * sin(_t * 1.5 + c.fase * 1.7 + 1.0)
		var base := c.tam * lerpf(0.45, 1.0, entra) * encoge

		c.nodo.size = Vector3(base * c.ex * wx, 3.0, base * c.ez * wz)
		c.nodo.modulate.a = a
		c.nodo.emission_energy = reflejo * a
