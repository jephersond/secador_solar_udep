class_name PanelConexion
extends PanelContainer

# ======================================================================
#  panel_conexion.gd - Panel desplegable de conexiones + pildora de estado
#  Lo construye y ubica interfaz.gd. Habla con EnlaceDatos (enlace_datos.gd).
# ======================================================================

const ANCHO: float = 400.0

const TIPOS: Dictionary = {
	"archivo": "ARCHIVO", "serial": "SERIAL", "wifi": "WIFI", "ws": "WIFI", "internet": "RED", "sd": "SD",
}

# Campos editables por tipo de fuente. Agregar un tipo nuevo = agregar una entrada aqui.
const PARAMS: Dictionary = {
	"archivo": [{"clave": "velocidad", "texto": "Velocidad", "opciones": [1, 10, 50],
			"defecto": 10, "fmt": "x%d"}],
	"serial": [{"clave": "baudios", "texto": "Baudios", "opciones": [9600, 19200, 57600, 115200],
			"defecto": 115200, "fmt": "%d"}],
	# "dinamico": las opciones las manda el puente en la propia fuente (f["opciones"][clave])
	"sd": [{"clave": "archivo", "texto": "Archivo", "dinamico": true, "fmt": "%s"}],
}

signal abrir_archivo_pedido        # el usuario quiere elegir un registro del disco
signal abrir_carpeta_pedida        # abrir la carpeta de registros en el explorador
signal elegir_carpeta_pedida       # cambiar la carpeta de registros

var enlace: EnlaceDatos

var _ignorar: Array[Control] = []     # controles que abren/cierran el panel (no cuentan como "afuera")
var _sel: String = ""                 # fuente seleccionada (muestra sus ajustes)
var _params: Dictionary = {}          # id_fuente -> {clave: valor}
var _x_ref: float = 0.0
var _derecha: bool = false
var _y_tope: float = 0.0
var _cuerpo: VBoxContainer
var _lbl_estado: Label
var _firma: String = ""


func _init() -> void:
	visible = false
	z_index = 150                          # Se dibuja por encima de todos los rótulos 3D
	custom_minimum_size = Vector2(ANCHO, 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", Tema.caja(Color(0.10, 0.10, 0.11, 0.95), Tema.BORDE, 1, 14.0, 14))
	_cuerpo = VBoxContainer.new()
	_cuerpo.add_theme_constant_override("separation", 8)
	add_child(_cuerpo)


func configurar(e: EnlaceDatos, ignorar: Array[Control]) -> void:
	enlace = e
	_ignorar = ignorar
	e.estado_cambiado.connect(func(_i: Dictionary): _al_cambio())
	e.fuentes_actualizadas.connect(func(_l: Array): _al_cambio())
	_firma = ""
	_al_cambio()


# ----------------------------------------------------------------------
#  Abrir / cerrar
# ----------------------------------------------------------------------
func abrir(x_ref: float, derecha: bool, y_tope: float) -> void:
	_x_ref = x_ref
	_derecha = derecha
	_y_tope = y_tope
	visible = true
	_firma = ""
	_al_cambio()
	if enlace != null and enlace.estado != "sin_puente":
		enlace.buscar()


func cerrar() -> void:
	visible = false


func _input(ev: InputEvent) -> void:
	if not visible:
		return
	var k := ev as InputEventKey
	if k != null and k.pressed and k.keycode == KEY_ESCAPE:
		cerrar()
		get_viewport().set_input_as_handled()
		return
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if get_global_rect().has_point(mb.position):
		return
	for c: Control in _ignorar:
		if c != null and c.is_visible_in_tree() and c.get_global_rect().has_point(mb.position):
			return
	cerrar()


func _reubicar() -> void:
	if not visible:
		return
	reset_size()
	var vp: Vector2 = get_viewport_rect().size
	var x: float = (_x_ref - size.x) if _derecha else _x_ref
	x = clampf(x, 8.0, maxf(8.0, vp.x - size.x - 8.0))
	position = Vector2(x, maxf(8.0, _y_tope - size.y - 10.0))


# ----------------------------------------------------------------------
#  Contenido
# ----------------------------------------------------------------------
func _al_cambio() -> void:
	if enlace == null:
		return
	# Solo se reconstruye si cambió algo visible; el contador de lecturas
	# se actualiza aparte (si no, cada latido cerraría un desplegable abierto).
	var firma: String = str([enlace.estado, enlace.fuente, enlace.detalle, enlace.fuentes, _sel])
	if firma != _firma:
		_firma = firma
		_reconstruir()
	elif _lbl_estado != null:
		_lbl_estado.text = _texto_estado()


func _texto_estado() -> String:
	match enlace.estado:
		"online":
			return "Online · %s · %d lecturas" % [enlace.nombre_de(enlace.fuente), enlace.lecturas]
		"buscando":
			return "Conectando a %s…" % enlace.nombre_de(enlace.fuente)
		"error":
			return "Error: %s" % enlace.detalle
		"desconectado":
			return "Sin conexión en vivo. Abre un registro o conecta el ESP32."
	return "El puente de datos no responde (solo hace falta para el modo en vivo). Los registros se abren igual."


func _color_estado() -> Color:
	match enlace.estado:
		"online": return Tema.OK
		"buscando": return Tema.AVISO
		"error": return Tema.MAL
	return Tema.GRIS


func _reconstruir() -> void:
	for h in _cuerpo.get_children():
		_cuerpo.remove_child(h)
		h.queue_free()

	# --- encabezado ---
	var cab := HBoxContainer.new()
	var titulo := Label.new()
	titulo.text = "Conexión"
	titulo.add_theme_font_size_override("font_size", 16)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(titulo)
	var b_buscar := Button.new()
	b_buscar.text = "↻ Buscar de nuevo"
	b_buscar.flat = true
	b_buscar.focus_mode = Control.FOCUS_NONE
	b_buscar.pressed.connect(func(): enlace.buscar())
	cab.add_child(b_buscar)
	_cuerpo.add_child(cab)

	# --- linea de estado ---
	_lbl_estado = Label.new()
	_lbl_estado.text = _texto_estado()
	_lbl_estado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_estado.custom_minimum_size = Vector2(ANCHO - 28.0, 0.0)
	_lbl_estado.add_theme_color_override("font_color", _color_estado())
	_cuerpo.add_child(_lbl_estado)

	# --- fuentes que se pueden seleccionar (las de la lista del puente, sin "sim" ni internet) ---
	var ids: Array[String] = []
	for f: Dictionary in enlace.fuentes:
		var tipo_f: String = str(f.get("tipo", ""))
		if tipo_f != "archivo" and tipo_f != "internet":
			ids.append(str(f.get("id", "")))
	if not ids.has(_sel):
		_sel = enlace.fuente if ids.has(enlace.fuente) else ""
		if _sel == "":
			for f: Dictionary in enlace.fuentes:
				if str(f.get("tipo", "")) == "serial":
					_sel = str(f.get("id", ""))
					break

	var activa_id: String = ""
	if enlace.estado == "online" or enlace.estado == "buscando":
		activa_id = enlace.fuente

	# --- 1) REGISTROS: no necesitan el puente ---
	_cuerpo.add_child(_seccion("REGISTROS (ARCHIVO)"))
	_cuerpo.add_child(_fila_accion("Registro de prueba (60 min)", "Registro_60_min.txt", "Cargar", _cargar_prueba))
	_cuerpo.add_child(_fila_accion("Abrir otro registro…", "CSV o TXT · también puedes arrastrarlo a la ventana",
			"Elegir…", _pedir_archivo))
	for f: Dictionary in enlace.fuentes:
		if str(f.get("tipo", "")) == "sd":
			_cuerpo.add_child(_fila(f, activa_id))

	# --- 2) EN VIVO: ESP32 por USB (y wifi cuando exista) ---
	_cuerpo.add_child(_seccion("EN VIVO"))
	var hay_vivo: bool = false
	for f: Dictionary in enlace.fuentes:
		var tipo_v: String = str(f.get("tipo", ""))
		if tipo_v == "archivo" or tipo_v == "sd" or tipo_v == "internet":
			continue
		hay_vivo = true
		_cuerpo.add_child(_fila(f, activa_id))
	if not hay_vivo:
		var vacio := Label.new()
		vacio.text = "No hay equipos. Conecta el ESP32 por USB y pulsa «Buscar de nuevo»."
		vacio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vacio.custom_minimum_size = Vector2(ANCHO - 28.0, 0.0)
		vacio.add_theme_font_size_override("font_size", 12)
		vacio.add_theme_color_override("font_color", Tema.GRIS)
		_cuerpo.add_child(vacio)

	# --- ajustes de la fuente seleccionada ---
	for f: Dictionary in enlace.fuentes:
		if str(f.get("id", "")) == _sel:
			_agregar_ajustes(f)
			break

	# --- pie: carpeta de registros e internet (solo informa) ---
	var pie := HBoxContainer.new()
	pie.add_child(_boton_plano("Abrir carpeta de registros", _pedir_abrir_carpeta))
	pie.add_child(_boton_plano("Cambiar carpeta…", _pedir_elegir_carpeta))
	_cuerpo.add_child(pie)

	for f: Dictionary in enlace.fuentes:
		if str(f.get("tipo", "")) == "internet":
			var ok: bool = bool(f.get("ok", false))
			var li := Label.new()
			li.text = "Internet: %s · solo se usa para el clima" % ("disponible" if ok else "sin red")
			li.add_theme_font_size_override("font_size", 11)
			li.add_theme_color_override("font_color", Tema.OK if ok else Tema.MAL)
			_cuerpo.add_child(li)
			break

	call_deferred("_reubicar")


func _seccion(texto: String) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Tema.GRIS)
	return l


func _boton_plano(texto: String, accion: Callable) -> Button:
	var b := Button.new()
	b.text = texto
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(accion)
	return b


# Fila con una sola accion (cargar / elegir archivo), sin estado de conexion
func _fila_accion(titulo: String, detalle_txt: String, texto_btn: String, accion: Callable) -> Control:
	var pc := PanelContainer.new()
	var sb := Tema.caja(Color(1, 1, 1, 0.05), Tema.TRANSP, 0, 10.0)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	pc.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	pc.add_child(hb)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nombre := Label.new()
	nombre.text = titulo
	vb.add_child(nombre)
	var detalle := Label.new()
	detalle.text = detalle_txt
	detalle.add_theme_font_size_override("font_size", 11)
	detalle.add_theme_color_override("font_color", Tema.GRIS)
	detalle.clip_text = true
	vb.add_child(detalle)
	hb.add_child(vb)

	var btn := Button.new()
	btn.text = texto_btn
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(96.0, 0.0)
	btn.pressed.connect(accion)
	hb.add_child(btn)
	return pc


func _cargar_prueba() -> void:
	enlace.cargar_csv_directo()
	cerrar()


func _pedir_archivo() -> void:
	cerrar()
	abrir_archivo_pedido.emit()


func _pedir_abrir_carpeta() -> void:
	abrir_carpeta_pedida.emit()


func _pedir_elegir_carpeta() -> void:
	cerrar()
	elegir_carpeta_pedida.emit()


func _fila(f: Dictionary, activa_id: String) -> Control:
	var id: String = str(f.get("id", ""))
	var activa: bool = id == activa_id
	var elegida: bool = id == _sel

	var pc := PanelContainer.new()
	var sb := Tema.caja(
		Tema.ACENTO_FONDO if elegida else Color(1, 1, 1, 0.05),
		Tema.ACENTO if elegida else Tema.TRANSP,
		1 if elegida else 0, 10.0)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	pc.add_theme_stylebox_override("panel", sb)
	pc.gui_input.connect(_clic_fila.bind(id))

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	pc.add_child(hb)

	var punto := Punto.new()
	if bool(f.get("info", false)):
		punto.color = Tema.OK if bool(f.get("ok", false)) else Tema.MAL
	elif activa:
		punto.color = Tema.OK if enlace.estado == "online" else Tema.AVISO
	else:
		punto.color = Tema.GRIS
	hb.add_child(punto)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_PASS
	var nombre := Label.new()
	nombre.text = str(f.get("nombre", id))
	nombre.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(nombre)
	var detalle := Label.new()
	detalle.text = str(f.get("detalle", ""))
	detalle.add_theme_font_size_override("font_size", 11)
	detalle.add_theme_color_override("font_color", Tema.GRIS)
	detalle.clip_text = true
	detalle.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(detalle)
	hb.add_child(vb)

	var tag := Label.new()
	tag.text = str(TIPOS.get(str(f.get("tipo", "")), str(f.get("tipo", "")).to_upper()))
	tag.add_theme_font_size_override("font_size", 10)
	tag.add_theme_color_override("font_color", Tema.GRIS)
	tag.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(tag)

	if bool(f.get("info", false)):               # solo informa (internet): sin botón
		var disp := Label.new()
		disp.text = "Disponible" if bool(f.get("ok", false)) else "Sin red"
		disp.add_theme_font_size_override("font_size", 12)
		disp.add_theme_color_override("font_color", Tema.OK if bool(f.get("ok", false)) else Tema.MAL)
		disp.custom_minimum_size = Vector2(96.0, 0.0)
		disp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb.add_child(disp)
		return pc

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(96.0, 0.0)

	if activa:
		btn.text = "Desconectar"
		btn.pressed.connect(func(): enlace.desconectar())
	elif bool(f.get("soportado", false)) and str(f.get("accion", "conectar")) == "importar":
		btn.text = "Importar"
		btn.pressed.connect(func(): enlace.importar(id, _params_de(f)))
	elif bool(f.get("soportado", false)):
		btn.text = "Conectar"
		btn.pressed.connect(func(): enlace.conectar(id, _params_de(f)))
	else:
		btn.text = "Pronto"
		btn.disabled = true

	hb.add_child(btn)
	return pc


func _clic_fila(ev: InputEvent, id: String) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and id != _sel:
		_sel = id
		call_deferred("_al_cambio")


func _agregar_ajustes(f: Dictionary) -> void:
	var tipo: String = str(f.get("tipo", ""))
	if not PARAMS.has(tipo):
		return
	var id: String = str(f.get("id", ""))
	var t := Label.new()
	t.text = "Ajustes · %s" % str(f.get("nombre", id))
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", Tema.GRIS)
	_cuerpo.add_child(t)
	for p: Dictionary in PARAMS[tipo]:
		var hb := HBoxContainer.new()
		var l := Label.new()
		l.text = str(p["texto"])
		l.custom_minimum_size = Vector2(110.0, 0.0)
		hb.add_child(l)
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		var ops: Array = _opciones(f, p)
		if ops.is_empty():
			var vacio := Label.new()
			vacio.text = "(sin archivos)"
			vacio.add_theme_color_override("font_color", Tema.GRIS)
			hb.add_child(vacio)
			_cuerpo.add_child(hb)
			continue
		var actual = _params.get(id, {}).get(p["clave"], _defecto(f, p))
		for i: int in ops.size():
			ob.add_item(str(p["fmt"]) % ops[i])
			if ops[i] == actual:
				ob.select(i)
		ob.item_selected.connect(_cambia_param.bind(id, str(p["clave"]), ops))
		hb.add_child(ob)
		_cuerpo.add_child(hb)
	var nota := Label.new()
	nota.text = "Los ajustes se aplican al conectar o importar."
	nota.add_theme_font_size_override("font_size", 11)
	nota.add_theme_color_override("font_color", Tema.GRIS)
	_cuerpo.add_child(nota)


func _cambia_param(idx: int, id: String, clave: String, ops: Array) -> void:
	if not _params.has(id):
		_params[id] = {}
	_params[id][clave] = ops[idx]


func _params_de(f: Dictionary) -> Dictionary:
	var res: Dictionary = {}
	var tipo: String = str(f.get("tipo", ""))
	if PARAMS.has(tipo):
		var guardados: Dictionary = _params.get(str(f.get("id", "")), {})
		for p: Dictionary in PARAMS[tipo]:
			var clave: String = str(p["clave"])
			var v = guardados.get(clave, _defecto(f, p))
			if not _opciones(f, p).has(v):       # p. ej. el archivo ya no está en la SD
				v = _defecto(f, p)
			res[clave] = v
	return res


# Opciones de un ajuste: fijas, o las que mandó el puente en la propia fuente
func _opciones(f: Dictionary, p: Dictionary) -> Array:
	if bool(p.get("dinamico", false)):
		var o = f.get("opciones", {})
		if typeof(o) == TYPE_DICTIONARY and o.has(p["clave"]):
			return o[p["clave"]]
		return []
	return p["opciones"]


func _defecto(f: Dictionary, p: Dictionary) -> Variant:
	if bool(p.get("dinamico", false)):
		var ops: Array = _opciones(f, p)
		return ops[ops.size() - 1] if not ops.is_empty() else ""    # el más reciente
	return p["defecto"]


# ======================================================================
#  Punto de color (estado de cada fuente)
# ======================================================================
class Punto extends Control:
	var color: Color = Color(0.5, 0.5, 0.5)

	func _init() -> void:
		custom_minimum_size = Vector2(12.0, 12.0)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(size * 0.5, 5.0, color)


# ======================================================================
#  Píldora de estado (la que se ve siempre, sobre la barra de tiempo)
# ======================================================================
class Pildora extends Button:
	var color: Color = Color(0.5, 0.5, 0.5)

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		text = "Sin puente"
		for e: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var st := Tema.caja(Color(0.10, 0.10, 0.11, 0.85), Tema.BORDE, 1, 16.0)
			st.content_margin_left = 30.0
			st.content_margin_right = 14.0
			st.content_margin_top = 6.0
			st.content_margin_bottom = 6.0
			if e == "hover" or e == "hover_pressed":
				st.bg_color = Color(0.16, 0.16, 0.18, 0.92)
			add_theme_stylebox_override(e, st)

	func poner(texto: String, col: Color) -> void:
		text = texto
		color = col
		reset_size()
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(16.0, size.y * 0.5)
		draw_circle(c, 8.0, Color(color.r, color.g, color.b, 0.25))
		draw_circle(c, 4.5, color)
