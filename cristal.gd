class_name Cristal
extends ColorRect

# ======================================================================
#  cristal.gd - fondo de vidrio (desenfoque + crema translucido + niebla)
#  Se coloca DETRAS de un panel y copia su posicion y tamano, asi el
#  contenido del panel no se ve afectado por el shader.
#
#  USO:
#    var c := Cristal.detras_de(panel, 26.0, 30.0)   # radio, niebla (px)
#    c.oscuridad = 0.70
#    c.aplicar()
#
#  Dejar el margen interior del panel >= ancho de niebla, para que el
#  contenido quede sobre la zona ya opaca.
#  Si no encuentra res://cristal.gdshader usa un fondo plano.
#  Depuracion en consola: prefijo [CRISTAL]
# ======================================================================

const RUTA_SHADER := "res://cristal.gdshader"

var objetivo: Control
var radio: float = 24.0
var niebla: float = 28.0
var desenfoque: float = 6.0
var oscuridad: float = 0.70
var opacidad: float = 1.0
var borde_alfa: float = 0.40      # opacidad pegada al borde
var linea: float = 1.5            # grosor del contorno exterior (px)
var radios := Vector4(-1.0, -1.0, -1.0, -1.0)   # (arr-izq, arr-der, abj-der, abj-izq); -1 = usa 'radio'
var ligero: bool = false                          # true = vidrio barato para paneles grandes

var tinte := Color(0.03, 0.03, 0.04)          # negro (de día)
var linea_color := Color(1, 1, 1, 0.20)       # borde tenue
var tinte_dia := Color(0.03, 0.03, 0.04)
var tinte_noche := Color(0.01, 0.01, 0.02)
var oscuridad_noche: float = 0.85
var _osc_dia: float = -1.0

var _mat: ShaderMaterial


static func detras_de(obj: Control, p_radio: float = 24.0, p_niebla: float = 28.0) -> Cristal:
	var c := Cristal.new()
	c.radio = p_radio
	c.niebla = p_niebla
	var padre := obj.get_parent()
	padre.add_child(c)
	padre.move_child(c, obj.get_index())    # justo antes = dibujado detras
	c.seguir(obj)
	return c


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_actualizar_tam)


func _ready() -> void:
	if ResourceLoader.exists(RUTA_SHADER):
		_mat = ShaderMaterial.new()
		_mat.shader = load(RUTA_SHADER)
		material = _mat
		aplicar()
	else:
		color = Color(0.03, 0.03, 0.04, 0.85)
		print("[CRISTAL] no encuentro ", RUTA_SHADER, ": fondo claro sin desenfoque")


func seguir(obj: Control) -> void:
	objetivo = obj
	obj.item_rect_changed.connect(_sincronizar)
	obj.visibility_changed.connect(_sincronizar)
	_sincronizar()
	# el primer calculo de layout llega un frame despues
	_sincronizar.call_deferred()


func aplicar() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("radio", radio)
	_mat.set_shader_parameter("niebla", niebla)
	_mat.set_shader_parameter("desenfoque", desenfoque)
	_mat.set_shader_parameter("oscuridad", oscuridad)
	_mat.set_shader_parameter("opacidad", opacidad)
	_mat.set_shader_parameter("borde_alfa", borde_alfa)
	_mat.set_shader_parameter("linea", linea)
	_mat.set_shader_parameter("radios", radios)
	_mat.set_shader_parameter("ligero", ligero)
	_mat.set_shader_parameter("tinte", tinte)
	_mat.set_shader_parameter("linea_color", linea_color)
	_actualizar_tam()


func noche(f: float) -> void:
	f = clampf(f, 0.0, 1.0)
	if _osc_dia < 0.0:
		_osc_dia = oscuridad
	tinte = tinte_dia.lerp(tinte_noche, f)
	oscuridad = lerpf(_osc_dia, oscuridad_noche, f)
	if _mat != null:
		_mat.set_shader_parameter("tinte", tinte)
		_mat.set_shader_parameter("oscuridad", oscuridad)


func _actualizar_tam() -> void:
	if _mat != null:
		_mat.set_shader_parameter("tam", size)


func _sincronizar() -> void:
	if objetivo == null or not is_instance_valid(objetivo):
		return
	position = objetivo.position
	size = objetivo.size
	visible = objetivo.is_visible_in_tree()
