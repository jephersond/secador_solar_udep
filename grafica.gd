class_name Grafica
extends Control

# ======================================================================
#  grafica.gd - Gráfica 2D de series temporales de alto rendimiento
#  Separa el dibujado estático de curvas del cursor móvil a 60 FPS.
# ======================================================================

signal tiempo_elegido(minuto: float)

const MI: float = 46.0     # Margen izquierdo (etiquetas Y)
const MD: float = 8.0      # Margen derecho
const MS: float = 36.0     # Margen superior (título y leyenda)
const MB: float = 20.0     # Margen inferior (eje X)

var datos: DatosSensores
var titulo: String = ""
var unidad: String = ""
var ids: Array = []
var fuente: Callable = Callable()

var _arrastrando: bool = false
var _fondo: StyleBoxFlat
var _cursor: CursorOverlay


func _init() -> void:
	custom_minimum_size = Vector2(300, 170)
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	_fondo = Tema.caja(Tema.TARJETA_CLARA, Tema.BORDE, 1, 0.0, 12)
	
	# Capa ligera independiente para el cursor de reproducción
	_cursor = CursorOverlay.new(self)
	add_child(_cursor)
	resized.connect(_al_redimensionar)


func _al_redimensionar() -> void:
	queue_redraw()
	if _cursor != null:
		_cursor.queue_redraw()


func configurar(d: DatosSensores, tit: String, uni: String, lista: Array, fn: Callable) -> void:
	datos = d
	titulo = tit
	unidad = uni
	ids = lista.duplicate()
	fuente = fn

	# Las curvas solo se redibujan cuando cambian los datos o la corrección
	# (en vivo: una vez por lectura nueva, no por cuadro)
	for senal: Signal in [datos.datos_cargados, datos.correccion_cambiada,
			datos.lectura_agregada, datos.modo_vivo_cambiado]:
		if not senal.is_connected(_refrescar_curvas):
			senal.connect(_refrescar_curvas)

	# El cursor solo redibuja su propia línea a 60 FPS sin tocar las curvas
	if not datos.minuto_cambiado.is_connected(_refrescar_cursor):
		datos.minuto_cambiado.connect(_refrescar_cursor)

	queue_redraw()
	_cursor.queue_redraw()


func set_ids(lista: Array) -> void:
	ids = lista.duplicate()
	queue_redraw()
	_cursor.queue_redraw()


func _refrescar_curvas(_x: Variant = null) -> void:
	queue_redraw()
	_cursor.queue_redraw()


func _refrescar_cursor(_m: float) -> void:
	_cursor.queue_redraw()


func _paso_x(dur: float) -> float:
	if dur <= 5.0: return 1.0
	if dur <= 15.0: return 2.0
	if dur <= 30.0: return 5.0
	if dur <= 60.0: return 10.0
	if dur <= 180.0: return 30.0
	return 60.0


# Dibujado estático (solo ocurre al cambiar datos, ids o tamaño de ventana)
func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var f: Font = get_theme_default_font()
	var tinta: Color = Tema.TINTA
	var gris: Color = Tema.GRIS

	draw_style_box(_fondo, Rect2(Vector2.ZERO, size))
	draw_string(f, Vector2(MI, 14), "%s (%s)" % [titulo, unidad], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tinta)

	if datos == null or not datos.hay_datos() or not fuente.is_valid():
		draw_string(f, Vector2(MI, h * 0.5), "Sin datos: usa «Subir datos»", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, gris)
		return

	if ids.is_empty():
		draw_string(f, Vector2(MI, h * 0.5), "Elige al menos una sonda", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, gris)
		return

	# Cálculo de rangos
	var ys: Array[PackedFloat32Array] = []
	var lo: float = INF
	var hi: float = -INF

	for id: int in ids:
		var s: PackedFloat32Array = fuente.call(id)
		ys.append(s)
		for v: float in s:
			if not is_nan(v):
				lo = minf(lo, v)
				hi = maxf(hi, v)

	if lo == INF:
		draw_string(f, Vector2(MI, h * 0.5), "Todas las lecturas son NaN", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, gris)
		return

	if hi - lo < 0.0001:
		lo -= 1.0
		hi += 1.0
	var pad: float = (hi - lo) * 0.08
	lo -= pad
	hi += pad

	var dur: float = maxf(datos.duracion, 0.0001)
	var px: float = w - MI - MD
	var py: float = h - MS - MB

	# Cuadrícula horizontal Y
	for k: int in range(5):
		var v: float = lo + (hi - lo) * float(k) / 4.0
		var y: float = MS + py * (1.0 - (v - lo) / (hi - lo))
		draw_line(Vector2(MI, y), Vector2(w - MD, y), Color(Tema.VELO, 0.12), 1.0)
		draw_string(f, Vector2(2, y + 4), "%.1f" % v, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, gris)

	# Cuadrícula vertical X
	draw_string(f, Vector2(w - MD - 24, 14), "min", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, gris)
	var paso: float = _paso_x(dur)
	var m: float = 0.0
	while m <= dur + 0.001:
		var x: float = MI + px * m / dur
		draw_line(Vector2(x, MS), Vector2(x, h - MB), Color(Tema.VELO, 0.06), 1.0)
		draw_string(f, Vector2(x - 6, h - 5), "%d" % int(round(m)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, gris)
		m += paso

	# Dibujo de curvas
	for j: int in ids.size():
		var col: Color = Tema.claro(datos.color_de(ids[j]))
		var s: PackedFloat32Array = ys[j]
		var n: int = mini(s.size(), datos.t_min.size())
		var seg := PackedVector2Array()
		for i: int in n:
			var v: float = s[i]
			if is_nan(v):
				if seg.size() > 1:
					draw_polyline(seg, col, 1.6, true)
				seg.clear()
				continue
			seg.append(Vector2(MI + px * datos.t_min[i] / dur, MS + py * (1.0 - (v - lo) / (hi - lo))))
		if seg.size() > 1:
			draw_polyline(seg, col, 1.6, true)

	# Leyenda
	var lx: float = MI
	for id: int in ids:
		draw_line(Vector2(lx, 25), Vector2(lx + 14, 25), Tema.claro(datos.color_de(id)), 3.0)
		draw_string(f, Vector2(lx + 17, 29), "ID%d" % id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, gris)
		lx += minf(58.0, (w - MI - MD) / float(ids.size()))


func _gui_input(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		_arrastrando = mb.pressed
		if mb.pressed:
			_elegir(mb.position.x)
		accept_event()
		return

	var mm := e as InputEventMouseMotion
	if mm and _arrastrando:
		_elegir(mm.position.x)
		accept_event()


func _elegir(px_x: float) -> void:
	if datos == null or not datos.hay_datos():
		return
	var dur: float = maxf(datos.duracion, 0.0001)
	var px: float = size.x - MI - MD
	var m: float = clampf((px_x - MI) / px * dur, 0.0, dur)
	datos.set_minuto(m)
	tiempo_elegido.emit(m)


# ======================================================================
#  CursorOverlay: Dibuja ÚNICAMENTE la aguja roja vertical a 60 FPS
# ======================================================================
class CursorOverlay extends Control:
	var g: Grafica

	func _init(graf: Grafica) -> void:
		g = graf
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if g.datos == null or not g.datos.hay_datos():
			return
		var dur: float = maxf(g.datos.duracion, 0.0001)
		var px: float = size.x - Grafica.MI - Grafica.MD
		var cx: float = Grafica.MI + px * g.datos.minuto / dur
		draw_line(Vector2(cx, Grafica.MS), Vector2(cx, size.y - Grafica.MB), Tema.ACENTO, 1.5)
