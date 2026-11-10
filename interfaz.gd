class_name Interfaz
extends CanvasLayer

# ======================================================================
#  interfaz.gd - Control UI, HUD de sensores, franja estilo IA y tarjetas
# ======================================================================

signal accion_secador(id: String, activa: bool)
signal vista_cambiada(nombre_vista: String)

const MARGEN: float = 8.0
const ANCHO_RIEL: float = 54.0
const ALTO_BARRA: float = 56.0
const ANCHO_BARRA: float = 780.0
const ANCHO_TARJETA: float = 520.0
const SEP_RIEL: float = 10.0

# Posiciones dinámicas de la tarjeta:
# Con clima desplegado: baja a 126px para despejar la franja exterior.
# Sin clima desplegado: sube a 66px para ubicarse justo bajo las vistas.
const TOP_TARJETA_NORMAL: float = 66.0
const TOP_TARJETA_CON_CLIMA: float = 126.0
const TOP_TARJETA_AMPLIA: float = 16.0

const VELOCIDADES: Array[float] = [1.0, 10.0, 60.0, 120.0, 300.0]
const VEL_TEXTOS: Array[String] = ["x1", "x10", "x60", "x120", "x300"]

var datos: DatosSensores

var _tema: Theme
var _raiz: Control
var _cristales: Array[Cristal] = []
var _clima: Clima
var _f_noche: float = 0.0

var _riel: Riel
var _barra_vistas: PanelContainer
var _btns_vistas: Dictionary = {}

var _activa: String = ""
var _tarjetas: Dictionary = {}
var _estados_secador: Dictionary = {}
var _clima_desplegado: bool = false

var _barra: PanelContainer
var _sitio: Sitio
var _checks: GridContainer
var _cuerpo: HBoxContainer
var _vb_graf: VBoxContainer
var _b_sondas: Button
var _rejilla: GridContainer
var _g_T: Grafica
var _g_H: Grafica
var _g_D: Grafica
var _g_V: Grafica
var _kpi: Label
var _tree_d: Tree
var _tree_t: Tree
var _it_d: Dictionary = {}
var _it_t: Dictionary = {}

var _dialogo: FileDialog
var _dlg_carpeta: FileDialog
var _menu: PopupMenu
var _toast: Label
var _id_aviso: int = 0
var _b_play: BotonIcono
var _b_reset: BotonIcono
var _b_mas: BotonIcono
var _b_con: BotonIcono                 # boton de conexion (junto a los tres puntos)
var _pild: PanelConexion.Pildora       # pildora de estado, sobre la barra
var _panel_con: PanelConexion
var enlace: EnlaceDatos
var _slider: HSlider
var _lbl_min: Label
var _lbl_reloj: Label
var _shown: Array[int] = []
var _sucio: bool = true
var _acum: float = 0.0
var _amplio: bool = false

var _graf: Array[Grafica] = []
var _btns_graf: Array[Button] = []
var _fila_graf: HBoxContainer
var _graf_sel: int = 0

var panel_clima_ref: CanvasLayer = null
var camara_3d: Camera3D = null

# Contenedor 2D para etiquetas flotantes
var _capa_rotulos: Control
var _etiquetas_hud: Dictionary = {}
var _rotulos_visibles: bool = true

const NOMBRES_SENSORES: Dictionary = {
	2: "Aire · ID2",
	6: "B1 · ID6",
	5: "B2 · ID5",
	4: "B3 · ID4",
	7: "B4 · ID7",
	8: "B5 · ID8",
	9: "B6 · ID9",
}


var _n_ids_vivo: int = -1     # cuantos sensores habia en la ultima lectura en vivo


func _ready() -> void:
	layer = 10
	if datos == null:
		push_error("[INTERFAZ] Falta asignar 'datos' antes de add_child")
		return
	_tema = Tema.crear()
	_construir()
	
	datos.datos_cargados.connect(_al_cargar)
	datos.carga_fallida.connect(_al_fallar)
	datos.minuto_cambiado.connect(_al_minuto)
	datos.reproduccion_cambiada.connect(_al_reproduccion)
	datos.correccion_cambiada.connect(_al_correccion)
	datos.lectura_agregada.connect(_al_lectura)
	datos.modo_vivo_cambiado.connect(_al_vivo)
	get_window().files_dropped.connect(_al_soltar)
	
	if datos.hay_datos():
		_al_cargar(datos.resumen())
	print("[INTERFAZ] Lista")


func _construir() -> void:
	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.theme = _tema
	add_child(_raiz)

	_capa_rotulos = Control.new()
	_capa_rotulos.set_anchors_preset(Control.PRESET_FULL_RECT)
	_capa_rotulos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_capa_rotulos)

	_dialogo = FileDialog.new()
	_dialogo.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialogo.access = FileDialog.ACCESS_FILESYSTEM
	_dialogo.filters = PackedStringArray(["*.csv, *.txt ; Registros de sensores"])
	_dialogo.title = "Subir registro de sensores"
	_dialogo.file_selected.connect(func(p: String): datos.cargar_csv(p))
	add_child(_dialogo)

	_dlg_carpeta = FileDialog.new()
	_dlg_carpeta.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dlg_carpeta.access = FileDialog.ACCESS_FILESYSTEM
	_dlg_carpeta.title = "Elegir carpeta de registros"
	_dlg_carpeta.dir_selected.connect(func(p: String):
		datos.set_carpeta_registros(p)
		_aviso("Los registros se guardarán en: " + p, false, 5.0))
	add_child(_dlg_carpeta)

	_construir_barra_vistas()
	_construir_riel_y_tarjetas()
	_construir_barra()
	_construir_menu()
	_construir_enlace_ui()
	_construir_aviso()
	_construir_rotulos_hud()


func _construir_riel_y_tarjetas() -> void:
	_riel = Riel.crear(_raiz, [
		{"id": "extractores", "icono": "extractores", "tip": "Extractores", "arriba": true},
		{"id": "rotulos", "icono": "rotulos", "tip": "Mostrar/Ocultar Rótulos de Sensores", "arriba": true},
		{"id": "cotas", "icono": "cotas", "tip": "Cotas", "arriba": true},
		{"id": "puertas", "icono": "puertas", "tip": "Puertas", "arriba": true},
		{"id": "techo", "icono": "techo", "tip": "Techo / Carcasa", "arriba": true},
		{"id": "despiece", "icono": "despiece", "tip": "Vista explosionada del secador", "arriba": true},
		{"id": "despiece_bandeja", "icono": "despiece_bandeja", "tip": "Despiece de la bandeja 2", "arriba": true},
		{"id": "graficas", "icono": "graficas", "tip": "Gráficas"},
		{"id": "diagnostico", "icono": "diagnostico", "tip": "Diagnóstico"},
		{"id": "tabla", "icono": "tabla", "tip": "Tabla"},
		{"id": "sitio", "icono": "sitio", "tip": "Sitio"},
	])
	_riel.a_izquierda_completo()
	_cristales.append(_riel.vidrio)
	_riel.pulsado.connect(_al_riel)

	_estados_secador["rotulos"] = true
	_riel.marcar("rotulos", true)

	var t_graf := _crear_tarjeta("graficas", "Gráficas", true)
	_construir_pagina_graficas(t_graf.contenido)
	t_graf.ampliada_cambiada.connect(_al_ampliar_tarjeta.bind("graficas"))

	var t_diag := _crear_tarjeta("diagnostico", "Diagnóstico", true)
	_construir_pagina_diagnostico(t_diag.contenido)
	t_diag.ampliada_cambiada.connect(_al_ampliar_tarjeta.bind("diagnostico"))

	var t_tabl := _crear_tarjeta("tabla", "Tabla", true)
	_construir_pagina_tabla(t_tabl.contenido)
	t_tabl.ampliada_cambiada.connect(_al_ampliar_tarjeta.bind("tabla"))

	var t_siti := _crear_tarjeta("sitio", "Sitio", true)
	_construir_pagina_sitio(t_siti.contenido)
	t_siti.ampliada_cambiada.connect(_al_ampliar_tarjeta.bind("sitio"))


func _crear_tarjeta(id: String, tit: String, amp: bool) -> Tarjeta:
	var t := Tarjeta.crear(_raiz, tit)
	var top_inicial: float = TOP_TARJETA_CON_CLIMA if _clima_desplegado else TOP_TARJETA_NORMAL
	t.colocar(ANCHO_RIEL + SEP_RIEL, top_inicial, ANCHO_TARJETA, 16.0, TOP_TARJETA_AMPLIA, 16.0, ALTO_BARRA + 30.0)
	t.ampliable = amp
	t.cerrada.connect(_al_cerrar_tarjeta.bind(id))
	_cristales.append(t.vidrio)
	_tarjetas[id] = t
	return t


func notificar_clima_desplegado(desplegado: bool) -> void:
	_clima_desplegado = desplegado
	if _barra_vistas != null and not _amplio:
		_barra_vistas.visible = not desplegado

	var nuevo_top: float = TOP_TARJETA_CON_CLIMA if desplegado else TOP_TARJETA_NORMAL
	for t: Tarjeta in _tarjetas.values():
		if not t.amplia:
			t.offset_top = nuevo_top


func _al_ampliar_tarjeta(on: bool, id: String) -> void:
	var t: Tarjeta = _tarjetas.get(id)
	if t != null:
		var top_restaurado: float = TOP_TARJETA_CON_CLIMA if _clima_desplegado else TOP_TARJETA_NORMAL
		t.offset_top = TOP_TARJETA_AMPLIA if on else top_restaurado

	_amplio = on
	_ajustar_barra()

	if panel_clima_ref != null and panel_clima_ref.has_method("alternar_pantalla_completa"):
		panel_clima_ref.alternar_pantalla_completa(not on)
	elif panel_clima_ref != null:
		panel_clima_ref.visible = not on

	if _barra_vistas != null:
		_barra_vistas.visible = (not on) and (not _clima_desplegado)
	if _capa_rotulos != null:
		_capa_rotulos.visible = (not on) and _rotulos_visibles

	if id == "graficas":
		_al_ampliar_graficas(on)
	elif id == "sitio":
		if _sitio != null and _sitio.has_method("establecer_modo_amplio"):
			_sitio.establecer_modo_amplio(on)


func _construir_barra_vistas() -> void:
	_barra_vistas = PanelContainer.new()
	_barra_vistas.anchor_left = 0.5
	_barra_vistas.anchor_right = 0.5
	_barra_vistas.offset_left = -170.0
	_barra_vistas.offset_right = 170.0
	_barra_vistas.offset_top = 14.0
	_barra_vistas.offset_bottom = 54.0

	var st := Tema.caja(Tema.TRANSP, Tema.TRANSP, 0, 20.0)
	st.content_margin_left = 6.0
	st.content_margin_right = 6.0
	st.content_margin_top = 4.0
	st.content_margin_bottom = 4.0
	_barra_vistas.add_theme_stylebox_override("panel", st)
	_raiz.add_child(_barra_vistas)

	var c := Cristal.detras_de(_barra_vistas, 20.0, 8.0)
	c.ligero = true
	c.aplicar()
	_cristales.append(c)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 6)
	_barra_vistas.add_child(hb)

	var vistas_info := [
		{"id": "planta", "txt": "Planta"},
		{"id": "exterior", "txt": "Exterior"},
		{"id": "bandejas", "txt": "Junto a las bandejas"}
	]

	for v in vistas_info:
		var btn := Button.new()
		btn.text = v["txt"]
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func(): _seleccionar_vista(v["id"]))
		hb.add_child(btn)
		_btns_vistas[v["id"]] = btn

	_actualizar_botones_vista("exterior")


func _seleccionar_vista(id_vista: String) -> void:
	_actualizar_botones_vista(id_vista)
	vista_cambiada.emit(id_vista)


func _actualizar_botones_vista(activa: String) -> void:
	for id: String in _btns_vistas:
		_pintar_pildora(_btns_vistas[id], id == activa)


func ocultar_vistas(ocultar: bool) -> void:
	if _barra_vistas != null and not _amplio:
		_barra_vistas.visible = not ocultar


# ======================================================================
#  PÁGINAS DE CONTENIDO DE LAS TARJETAS
# ======================================================================
func _construir_pagina_graficas(padre: VBoxContainer) -> void:
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	padre.add_child(sc)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	_vb_graf = vb

	_b_sondas = Button.new()
	_b_sondas.text = "Sondas +"
	_b_sondas.focus_mode = Control.FOCUS_NONE
	_b_sondas.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_b_sondas.pressed.connect(_toggle_sondas)
	vb.add_child(_b_sondas)

	_checks = GridContainer.new()
	_checks.columns = 2
	_checks.add_theme_constant_override("v_separation", 4)
	_checks.visible = false
	vb.add_child(_checks)

	_fila_graf = HBoxContainer.new()
	_fila_graf.add_theme_constant_override("separation", 6)
	_fila_graf.visible = false
	vb.add_child(_fila_graf)

	var titulos_graf: Array[String] = ["Temperatura", "Humedad", "Δ Bandeja", "Viento"]
	for i: int in 4:
		var bg := Button.new()
		bg.text = titulos_graf[i]
		bg.focus_mode = Control.FOCUS_NONE
		bg.add_theme_font_size_override("font_size", 12)
		bg.pressed.connect(_elegir_graf.bind(i))
		_fila_graf.add_child(bg)
		_btns_graf.append(bg)

	_cuerpo = HBoxContainer.new()
	_cuerpo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cuerpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cuerpo.add_theme_constant_override("separation", 12)
	vb.add_child(_cuerpo)

	_rejilla = GridContainer.new()
	_rejilla.columns = 1
	_rejilla.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rejilla.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rejilla.add_theme_constant_override("h_separation", 8)
	_rejilla.add_theme_constant_override("v_separation", 8)
	_cuerpo.add_child(_rejilla)

	_g_T = _nueva_grafica("Temperatura", "°C", func(id: int): return datos.serie(id, "T"))
	_g_H = _nueva_grafica("Humedad relativa", "%", func(id: int): return datos.serie(id, "H"))
	_g_D = _nueva_grafica("Bandeja − BME280", "°C", func(id: int): return _delta(id))
	_g_V = _nueva_grafica("Viento", "m/s", func(id: int): return datos.serie(id, "V"))
	_graf = [_g_T, _g_H, _g_D, _g_V]
	_aplicar_graficas()

	var pie := Label.new()
	pie.text = "Toca una gráfica para mover el minuto del modelo 3D."
	pie.add_theme_font_size_override("font_size", 11)
	pie.add_theme_color_override("font_color", Tema.GRIS)
	vb.add_child(pie)


func _construir_pagina_diagnostico(padre: VBoxContainer) -> void:
	_kpi = Label.new()
	_kpi.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	padre.add_child(_kpi)

	_tree_d = _nuevo_tree(
		["ID", "Sensor", "Estado", "Lect. OK", "Fallos", "% éxito", "Valor al minuto", "Chequeo"],
		[34, 150, 100, 62, 52, 60, 150, 120])
	padre.add_child(_tree_d)


func _construir_pagina_tabla(padre: VBoxContainer) -> void:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	padre.add_child(vb)

	_tree_t = _nuevo_tree(
		["ID", "Sensor", "T (°C)", "HR (%)", "ΔT vs BME280", "Punto de rocío"],
		[34, 150, 62, 62, 96, 100])
	vb.add_child(_tree_t)

	var nt := Label.new()
	nt.text = "Las sondas de bandeja miden el metal; el BME280, el aire. Usa «Corregir T» para ID6 e ID4."
	nt.add_theme_font_size_override("font_size", 11)
	nt.add_theme_color_override("font_color", Tema.GRIS)
	nt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(nt)


func _construir_pagina_sitio(padre: VBoxContainer) -> void:
	_sitio = Sitio.new()
	_sitio.datos = datos
	_sitio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sitio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	padre.add_child(_sitio)


func _nueva_grafica(tit: String, uni: String, fn: Callable) -> Grafica:
	var g := Grafica.new()
	g.configurar(datos, tit, uni, [], fn)
	g.custom_minimum_size = Vector2(0.0, 150.0)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rejilla.add_child(g)
	return g


func _nuevo_tree(cols: Array, anchos: Array) -> Tree:
	var t := Tree.new()
	t.columns = cols.size()
	t.column_titles_visible = true
	t.hide_root = true
	t.focus_mode = Control.FOCUS_NONE
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_font_size_override("title_button_font_size", 12)
	for i: int in cols.size():
		t.set_column_title(i, str(cols[i]))
		t.set_column_custom_minimum_width(i, int(anchos[i]))
		t.set_column_expand(i, i == 1 or i == cols.size() - 1)
	return t


func _pintar_pildora(b: Button, activa: bool) -> void:
	var fondo: Color = Tema.ACENTO_FONDO if activa else Color(1, 1, 1, 0.08)
	var borde: Color = Tema.ACENTO if activa else Tema.TRANSP
	var sb := Tema.caja(fondo, borde, 1 if activa else 0, 12.0, Tema.PILDORA)
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	for e: String in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(e, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var col: Color = Tema.ACENTO_TEXTO if activa else Tema.GRIS
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, col)


func _elegir_graf(i: int) -> void:
	_graf_sel = i
	_aplicar_graficas()


func _aplicar_graficas() -> void:
	_rejilla.columns = 1
	for i: int in _graf.size():
		_graf[i].visible = (not _amplio) or (i == _graf_sel)
		_graf[i].custom_minimum_size.y = 150.0
	for i: int in _btns_graf.size():
		_pintar_pildora(_btns_graf[i], i == _graf_sel)
	if _fila_graf != null:
		_fila_graf.visible = _amplio
	_b_sondas.visible = not _amplio
	if _amplio and _checks.get_parent() != _cuerpo:
		_checks.reparent(_cuerpo, false)
	elif not _amplio and _checks.get_parent() != _vb_graf:
		_checks.reparent(_vb_graf, false)
		_vb_graf.move_child(_checks, _b_sondas.get_index() + 1)
	_checks.columns = 1 if _amplio else 2
	_checks.visible = _amplio
	if not _amplio:
		_b_sondas.text = "Sondas +"


# ======================================================================
#  RÓTULOS 2D CON Z-INDEX Y PROFUNDIDAD REAL
# ======================================================================
func _construir_rotulos_hud() -> void:
	var coords_3d: Dictionary = {
		2: Vector3(0.0, 2.35, 0.0),
		6: Vector3(1.91, 1.15, 1.48),
		5: Vector3(0.0, 1.15, 1.48),
		4: Vector3(-1.91, 1.15, 1.48),
		7: Vector3(-1.91, 1.15, -1.48),
		8: Vector3(0.0, 1.15, -1.48),
		9: Vector3(1.91, 1.15, -1.48),
	}

	for id: int in coords_3d:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.09, 0.11, 0.92)
		sb.border_color = Color("#2fb457")
		sb.set_border_width_all(1)
		sb.border_width_left = 3
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 7.0
		sb.content_margin_right = 9.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		panel.add_theme_stylebox_override("panel", sb)

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		panel.add_child(hb)

		var punto := ColorRect.new()
		punto.custom_minimum_size = Vector2(7, 7)
		punto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		punto.color = Color("#2fb457")
		hb.add_child(punto)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		hb.add_child(vb)

		var lbl_t := Label.new()
		lbl_t.text = "--.- °C"
		lbl_t.add_theme_font_size_override("font_size", 12)
		lbl_t.add_theme_color_override("font_color", Color.WHITE)
		vb.add_child(lbl_t)

		var lbl_n := Label.new()
		lbl_n.text = NOMBRES_SENSORES[id]
		lbl_n.add_theme_font_size_override("font_size", 10)
		lbl_n.add_theme_color_override("font_color", Tema.GRIS)
		vb.add_child(lbl_n)

		_capa_rotulos.add_child(panel)
		_etiquetas_hud[id] = {
			"panel": panel,
			"sb": sb,
			"punto": punto,
			"lbl_t": lbl_t,
			"pos3d": coords_3d[id]
		}


func _actualizar_posiciones_rotulos_hud() -> void:
	if camara_3d == null or not _rotulos_visibles or _amplio or _estados_secador.get("despiece_bandeja", false) or _estados_secador.get("despiece", false):
		_capa_rotulos.visible = false
		return

	_capa_rotulos.visible = true
	var m: float = datos.minuto
	var cam_pos: Vector3 = camara_3d.global_position

	for id: int in _etiquetas_hud:
		var item: Dictionary = _etiquetas_hud[id]
		var panel: PanelContainer = item["panel"]
		var pos_mundo: Vector3 = item["pos3d"]

		if camara_3d.is_position_behind(pos_mundo):
			panel.visible = false
			continue

		var dist: float = cam_pos.distance_to(pos_mundo)
		panel.z_index = clampi(int(100.0 - dist * 2.0), 0, 100)

		var pos_2d: Vector2 = camara_3d.unproject_position(pos_mundo)
		panel.visible = true
		panel.position = pos_2d - Vector2(panel.size.x * 0.5, panel.size.y + 12.0)

		if datos.hay_datos():
			var v: Dictionary = datos.valor(id, m)
			var es_alarma: bool = datos.en_alarma(v["T"], v["H"])
			var col_estado: Color = Color("#d62828") if es_alarma else Color("#2fb457")

			item["lbl_t"].text = "%.1f °C" % v["T"]
			item["punto"].color = col_estado
			item["sb"].border_color = col_estado


func _al_riel(id: String) -> void:
	if _tarjetas.has(id):
		var t: Tarjeta = _tarjetas[id]
		var estaba: bool = t.visible
		for k: String in _tarjetas:
			_tarjetas[k].cerrar()
			_riel.marcar(k, false)
		if not estaba:
			t.abrir()
			_riel.marcar(id, true)
			_activa = id
			_sucio = true
		_ajustar_barra()
		return

	var estaba_activa: bool = bool(_estados_secador.get(id, false))
	var nueva_activa: bool = not estaba_activa

	# EXCLUSIVIDAD 1: Si se activa despiece, apaga cualquier otra herramienta y oculta rótulos de sensores
	if nueva_activa and (id == "despiece" or id == "despiece_bandeja"):
		for k: String in _estados_secador.keys():
			if _estados_secador[k] and k != id:
				_estados_secador[k] = false
				_riel.marcar(k, false)
				accion_secador.emit(k, false)
		_rotulos_visibles = false
		_capa_rotulos.visible = false

	# EXCLUSIVIDAD 2: Si se desactiva el despiece, reensamblar y reactivar los rótulos de sensores limpios
	if not nueva_activa and (id == "despiece" or id == "despiece_bandeja"):
		_estados_secador[id] = false
		_riel.marcar(id, false)
		accion_secador.emit(id, false)
		_rotulos_visibles = true
		_estados_secador["rotulos"] = true
		_riel.marcar("rotulos", true)
		_capa_rotulos.visible = true
		accion_secador.emit("rotulos", true)
		return

	# BOTÓN RÓTULOS: si algún despiece estaba activo, apagarlo primero
	if id == "rotulos":
		if _estados_secador.get("despiece", false):
			_estados_secador["despiece"] = false
			_riel.marcar("despiece", false)
			accion_secador.emit("despiece", false)
		if _estados_secador.get("despiece_bandeja", false):
			_estados_secador["despiece_bandeja"] = false
			_riel.marcar("despiece_bandeja", false)
			accion_secador.emit("despiece_bandeja", false)

		_rotulos_visibles = nueva_activa
		_estados_secador["rotulos"] = nueva_activa
		_riel.marcar("rotulos", nueva_activa)
		_capa_rotulos.visible = nueva_activa
		accion_secador.emit("rotulos", nueva_activa)
		return

	_estados_secador[id] = nueva_activa
	_riel.marcar(id, nueva_activa)
	accion_secador.emit(id, nueva_activa)


func _al_cerrar_tarjeta(id: String) -> void:
	_riel.marcar(id, false)
	if _activa == id:
		_activa = ""
	_ajustar_barra()
	if panel_clima_ref != null and panel_clima_ref.has_method("alternar_pantalla_completa"):
		panel_clima_ref.alternar_pantalla_completa(true)
	elif panel_clima_ref != null:
		panel_clima_ref.visible = true
	if _barra_vistas != null and not _amplio and not _clima_desplegado:
		_barra_vistas.visible = true
	if _capa_rotulos != null:
		_capa_rotulos.visible = _rotulos_visibles


func _al_ampliar_graficas(on: bool) -> void:
	_amplio = on
	_aplicar_graficas()
	_sucio = true


func _toggle_sondas() -> void:
	_checks.visible = not _checks.visible
	_b_sondas.text = "Sondas −" if _checks.visible else "Sondas +"


# ======================================================================
#  BARRA INFERIOR
# ======================================================================
func _construir_barra() -> void:
	_barra = PanelContainer.new()
	_barra.anchor_left = 0.5
	_barra.anchor_right = 0.5
	_barra.anchor_top = 1.0
	_barra.anchor_bottom = 1.0
	_barra.offset_left = -ANCHO_BARRA * 0.5
	_barra.offset_right = ANCHO_BARRA * 0.5
	_barra.offset_top = -(ALTO_BARRA + 16.0)
	_barra.offset_bottom = -16.0
	
	var st := Tema.caja(Tema.TRANSP, Tema.TRANSP, 0, 24.0)
	st.content_margin_top = 8.0
	st.content_margin_bottom = 8.0
	_barra.add_theme_stylebox_override("panel", st)
	_raiz.add_child(_barra)
	
	var c := Cristal.detras_de(_barra, 28.0, 14.0)
	c.ligero = true
	c.aplicar()
	_cristales.append(c)

	var f := HBoxContainer.new()
	f.add_theme_constant_override("separation", 10)
	_barra.add_child(f)

	_b_play = BotonIcono.new()
	_b_play.tipo = "play"
	_b_play.tooltip_text = "Correr simulación"
	_b_play.pressed.connect(_al_pulsar_play)
	f.add_child(_b_play)

	_b_reset = BotonIcono.new()
	_b_reset.tipo = "reiniciar"
	_b_reset.tooltip_text = "Reiniciar"
	_b_reset.pressed.connect(func(): datos.reiniciar())
	f.add_child(_b_reset)

	var ov := OptionButton.new()
	ov.focus_mode = Control.FOCUS_NONE
	ov.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for t: String in VEL_TEXTOS:
		ov.add_item(t)
	ov.select(2)
	ov.item_selected.connect(func(i: int): datos.velocidad = VELOCIDADES[i])
	f.add_child(ov)

	_lbl_min = Label.new()
	_lbl_min.custom_minimum_size = Vector2(76, 0)
	_lbl_min.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	f.add_child(_lbl_min)

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 60.0
	_slider.step = 0.05
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(func(v: float): datos.set_minuto(v))
	f.add_child(_slider)

	_lbl_reloj = Label.new()
	_lbl_reloj.custom_minimum_size = Vector2(190, 0)
	_lbl_reloj.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	f.add_child(_lbl_reloj)

	_b_con = BotonIcono.new()
	_b_con.tipo = "enlace"
	_b_con.tooltip_text = "Conexión"
	f.add_child(_b_con)

	_b_mas = BotonIcono.new()
	_b_mas.tipo = "mas"
	_b_mas.tooltip_text = "Más opciones"
	_b_mas.pressed.connect(_abrir_menu)
	f.add_child(_b_mas)


func _al_pulsar_play() -> void:
	if not datos.reproduciendo:
		if _estados_secador.get("despiece", false):
			_al_riel("despiece")
		if _estados_secador.get("despiece_bandeja", false):
			_al_riel("despiece_bandeja")
	datos.alternar()


func _ajustar_barra() -> void:
	if _barra == null:
		return
	var t: Tarjeta = _tarjetas.get(_activa) if _activa != "" else null
	if t != null and t.visible and t.amplia:
		_barra.anchor_left = 0.0
		_barra.anchor_right = 1.0
		_barra.offset_left = ANCHO_RIEL + SEP_RIEL
		_barra.offset_right = -16.0
	elif t != null and t.visible:
		_barra.anchor_left = 0.0
		_barra.anchor_right = 1.0
		_barra.offset_left = t.offset_right + 16.0
		_barra.offset_right = -16.0
	else:
		_barra.anchor_left = 0.5
		_barra.anchor_right = 0.5
		_barra.offset_left = -ANCHO_BARRA * 0.5
		_barra.offset_right = ANCHO_BARRA * 0.5


func _construir_menu() -> void:
	_menu = PopupMenu.new()
	_menu.add_item("Subir datos…", 0)
	_menu.add_item("Abrir carpeta de registros", 4)
	_menu.add_item("Elegir carpeta de registros…", 5)
	_menu.add_check_item("Corregir T (ID6 −2,8 · ID4 +1,4)", 1)
	_menu.add_separator()
	_menu.add_item("Ocultar interfaz  [H]", 2)
	_menu.add_separator()
	_menu.add_item("Sin registro cargado", 3)
	_menu.set_item_disabled(_menu.get_item_index(3), true)
	_menu.id_pressed.connect(_clic_menu)
	_raiz.add_child(_menu)


func _abrir_menu() -> void:
	var r := _b_mas.get_global_rect()
	_menu.reset_size()
	var tam: Vector2 = _menu.get_contents_minimum_size()
	_menu.popup(Rect2i(Vector2i(int(r.end.x - tam.x), int(r.position.y - tam.y - 10.0)), Vector2i(tam)))


func _clic_menu(id: int) -> void:
	match id:
		0: _dialogo.popup_centered(Vector2i(900, 520))
		1:
			var i: int = _menu.get_item_index(1)
			datos.corregir = not _menu.is_item_checked(i)
		2: _toggle_interfaz()
		4:
			var d: String = datos.carpeta_registros()
			DirAccess.make_dir_recursive_absolute(d)
			OS.shell_open(d)
		5: _dlg_carpeta.popup_centered(Vector2i(900, 520))


func _al_correccion(activa: bool) -> void:
	if _menu != null:
		_menu.set_item_checked(_menu.get_item_index(1), activa)
	_sucio = true


func _construir_aviso() -> void:
	_toast = Label.new()
	_toast.theme = _tema
	_toast.visible = false
	_toast.anchor_left = 1.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_right = -MARGEN
	_toast.offset_left = -MARGEN - 10.0
	_toast.offset_bottom = -(MARGEN + ALTO_BARRA + 8.0)
	_toast.offset_top = _toast.offset_bottom - 10.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var sb := Tema.caja(Color(0.10, 0.10, 0.11, 0.95), Tema.BORDE, 1, 14.0, 14)
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	_toast.add_theme_stylebox_override("normal", sb)
	add_child(_toast)


func _aviso(texto: String, error: bool = false, seg: float = 5.0) -> void:
	_toast.text = texto
	_toast.add_theme_color_override("font_color", Tema.MAL if error else Tema.TINTA)
	_toast.visible = true
	_toast.reset_size()
	_id_aviso += 1
	var mi: int = _id_aviso
	await get_tree().create_timer(seg).timeout
	if mi == _id_aviso and is_instance_valid(_toast):
		_toast.visible = false


func bloquea_mouse(pos: Vector2) -> bool:
	if _raiz == null or not _raiz.visible:
		return false
	if _barra != null and _barra.is_visible_in_tree() and _barra.get_global_rect().has_point(pos):
		return true
	if _barra_vistas != null and _barra_vistas.is_visible_in_tree() and _barra_vistas.get_global_rect().has_point(pos):
		return true
	if _riel != null and _riel.is_visible_in_tree() and _riel.get_global_rect().has_point(pos):
		return true
	if _pild != null and _pild.is_visible_in_tree() and _pild.get_global_rect().has_point(pos):
		return true
	if _panel_con != null and _panel_con.is_visible_in_tree() and _panel_con.get_global_rect().has_point(pos):
		return true
	for t: Tarjeta in _tarjetas.values():
		if t.is_visible_in_tree() and t.get_global_rect().has_point(pos):
			return true
	return false


func margen_izquierdo() -> float:
	if _raiz == null or not _raiz.visible or _activa == "":
		return 0.0
	var t: Tarjeta = _tarjetas.get(_activa)
	if t != null and t.is_visible_in_tree() and not t.amplia:
		return t.get_global_rect().end.x
	return 0.0


func margen_superior() -> float:
	if _clima_desplegado and not _amplio:
		return 112.0
	return 0.0


func _toggle_interfaz() -> void:
	_raiz.visible = not _raiz.visible
	if not _raiz.visible:
		_aviso("Interfaz oculta · pulsa H para mostrarla", false, 3.0)


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	if k.keycode == KEY_H:
		_toggle_interfaz()


func asignar_camara(c: Camera3D) -> void:
	camara_3d = c
	if _sitio != null:
		_sitio.camara = c


func asignar_clima(c: Clima) -> void:
	_clima = c
	if _sitio != null:
		_sitio.clima = c
		_sitio.actualizar()


func _al_cargar(_info: Dictionary) -> void:
	_tree_d.clear()
	_it_d.clear()
	_tree_t.clear()
	_it_t.clear()

	if _sitio != null:
		_sitio.actualizar()
	_slider.max_value = maxf(datos.duracion, 0.1)
	_armar_checks()
	_g_V.set_ids(datos.ids_viento())
	_aplicar_ids()
	
	var resumen_str: String = "%s · %d lecturas · %.1f min" % [
		datos.archivo.get_file(), datos.t_min.size(), datos.duracion]
	_menu.set_item_text(_menu.get_item_index(3), resumen_str)
	_aviso("Registro cargado: " + resumen_str, false, 4.0)
	_al_reproduccion(datos.reproduciendo)
	_al_minuto(datos.minuto)


func _al_fallar(msg: String) -> void:
	_aviso("Error: " + msg, true, 7.0)
	_al_reproduccion(datos.reproduciendo)


func _al_minuto(m: float) -> void:
	_slider.set_value_no_signal(m)
	_lbl_min.text = "Min %.1f" % m
	_lbl_reloj.text = _reloj(m)
	_sucio = true


func _al_reproduccion(activa: bool) -> void:
	_b_play.tipo = "pausa" if activa else "play"
	_b_play.tooltip_text = "Pausar" if activa else "Correr simulación"
	_b_play.queue_redraw()

	if _riel != null:
		_riel.set_deshabilitado("despiece", activa)
		_riel.set_deshabilitado("despiece_bandeja", activa)


# ---- Conexion: pildora de estado + panel desplegable ----
func _construir_enlace_ui() -> void:
	_pild = PanelConexion.Pildora.new()
	_pild.tooltip_text = "Estado de la conexión · clic para ver las fuentes"
	_pild.pressed.connect(func(): _alternar_panel_con(false))
	_raiz.add_child(_pild)

	_panel_con = PanelConexion.new()
	_raiz.add_child(_panel_con)

	_b_con.pressed.connect(func(): _alternar_panel_con(true))
	_pintar_enlace()


# Llamar desde principal.gd:  interfaz.asignar_enlace(enlace)
func asignar_enlace(e: EnlaceDatos) -> void:
	enlace = e
	var ign: Array[Control] = [_pild, _b_con]
	_panel_con.configurar(e, ign)
	e.estado_cambiado.connect(func(_i: Dictionary): _pintar_enlace())
	e.fuentes_actualizadas.connect(func(_l: Array): _pintar_enlace())
	e.aviso.connect(func(t: String, err: bool): _aviso(t, err, 6.0))
	_pintar_enlace()


func _alternar_panel_con(desde_boton: bool) -> void:
	if _panel_con.visible:
		_panel_con.cerrar()
		return
	if desde_boton:
		_panel_con.abrir(_b_con.get_global_rect().end.x, true, _barra.get_global_rect().position.y)
	else:
		var r: Rect2 = _pild.get_global_rect()
		_panel_con.abrir(r.position.x, false, r.position.y)


func _pintar_enlace() -> void:
	var est: String = enlace.estado if enlace != null else "sin_puente"
	var col: Color = Tema.GRIS
	var txt: String = "Sin puente"
	match est:
		"online":
			col = Tema.OK
			txt = "Online · " + enlace.nombre_de(enlace.fuente)
		"buscando":
			col = Tema.AVISO
			txt = "Conectando…"
		"error":
			col = Tema.MAL
			txt = "Error de conexión"
		"desconectado":
			txt = "Desconectado"
	if _pild != null:
		_pild.poner(txt, col)
	if _b_con != null:
		_b_con.color_estado = col
		_b_con.queue_redraw()


# La pildora flota justo sobre el extremo izquierdo de la barra de tiempo
func _actualizar_pildora_pos() -> void:
	if _pild == null or _barra == null:
		return
	var r: Rect2 = _barra.get_global_rect()
	_pild.position = Vector2(r.position.x + 14.0, r.position.y - _pild.size.y - 8.0)


# ---- Modo en vivo (lecturas que llegan del puente Python) ----
func _al_vivo(activo: bool) -> void:
	if activo:
		_tree_d.clear()
		_it_d.clear()
		_tree_t.clear()
		_it_t.clear()
		_n_ids_vivo = -1
		_slider.max_value = 0.1
		_menu.set_item_text(_menu.get_item_index(3), "En vivo · esperando datos…")
		_aviso("Recibiendo datos en vivo", false, 3.0)
		_al_reproduccion(false)
	_sucio = true


func _al_lectura(m: float) -> void:
	_slider.max_value = maxf(m, 0.1)
	# solo al aparecer sensores nuevos (normalmente la 1ª lectura) se rearman las listas
	if datos.series.size() != _n_ids_vivo:
		_n_ids_vivo = datos.series.size()
		_armar_checks()
		_g_V.set_ids(datos.ids_viento())
		_aplicar_ids()
	_menu.set_item_text(_menu.get_item_index(3), "En vivo · %d lecturas · %.1f min" % [
		datos.t_min.size(), datos.duracion])
	_sucio = true


func _al_soltar(archivos: PackedStringArray) -> void:
	if archivos.is_empty():
		return
	var ext: String = archivos[0].get_extension().to_lower()
	if ext in ["csv", "txt"]:
		datos.cargar_csv(archivos[0])
	else:
		_al_fallar("Solo acepto archivos .csv o .txt")


func _reloj(m: float) -> String:
	var p: PackedStringArray = datos.inicio_texto.replace("T", " ").split(" ", false)
	if p.size() < 2:
		return ""
	var h: PackedStringArray = p[1].split(":")
	var s: int = int(h[0]) * 3600 + int(h[1]) * 60 + (int(h[2]) if h.size() > 2 else 0) + int(m * 60.0)
	s = s % 86400
	return "%s  %02d:%02d:%02d" % [p[0], floori(float(s) / 3600.0), floori(float(s % 3600) / 60.0), s % 60]


func _armar_checks() -> void:
	for c: Node in _checks.get_children():
		c.queue_free()
	_shown.clear()
	for id: int in datos.ids_termo():
		_shown.append(id)
		var hb := HBoxContainer.new()
		var sw := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Tema.claro(datos.color_de(id))
		sw.add_theme_stylebox_override("panel", sb)
		sw.custom_minimum_size = Vector2(16, 5)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(sw)
		
		var cb := CheckBox.new()
		cb.text = datos.nombre(id)
		cb.button_pressed = true
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 12)
		cb.toggled.connect(func(on: bool): _toggle_id(id, on))
		hb.add_child(cb)
		_checks.add_child(hb)


func _toggle_id(id: int, on: bool) -> void:
	if on and not (id in _shown):
		_shown.append(id)
	elif not on:
		_shown.erase(id)
	_aplicar_ids()


func _aplicar_ids() -> void:
	var l: Array = datos.ids_termo().filter(func(i: int): return i in _shown)
	_g_T.set_ids(l)
	_g_H.set_ids(l)
	_g_D.set_ids(l.filter(func(i: int): return i != DatosSensores.AIRE))


func _delta(id: int) -> PackedFloat32Array:
	var a: PackedFloat32Array = datos.serie(id, "T")
	var b: PackedFloat32Array = datos.serie(DatosSensores.AIRE, "T")
	var n: int = mini(a.size(), b.size())
	var o := PackedFloat32Array()
	o.resize(n)
	for i: int in n:
		o[i] = a[i] - b[i]
	return o


func _process(delta: float) -> void:
	if _clima != null:
		var f: float = Tema.factor_noche(_clima.hora)
		if absf(f - _f_noche) > 0.01:
			_f_noche = f
			for cr: Cristal in _cristales:
				cr.noche(f)

	_actualizar_posiciones_rotulos_hud()
	_actualizar_pildora_pos()

	_acum += delta
	if _sucio and _acum >= 0.1:
		_acum = 0.0
		_sucio = false
		if _activa == "" or not _raiz.visible or not datos.hay_datos():
			return
		match _activa:
			"diagnostico": _llenar_diag()
			"tabla": _llenar_tabla()
			"sitio":
				if _sitio != null:
					_sitio.actualizar()


func _item(arbol: Tree, cache: Dictionary, id: int) -> TreeItem:
	if not cache.has(id):
		if arbol.get_root() == null:
			arbol.create_item()
		cache[id] = arbol.create_item(arbol.get_root())
	return cache[id]


func _congelado(id: int, m: float) -> bool:
	var s: PackedFloat32Array = datos.serie(id, "T")
	var vistos: Dictionary = {}
	var n: int = 0
	for i: int in mini(s.size(), datos.t_min.size()):
		var t: float = datos.t_min[i]
		if t <= m and t > m - 5.0:
			n += 1
			vistos[snappedf(s[i], 0.01)] = true
	return n > 30 and vistos.size() < 2


func _llenar_diag() -> void:
	var m: float = datos.minuto
	var res: Dictionary = datos.resumen()
	var n: int = res["n"]
	_kpi.text = "%d lecturas · ciclo medio %.1f s · mayor hueco %.0f s · límites T %d–%d °C, HR %d–%d %%" % [
		n, res["ciclo_medio"], res["hueco_max"],
		int(DatosSensores.T_MIN), int(DatosSensores.T_MAX),
		int(DatosSensores.H_MIN), int(DatosSensores.H_MAX)]
		
	var ids: Array = datos.series.keys()
	ids.sort()
	for id: int in ids:
		var tipo: String = datos.series[id]["tipo"]
		var ok: int = datos.lecturas_ok(id)
		var estado: String = "OK"
		var chk: String = "OK"
		var valor: String = "-"
		var col: Color = Tema.OK
		
		match tipo:
			"sonda", "aire":
				var v: Dictionary = datos.valor(id, m)
				valor = "%.1f °C · %.1f %%" % [v["T"], v["H"]]
				if datos.en_alarma(v["T"], v["H"]):
					estado = "ALARMA"
					col = Tema.MAL
				if _congelado(id, m):
					chk = "Valor congelado"
					col = Tema.AVISO
			"viento":
				valor = "%.1f m/s" % datos.viento(id, m)
				var mx: float = 0.0
				for x: float in datos.series[id]["V"]:
					if not is_nan(x):
						mx = maxf(mx, x)
				if mx == 0.0:
					chk = "Sin flujo (apagado)"
					col = Tema.AVISO
			_:
				estado = "Sin identificar"
				chk = "Dato inválido: ignorar"
				col = Tema.AVISO
				valor = "crudo %.0f / %.0f" % [
					datos._interp(datos.series[id]["a"], m), datos._interp(datos.series[id]["b"], m)]
					
		var it: TreeItem = _item(_tree_d, _it_d, id)
		var textos: Array[String] = [
			str(id), datos.nombre(id), estado, str(ok), str(n - ok),
			"%.0f" % (100.0 * ok / maxf(n, 1)), valor, chk
		]
		for c: int in textos.size():
			it.set_text(c, textos[c])
		it.set_custom_color(2, col)
		it.set_custom_color(7, col)


func _llenar_tabla() -> void:
	var m: float = datos.minuto
	for id: int in datos.ids_termo():
		var v: Dictionary = datos.valor(id, m)
		var td: float = datos.punto_rocio(v["T"], v["H"])
		var dt: String = "—" if id == DatosSensores.AIRE else "%+.1f" % datos.delta_vs_aire(id, m)
		var it: TreeItem = _item(_tree_t, _it_t, id)
		var textos: Array[String] = [str(id), datos.nombre(id), "%.1f" % v["T"], "%.1f" % v["H"], dt, "%.1f" % td]
		for c: int in textos.size():
			it.set_text(c, textos[c])


# ======================================================================
#  BotonIcono: Iconos de la barra inferior
# ======================================================================
class BotonIcono extends Button:
	var tipo: String = ""
	var color_estado: Color = Color(0, 0, 0, 0)   # solo para el icono "enlace"

	func _init() -> void:
		custom_minimum_size = Vector2(36, 36)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		focus_mode = Control.FOCUS_NONE
		flat = true
		for e: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(e, StyleBoxEmpty.new())

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var hover: bool = is_hovered()
		if hover:
			draw_circle(c, 17.0, Color(1, 1, 1, 0.12))
		var col: Color = Tema.TINTA if hover else Tema.GRIS
		match tipo:
			"play":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-5, -8), c + Vector2(-5, 8), c + Vector2(8, 0)]), Tema.ACENTO)
			"pausa":
				draw_rect(Rect2(c + Vector2(-7, -8), Vector2(5, 16)), Tema.ACENTO)
				draw_rect(Rect2(c + Vector2(2, -8), Vector2(5, 16)), Tema.ACENTO)
			"reiniciar":
				var fin: float = deg_to_rad(230.0)
				draw_arc(c, 8.0, deg_to_rad(-50.0), fin, 20, col, 2.0, true)
				var p: Vector2 = c + Vector2(cos(fin), sin(fin)) * 8.0
				var tg := Vector2(-sin(fin), cos(fin))
				var nr := Vector2(cos(fin), sin(fin))
				draw_colored_polygon(PackedVector2Array([p + tg * 5.0, p + nr * 4.0, p - nr * 4.0]), col)
			"mas":
				for dx: float in [-8.0, 0.0, 8.0]:
					draw_circle(c + Vector2(dx, 0), 2.0, col)
			"enlace":
				var ce: Color = color_estado if color_estado.a > 0.0 else col
				var base: Vector2 = c + Vector2(0, 7)
				draw_circle(base, 2.2, ce)
				for r: float in [6.0, 10.0, 14.0]:
					draw_arc(base, r, deg_to_rad(-135.0), deg_to_rad(-45.0), 12, ce, 2.0, true)
