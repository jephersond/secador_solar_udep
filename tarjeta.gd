class_name Tarjeta
extends PanelContainer

# ======================================================================
#  tarjeta.gd - Ventana flotante sobre cristal (cabecera + ampliar + cerrar)
# ======================================================================

signal cerrada
signal ampliada_cambiada(activa: bool)

const RADIO: float = 28.0
const NIEBLA: float = 18.0

var titulo: String = "":
	set(v):
		titulo = v
		if _lbl != null:
			_lbl.text = v

var ampliable: bool = true:
	set(v):
		ampliable = v
		if _b_amp != null:
			_b_amp.visible = v

var tecla_abrir: Key = KEY_NONE
var vidrio: Cristal
var contenido: VBoxContainer
var amplia: bool = false

var _izq: float = 80.0
var _sup: float = 80.0
var _ancho: float = 400.0
var _inf: float = 80.0
var _inf_amp: float = -1.0
var _der_amp: float = 16.0
var _sup_amp: float = 96.0

var _lbl: Label
var _b_amp: BotonTarjeta
var _b_cer: BotonTarjeta


static func crear(padre: Control, p_titulo: String) -> Tarjeta:
	var t := Tarjeta.new()
	t.titulo = p_titulo
	padre.add_child(t)
	t.vidrio = Cristal.detras_de(t, RADIO, NIEBLA)
	t.vidrio.ligero = true
	t.vidrio.borde_alfa = 0.9
	t.vidrio.aplicar()
	t._aplicar_rect()
	return t


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", Tema.caja(Tema.TRANSP, Tema.TRANSP, 0, 18.0))
	
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	var cab := HBoxContainer.new()
	col.add_child(cab)

	_lbl = Label.new()
	_lbl.text = titulo
	_lbl.add_theme_font_size_override("font_size", 15)
	_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cab.add_child(_lbl)

	_b_amp = BotonTarjeta.new()
	_b_amp.tipo = "ampliar"
	_b_amp.pressed.connect(alternar_ampliada)
	cab.add_child(_b_amp)

	_b_cer = BotonTarjeta.new()
	_b_cer.tipo = "cerrar"
	_b_cer.pressed.connect(cerrar)
	cab.add_child(_b_cer)

	contenido = VBoxContainer.new()
	contenido.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contenido.add_theme_constant_override("separation", 8)
	col.add_child(contenido)


func colocar(izq: float, sup: float, ancho: float, inf: float, sup_amp: float = 96.0, der_amp: float = 16.0, inf_amp: float = -1.0) -> void:
	_izq = izq
	_sup = sup
	_ancho = ancho
	_inf = inf
	_sup_amp = sup_amp
	_der_amp = der_amp
	_inf_amp = inf_amp
	_aplicar_rect()


func _aplicar_rect() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	anchor_right = 1.0 if amplia else 0.0
	offset_left = _izq
	offset_top = _sup_amp if amplia else _sup
	offset_bottom = -(_inf_amp if amplia and _inf_amp >= 0.0 else _inf)
	offset_right = -_der_amp if amplia else _izq + _ancho


func abrir() -> void:
	visible = true
	var p := get_parent()
	if p != null and vidrio != null:
		p.move_child(self, -1)
		p.move_child(vidrio, p.get_child_count() - 2)


func cerrar() -> void:
	if not visible:
		return
	visible = false
	cerrada.emit()


func alternar() -> void:
	if visible: cerrar()
	else: abrir()


func alternar_ampliada() -> void:
	establecer_ampliada(not amplia)


func establecer_ampliada(on: bool) -> void:
	amplia = on
	_aplicar_rect()
	_b_amp.tipo = "reducir" if on else "ampliar"
	_b_amp.queue_redraw()
	ampliada_cambiada.emit(on)


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	if k.keycode == KEY_ESCAPE and is_visible_in_tree():
		cerrar()
		get_viewport().set_input_as_handled()
	elif tecla_abrir != KEY_NONE and k.keycode == tecla_abrir:
		alternar()


# ======================================================================
#  BotonTarjeta: Botón de cerrar / ampliar / reducir
# ======================================================================
class BotonTarjeta extends Button:
	var tipo: String = ""

	func _init() -> void:
		custom_minimum_size = Vector2(34, 34)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		focus_mode = Control.FOCUS_NONE
		flat = true
		for e: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(e, StyleBoxEmpty.new())

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var hover: bool = is_hovered()
		if hover:
			draw_circle(c, 16.0, Color(Tema.VELO, 0.08))
		var col: Color = Tema.TINTA if hover else Tema.GRIS
		match tipo:
			"cerrar":
				draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), col, 2.0, true)
				draw_line(c + Vector2(-5, 5), c + Vector2(5, -5), col, 2.0, true)
			"ampliar":
				draw_polyline(PackedVector2Array([c + Vector2(-6, -6), c + Vector2(0, 0), c + Vector2(-6, 6)]), col, 2.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(1, -6), c + Vector2(7, 0), c + Vector2(1, 6)]), col, 2.0, true)
			"reducir":
				draw_polyline(PackedVector2Array([c + Vector2(6, -6), c + Vector2(0, 0), c + Vector2(6, 6)]), col, 2.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(-1, -6), c + Vector2(-7, 0), c + Vector2(-1, 6)]), col, 2.0, true)
