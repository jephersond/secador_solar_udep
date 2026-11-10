class_name Bruma
extends Node

# ======================================================================
#  bruma.gd - Niebla de distancia y franja de horizonte en el cielo
# ======================================================================

var clima: Clima
var cielo: Cielo                  # Asignado directamente desde principal.gd
var terreno: Node = null

var auto_limites: bool = true
var inicio: float = 70.0
var fin: float = 230.0
var curva: float = 1.9
var margen: float = 45.0
var intensidad_cielo: float = 0.9

var _env: Environment
var _mat_cielo: ShaderMaterial
var _limites_listos: bool = false
var _color: Color = Color(0.86, 0.85, 0.82)
var _lluvia: float = 0.0
var _prev_nubes: float = -1.0
var _prev_lluvia: float = -1.0
var _prev_hora: float = -1.0


func _ready() -> void:
	process_priority = 100
	_conectar_cielo()


func _conectar_cielo() -> void:
	if cielo != null:
		_env = cielo.env
		_mat_cielo = cielo.mat_cielo
	else:
		# Respaldo si no se asignó la referencia
		var we_node = get_tree().get_first_node_in_group("ambiente")
		if we_node is WorldEnvironment:
			_env = we_node.environment
			if _env and _env.sky and _env.sky.sky_material is ShaderMaterial:
				_mat_cielo = _env.sky.sky_material


func _calcular_limites() -> void:
	if not auto_limites or terreno == null or not terreno.is_inside_tree():
		_limites_listos = true
		return

	var caja := AABB()
	var primero := true
	var cola: Array[Node] = [terreno]

	while not cola.is_empty():
		var actual = cola.pop_back()
		if actual is MeshInstance3D and actual.mesh != null:
			var a: AABB = actual.global_transform * actual.get_aabb()
			if primero:
				caja = a
				primero = false
			else:
				caja = caja.merge(a)
		cola.append_array(actual.get_children())

	if primero:
		return

	var d: float = minf(minf(caja.end.x, -caja.position.x), minf(caja.end.z, -caja.position.z))
	fin = clampf(d - margen, 80.0, 400.0)
	inicio = fin * 0.3
	_limites_listos = true
	print("[BRUMA] Terreno detectado -> Niebla fijada de %.0f a %.0f m" % [inicio, fin])


func _calcular_color(nubes: float, lluvia: float, hora: float, doy: int) -> void:
	# Unificado con la elevación real de Sitio
	var elev: float = Sitio.posicion_sol(hora * 3600.0, doy).x
	var dia: float = smoothstep(-6.0, 8.0, elev)
	var crep: float = 1.0 - absf(dia * 2.0 - 1.0)

	var col := Color(0.86, 0.85, 0.82).lerp(Color(0.713, 0.788, 0.774, 0.62), nubes)
	col = col.lerp(Color(0.52, 0.55, 0.60), lluvia * 0.6)
	col = col.lerp(Color(0.95, 0.70, 0.55), crep * 0.45 * (1.0 - nubes))
	_color = Color(0.04, 0.05, 0.10).lerp(col, dia)


func _process(_delta: float) -> void:
	if _env == null:
		_conectar_cielo()
		if _env == null: return

	if not _limites_listos:
		_calcular_limites()

	var nubes: float = clima.nubes if clima else 0.0
	var lluvia: float = clima.lluvia if clima else 0.0
	var hora: float = clima.hora if clima else 12.0
	var doy: int = clima.doy if clima else 296

	# Recálculo de color solo si hay cambio medible
	if absf(nubes - _prev_nubes) > 0.01 or absf(lluvia - _prev_lluvia) > 0.01 or absf(hora - _prev_hora) > 0.02:
		_prev_nubes = nubes
		_prev_lluvia = lluvia
		_prev_hora = hora
		_lluvia = lluvia
		_calcular_color(nubes, lluvia, hora, doy)
		if _mat_cielo != null:
			_mat_cielo.set_shader_parameter("bruma_color", _color)
			_mat_cielo.set_shader_parameter("bruma", intensidad_cielo)

	# Control único de niebla de profundidad sobre el Environment
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_light_color = _color
	_env.fog_density = 1.0
	_env.fog_depth_begin = lerpf(inicio, minf(inicio, 25.0), _lluvia)
	_env.fog_depth_end = lerpf(fin, minf(110.0, fin), _lluvia)
	_env.fog_depth_curve = curva
	_env.fog_aerial_perspective = 0.0
	_env.fog_sky_affect = 0.0
