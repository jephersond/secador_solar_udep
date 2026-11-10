class_name Lluvia
extends Node3D

# ======================================================================
#  LLUVIA (3000 gotas que siguen a la cámara) con TECHO sobre el secador:
#  un colisionador invisible hace desaparecer las gotas que chocan con él,
#  así no llueve adentro del secador.
#
#  Propiedades que asigna principal.gd:
#    clima  (Clima)     de donde lee clima.lluvia (0 a 1)
#    camara (Camera3D)  la cámara a la que siguen las gotas
#
#  El techo es un VOLUMEN (no una lámina): va desde el suelo hasta un poco
#  por encima de la cubierta. Así una gota nunca puede "saltárselo" entre
#  dos cuadros, aunque la computadora vaya lenta.
#
#  AJUSTE (pon depurar = true para ver el volumen en rojo):
#    techo_xz:     centro en el plano (x, z). (0, 0) si el secador está en el origen
#    techo_ancho:  medida en X
#    techo_largo:  medida en Z
#    techo_giro:   giro en grados si el secador está al revés (prueba 90)
#    techo_alto:   altura de la parte más alta de la cubierta
#    techo_margen: cuánto sube el volumen por encima de la cubierta
# ======================================================================

var clima: Clima
var camara: Camera3D

var techo_xz: Vector2 = Vector2(0.0, 0.0)
var techo_ancho: float = 6.8
var techo_largo: float = 9.0
var techo_giro: float = 0.0
var techo_alto: float = 3.0
var techo_margen: float = 1.5
var depurar: bool = false

var altura_emision: float = 14.0
var _gotas: GPUParticles3D
var _techo: GPUParticlesCollisionBox3D

func _ready() -> void:
	_gotas = GPUParticles3D.new()
	_gotas.name = "Gotas"
	_gotas.amount = 3000
	_gotas.lifetime = 0.9
	_gotas.preprocess = 0.9
	_gotas.local_coords = false
	_gotas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gotas.visibility_aabb = AABB(Vector3(-30, -25, -30), Vector3(60, 40, 60))

	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(25.0, 0.5, 25.0)
	pm.direction = Vector3(0.05, -1.0, 0.0)
	pm.spread = 2.0
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 24.0
	pm.gravity = Vector3(0.0, -10.0, 0.0)
	# las gotas desaparecen al tocar el colisionador del techo
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_gotas.process_material = pm

	var malla = BoxMesh.new()
	malla.size = Vector3(0.02, 0.5, 0.02)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.78, 0.85, 0.95, 0.5)
	malla.material = mat
	_gotas.draw_pass_1 = malla
	_gotas.emitting = false
	add_child(_gotas)

	var alto_total: float = techo_alto + techo_margen
	var tam := Vector3(techo_ancho, alto_total, techo_largo)
	var pos := Vector3(techo_xz.x, alto_total / 2.0, techo_xz.y)

	_techo = GPUParticlesCollisionBox3D.new()
	_techo.name = "TechoSecador"
	_techo.size = tam
	_techo.position = pos
	_techo.rotation_degrees.y = techo_giro
	add_child(_techo)

	if depurar:
		var vista = MeshInstance3D.new()
		var caja = BoxMesh.new()
		caja.size = tam
		var mr = StandardMaterial3D.new()
		mr.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mr.albedo_color = Color(1.0, 0.1, 0.1, 0.35)
		mr.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		caja.material = mr
		vista.mesh = caja
		vista.position = pos
		vista.rotation_degrees.y = techo_giro
		add_child(vista)

func _process(_delta: float) -> void:
	if clima == null or _gotas == null:
		return

	var l: float = clampf(clima.lluvia, 0.0, 1.0)
	var es_clima_lluvia: bool = (clima.clima_nombre == "lluvia")

	# Solo emite si realmente estamos en clima de "lluvia" Y supera el 10%
	if es_clima_lluvia and l >= 0.10:
		_gotas.amount_ratio = l
		_gotas.emitting = true
	else:
		_gotas.amount_ratio = 0.0
		_gotas.emitting = false

	if camara:
		_gotas.global_position = camara.global_position + Vector3(0.0, altura_emision, 0.0)
