class_name SueloMojado
extends Node

# ======================================================================
#  suelo_mojado.gd - Oscurecimiento y rugosidad de la tierra con agua
# ======================================================================

var color_mojado: Color = Color(0.45, 0.40, 0.37)
var rugosidad_mojado: float = 0.35
var tiempo_mojar: float = 25.0
var secado_sol: float = 0.012
var secado_noche: float = 0.0008
var humedad: float = 0.0

class MatSuelo:
	var mat: BaseMaterial3D
	var rug0: float
	var col0: Color

var _mats: Array[MatSuelo] = []
var _ultimo_k: float = -1.0


func aplicar_a(raiz: Node) -> void:
	if raiz == null:
		push_warning("[SUELO] No recibí el nodo del terreno")
		return
	_buscar(raiz)
	if _mats.is_empty():
		push_warning("[SUELO] No encontré materiales editables en el terreno")


func _buscar(n: Node) -> void:
	if n is MeshInstance3D and n.mesh != null:
		for i in range(n.mesh.get_surface_count()):
			var m = n.get_active_material(i)
			if m is BaseMaterial3D:
				var copia: BaseMaterial3D = m.duplicate()
				n.set_surface_override_material(i, copia)
				var ms := MatSuelo.new()
				ms.mat = copia
				ms.rug0 = copia.roughness
				ms.col0 = copia.albedo_color
				_mats.append(ms)

	for h in n.get_children():
		_buscar(h)


func actualizar(delta: float, lluvia: float, nubes: float, luz_dia: float) -> void:
	if lluvia > 0.05:
		humedad += delta * lluvia / tiempo_mojar
	else:
		var sol := luz_dia * (1.0 - nubes * 0.75)
		var ritmo := lerpf(secado_noche, secado_sol, sol)
		humedad -= delta * ritmo
	humedad = clampf(humedad, 0.0, 1.0)

	var k := smoothstep(0.0, 1.0, humedad)
	if absf(k - _ultimo_k) < 0.002:
		return
	_ultimo_k = k

	for ms: MatSuelo in _mats:
		var c0 := ms.col0
		ms.mat.albedo_color = c0.lerp(Color(c0.r * color_mojado.r, c0.g * color_mojado.g, c0.b * color_mojado.b, c0.a), k)
		ms.mat.roughness = lerpf(ms.rug0, rugosidad_mojado, k)
