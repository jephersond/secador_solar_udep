class_name SombrasNubes
extends Node3D

# ======================================================================
#  sombras_nubes.gd - Sombras de nubes en suelo mediante Decals
# ======================================================================

const TAM: float = 200.0
var viento_dir: Vector2 = Vector2(1.0, 0.35).normalized()
var viento_vel: float = 2.0
var oscuridad_max: float = 0.8
var altura: float = 40.0

class SombraData:
	var nodo: Decal
	var base: Vector2

var _capas: Array[Array] = []
var _offset: Vector2 = Vector2.ZERO


func _crear_textura(umbral_ini: float, umbral_fin: float) -> NoiseTexture2D:
	var ruido := FastNoiseLite.new()
	ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ruido.fractal_type = FastNoiseLite.FRACTAL_FBM
	ruido.fractal_octaves = 4
	ruido.frequency = 0.006
	ruido.seed = 7

	var c_hueco := Color(0.02, 0.03, 0.08, 0.0)
	var c_media := Color(0.02, 0.03, 0.08, 0.85)
	var rampa := Gradient.new()
	rampa.set_offset(0, 0.0)
	rampa.set_color(0, c_hueco)
	rampa.set_offset(1, 1.0)
	rampa.set_color(1, Color(0.02, 0.03, 0.08, 1.0))
	rampa.add_point(umbral_ini, c_hueco)
	rampa.add_point(umbral_fin, c_media)

	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = ruido
	tex.color_ramp = rampa
	return tex


func _ready() -> void:
	var texturas := [
		_crear_textura(0.50, 0.66),
		_crear_textura(0.36, 0.52),
	]

	for k in range(2):
		var lista: Array[SombraData] = []
		for i in range(-1, 2):
			for j in range(-1, 2):
				var d := Decal.new()
				d.size = Vector3(TAM, 100.0, TAM)
				d.texture_albedo = texturas[k]
				d.modulate = Color(1.0, 1.0, 1.0, 0.0)
				d.visible = false
				add_child(d)

				var item := SombraData.new()
				item.nodo = d
				item.base = Vector2(i * TAM, j * TAM)
				lista.append(item)
		_capas.append(lista)


func actualizar(delta: float, nubes: float, luz_dia: float) -> void:
	_offset += viento_dir * viento_vel * delta
	var medio := TAM * 1.5
	var total := TAM * 3.0

	var base := smoothstep(0.02, 0.30, nubes) * luz_dia * oscuridad_max
	var cobertura := smoothstep(0.35, 0.95, nubes)
	var fuerzas := [base * (1.0 - cobertura), base * cobertura]

	for k in range(2):
		var f: float = fuerzas[k]
		var vis := f > 0.01
		for item: SombraData in _capas[k]:
			var p := item.base + _offset
			p.x = fposmod(p.x + medio, total) - medio
			p.y = fposmod(p.y + medio, total) - medio
			item.nodo.position = Vector3(p.x, altura, p.y)
			item.nodo.modulate.a = f
			item.nodo.visible = vis
