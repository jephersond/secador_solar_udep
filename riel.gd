class_name Riel
extends PanelContainer

# ======================================================================
#  riel.gd - Riel vertical de iconos vectoriales sobre cristal
# ======================================================================

signal pulsado(id: String)

const ANCHO: float = 54.0
const RADIO: float = 24.0

var vidrio: Cristal

var _vb: VBoxContainer
var _botones: Dictionary = {}
var _arriba: VBoxContainer
var _abajo: VBoxContainer


static func crear(padre: Control, items: Array) -> Riel:
	var r := Riel.new()
	padre.add_child(r)
	for d: Dictionary in items:
		var id: String = str(d.get("id", ""))
		var icono: String = str(d.get("icono", ""))
		var tip: String = str(d.get("tip", ""))
		var arriba: bool = bool(d.get("arriba", false))
		r._agregar(id, icono, tip, arriba)
		
	r.vidrio = Cristal.detras_de(r, RADIO, 8.0)
	r.vidrio.ligero = true
	r.vidrio.borde_alfa = 0.9
	r.vidrio.aplicar()
	return r


func _init() -> void:
	var st := Tema.caja(Tema.TRANSP, Tema.TRANSP, 0, 8.0)
	st.content_margin_top = 16.0
	st.content_margin_bottom = 10.0
	add_theme_stylebox_override("panel", st)

	_vb = VBoxContainer.new()
	_vb.add_theme_constant_override("separation", 4)
	add_child(_vb)

	_arriba = VBoxContainer.new()
	_arriba.add_theme_constant_override("separation", 4)
	_vb.add_child(_arriba)

	var relleno := Control.new()
	relleno.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vb.add_child(relleno)

	_abajo = VBoxContainer.new()
	_abajo.add_theme_constant_override("separation", 4)
	_vb.add_child(_abajo)


func _agregar(id: String, icono: String, tip: String, arriba: bool = false) -> void:
	var b := IconoRiel.new()
	b.tipo = icono
	b.tooltip_text = tip
	b.pressed.connect(func(): pulsado.emit(id))
	(_arriba if arriba else _abajo).add_child(b)
	_botones[id] = b


func a_izquierda_completo() -> void:
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = ANCHO
	offset_top = 0.0
	offset_bottom = 0.0
	grow_vertical = Control.GROW_DIRECTION_BOTH
	if vidrio != null:
		vidrio.radios = Vector4(8.0, 8.0, 8.0, 8.0)
		vidrio.aplicar()


func a_derecha(margen: float = 16.0, sup: float = 96.0) -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_right = -margen
	offset_left = -margen - ANCHO
	offset_top = sup
	offset_bottom = sup
	grow_vertical = Control.GROW_DIRECTION_END
	grow_horizontal = Control.GROW_DIRECTION_BEGIN


func marcar(id: String, on: bool) -> void:
	if _botones.has(id):
		var b: IconoRiel = _botones[id]
		b.activo = on
		b.queue_redraw()


func set_deshabilitado(id: String, deshabilitar: bool) -> void:
	if _botones.has(id):
		_botones[id].disabled = deshabilitar
		_botones[id].mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if deshabilitar else Control.CURSOR_POINTING_HAND
		_botones[id].queue_redraw()


# ======================================================================
#  IconoRiel: Botón con dibujo vectorial de trazos precisos
# ======================================================================
class IconoRiel extends Button:
	var tipo: String = ""
	var activo: bool = false
	var _sb_act: StyleBoxFlat = Tema.caja(Tema.ACENTO_FONDO, Tema.TRANSP, 0, 0.0, 17)
	var _sb_hov: StyleBoxFlat = Tema.caja(Color(Tema.VELO, 0.08), Tema.TRANSP, 0, 0.0, 17)

	func _init() -> void:
		custom_minimum_size = Vector2(38, 38)
		focus_mode = Control.FOCUS_NONE
		flat = true
		for e: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(e, StyleBoxEmpty.new())

	func _q(x: float, y: float) -> Vector2:
		return Vector2(8.0 + x * 0.75, 8.0 + y * 0.75)

	func _draw() -> void:
		var col: Color = Tema.GRIS
		if disabled:
			col = Color(Tema.GRIS.r, Tema.GRIS.g, Tema.GRIS.b, 0.3)
		elif activo:
			draw_style_box(_sb_act, Rect2(Vector2.ZERO, size))
			col = Tema.ACENTO
		elif is_hovered():
			draw_style_box(_sb_hov, Rect2(Vector2.ZERO, size))
			col = Tema.TINTA
			
		var w: float = 1.5
		match tipo:
			"graficas":
				draw_polyline(PackedVector2Array([_q(3, 20), _q(21, 20)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(5, 15), _q(9, 10), _q(13, 13), _q(19, 5)]), col, w, true)
			"control":
				for y: float in [6.0, 12.0, 18.0]:
					draw_line(_q(3, y), _q(21, y), col, w, true)
				draw_circle(_q(8, 6), 2.0, col)
				draw_circle(_q(16, 12), 2.0, col)
				draw_circle(_q(10, 18), 2.0, col)
			"diagnostico":
				draw_polyline(PackedVector2Array([
					_q(3, 12), _q(7, 12), _q(9, 6), _q(13, 18), _q(15, 12), _q(21, 12)]), col, w, true)
			"tabla":
				draw_polyline(PackedVector2Array([
					_q(3, 5), _q(21, 5), _q(21, 19), _q(3, 19), _q(3, 5)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(3, 10), _q(21, 10)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(9, 5), _q(9, 19)]), col, w, true)
			"sitio":
				draw_arc(_q(12, 12), 4.0 * 0.75, 0.0, TAU, 24, col, w, true)
				draw_polyline(PackedVector2Array([_q(12, 2), _q(12, 5)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(12, 19), _q(12, 22)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(2, 12), _q(5, 12)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(19, 12), _q(22, 12)]), col, w, true)
			"extractores":
				draw_arc(_q(12, 12), 9.0 * 0.75, 0.0, TAU, 28, col, w, true)
				for i: int in 4:
					var a: float = i * TAU / 4.0 + 0.5
					draw_line(_q(12, 12), _q(12.0 + cos(a) * 7.0, 12.0 + sin(a) * 7.0), col, w, true)
			"rotulos":
				# Etiqueta / Tag de rótulos 3D
				draw_polyline(PackedVector2Array([
					_q(4, 9), _q(4, 15), _q(9, 20), _q(19, 20), _q(19, 4), _q(9, 4), _q(4, 9)
				]), col, w, true)
				draw_circle(_q(14, 9), 1.5, col)
				draw_line(_q(9, 14), _q(15, 14), col, w, true)
			"cotas":
				draw_polyline(PackedVector2Array([_q(3, 12), _q(21, 12)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(3, 7), _q(3, 17)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(21, 7), _q(21, 17)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(7, 9), _q(3, 12), _q(7, 15)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(17, 9), _q(21, 12), _q(17, 15)]), col, w, true)
			"puertas":
				draw_polyline(PackedVector2Array([
					_q(6, 3), _q(18, 3), _q(18, 21), _q(6, 21), _q(6, 3)]), col, w, true)
				draw_circle(_q(15, 12), 1.2, col)
			"techo":
				draw_arc(_q(12, 19), 9.0 * 0.75, PI, TAU, 20, col, w, true)
				draw_polyline(PackedVector2Array([_q(3, 19), _q(21, 19)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(12, 10), _q(12, 19)]), col, w, true)
			"despiece":
				draw_polyline(PackedVector2Array([_q(5, 3), _q(19, 3), _q(19, 8), _q(5, 8), _q(5, 3)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(5, 11), _q(19, 11), _q(19, 16), _q(5, 16), _q(5, 11)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(5, 19), _q(19, 19)]), col, w, true)
			"despiece_bandeja":
				draw_polyline(PackedVector2Array([_q(4, 4), _q(20, 4)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(6, 9), _q(18, 9)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(6, 14), _q(18, 14)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(7, 14), _q(7, 21)]), col, w, true)
				draw_polyline(PackedVector2Array([_q(17, 14), _q(17, 21)]), col, w, true)
			_:
				draw_circle(size * 0.5, 4.0, col)
