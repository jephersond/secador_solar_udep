class_name Vidrio
extends Node

# ======================================================================
#  vidrio.gd - Techo de policarbonato con transparencia Fresnel
# ======================================================================

var secador: Node3D
var piezas_vidrio: Array[String] = ["cubierta_policarbonato"]
var piezas_sin_sombra: Array[String] = []

var material: ShaderMaterial
var _vidrios: Array[MeshInstance3D] = []

const CODIGO := """
shader_type spatial;
render_mode blend_mix, cull_disabled;

uniform vec4 tinte : source_color = vec4(0.72, 0.94, 0.96, 1.0);
uniform float alfa_centro : hint_range(0.0, 1.0) = 0.08;
uniform float alfa_borde : hint_range(0.0, 1.0) = 0.55;
uniform float potencia : hint_range(0.5, 8.0) = 3.0;
uniform float brillo_borde : hint_range(0.0, 3.0) = 0.8;
uniform float dist_cerca = 2.0;
uniform float dist_lejos = 8.0;
uniform float alfa_cerca : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	float f = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), potencia);
	float lejania = smoothstep(dist_cerca, dist_lejos, length(VERTEX));
	float velo = mix(alfa_cerca, 1.0, lejania);
	ALBEDO = tinte.rgb;
	METALLIC = 0.0;
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
	EMISSION = tinte.rgb * f * brillo_borde;
	ALPHA = mix(alfa_centro, alfa_borde, f) * velo;
}
"""


func _ready() -> void:
	if secador == null:
		push_error("[VIDRIO] Falta asignar 'secador' antes de add_child")
		return

	var sh := Shader.new()
	sh.code = CODIGO
	material = ShaderMaterial.new()
	material.shader = sh

	for nombre: String in piezas_vidrio:
		_aplicar(nombre, true)
	for nombre: String in piezas_sin_sombra:
		_aplicar(nombre, false)


func _aplicar(nombre: String, con_material: bool) -> void:
	var pieza := secador.get_node_or_null(nombre)
	if pieza == null:
		push_warning("[VIDRIO] No encuentro '%s' dentro del secador" % nombre)
		return

	for nodo: Node in _obtener_mallas(pieza):
		var mi := nodo as MeshInstance3D
		if mi:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if con_material:
				mi.material_override = material
				_vidrios.append(mi)


func _obtener_mallas(raiz: Node) -> Array[MeshInstance3D]:
	var resultado: Array[MeshInstance3D] = []
	var cola: Array[Node] = [raiz]
	while not cola.is_empty():
		var actual: Node = cola.pop_back()
		if actual is MeshInstance3D:
			resultado.append(actual)
		cola.append_array(actual.get_children())
	return resultado


# Muestra u oculta el vidrio (para el botón 'techo' del riel)
func mostrar(v: bool) -> void:
	for mi in _vidrios:
		mi.visible = v


func ajustar(parametro: String, valor: Variant) -> void:
	if material != null:
		material.set_shader_parameter(parametro, valor)
