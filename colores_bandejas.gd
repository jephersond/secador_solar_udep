class_name ColoresBandejas
extends Node

const MAPA := {1: 6, 2: 5, 3: 4, 4: 7, 5: 8, 6: 9}
const T_MIN := 32.0
const T_MAX := 42.0
const GRAD := [Color(0.098, 0.902, 0.784), Color(0.40, 0.74, 0.52), Color(0.70, 0.58, 0.26), Color(1.0, 0.416, 0.0)]
const FILTRO := "malla"

var datos: DatosSensores
var clima: Clima
var secador: Node3D
var _mats := {}
var _t_vivo: float = 0.0


func _ready() -> void:
	for n in MAPA:
		var raiz := secador.get_node_or_null("bandeja_B%d" % n)
		if raiz == null:
			push_warning("[BANDEJAS] no encuentro bandeja_B%d" % n)
			continue
		var todas := raiz.find_children("*", "MeshInstance3D", true, false)
		var elegidas := todas.filter(func(m): return FILTRO in m.name.to_lower())
		if elegidas.is_empty():
			elegidas = todas
		print("[BANDEJAS] B%d meshes: %s | coloreo: %s" % [n, todas.map(func(m): return m.name), elegidas.map(func(m): return m.name)])
		_mats[n] = []
		for m in elegidas:
			var base = m.get_active_material(0)
			var mat: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
			m.material_override = mat
			_mats[n].append(mat)
	datos.minuto_cambiado.connect(_refrescar)
	datos.correccion_cambiada.connect(_refrescar)
	datos.datos_cargados.connect(_refrescar)
	datos.modo_vivo_cambiado.connect(_refrescar)
	if clima != null:
		clima.modo_cambiado.connect(_refrescar)
	_refrescar()

func _color(t: float) -> Color:
	# Si el sensor no respondió o tiene falla en este minuto, color neutro apagado
	if is_nan(t):
		return Color(0.22, 0.24, 0.28)

	var k := clampf((t - T_MIN) / (T_MAX - T_MIN), 0.0, 1.0) * 3.0
	var i := clampi(floori(k), 0, 2)
	return GRAD[i].lerp(GRAD[i + 1], k - float(i))


func _process(delta: float) -> void:
	# En vivo, un sensor puede pasar a "sin señal" sin que llegue ninguna lectura nueva
	if datos != null and datos.en_vivo:
		_t_vivo += delta
		if _t_vivo >= 1.0:
			_t_vivo = 0.0
			_refrescar()


func _refrescar(_x = null) -> void:
	var visibles: bool = datos.en_vivo or clima == null or clima.modo_actual == Clima.Modo.REGISTRO
	if not datos.hay_datos() and visibles:
		return
	for n in _mats:
		var c := _color(datos.valor(MAPA[n], datos.minuto)["T"] if visibles else NAN)
		for mat in _mats[n]:
			mat.albedo_color = c
