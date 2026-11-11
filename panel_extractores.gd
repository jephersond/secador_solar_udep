class_name PanelExtractores
extends VBoxContainer

# ======================================================================
#  panel_extractores.gd - Control de los extractores (dimmers del ESP32)
#  Godot solo manda el modo y los limites; el ESP32 decide y tiene la ultima palabra.
#  Los comandos estan descritos en PROTOCOLO_EXTRACTORES.md
# ======================================================================

const N_EXTRACTORES: int = 2
const MODOS: Array = ["OFF", "ON", "AUTO"]
const MODOS_TXT: Array = ["Apagado", "Encendido", "Automático"]
const FUENTES: Array = ["EXT", "AMB"]
const FUENTES_TXT: Array = ["Temp. del extractor", "Temp. ambiente"]

var enlace: EnlaceDatos

var _modo: Array[int] = [0, 0]
var _fuente: Array[int] = [0, 0]
var _t_on: Array[SpinBox] = []
var _t_max: Array[SpinBox] = []
var _b_modo: Array = []           # por extractor: Array de Button
var _o_fuente: Array[OptionButton] = []
var _bloque_auto: Array[Control] = []
var _lbl_estado: Label
var _lbl_resp: Label


func configurar(e: EnlaceDatos) -> void:
	enlace = e
	e.estado_cambiado.connect(func(_i: Dictionary): _pintar_estado())
	e.extractor_respuesta.connect(_al_respuesta)
	_pintar_estado()


func _init() -> void:
	add_theme_constant_override("separation", 10)

	_lbl_estado = Label.new()
	_lbl_estado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_estado.add_theme_font_size_override("font_size", 12)
	add_child(_lbl_estado)

	for i: int in N_EXTRACTORES:
		add_child(_construir_extractor(i))

	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	add_child(fila)
	var b_ap := Button.new()
	b_ap.text = "Aplicar al ESP32"
	b_ap.focus_mode = Control.FOCUS_NONE
	b_ap.pressed.connect(_aplicar)
	fila.add_child(b_ap)
	var b_leer := Button.new()
	b_leer.text = "Leer estado"
	b_leer.focus_mode = Control.FOCUS_NONE
	b_leer.pressed.connect(func(): _enviar("X?"))
	fila.add_child(b_leer)

	_lbl_resp = Label.new()
	_lbl_resp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_resp.add_theme_font_size_override("font_size", 12)
	_lbl_resp.add_theme_color_override("font_color", Tema.GRIS)
	_lbl_resp.text = "El ESP32 tiene el control final: aquí solo se le indica el modo y los límites."
	add_child(_lbl_resp)


func _construir_extractor(i: int) -> Control:
	var caja := PanelContainer.new()
	caja.add_theme_stylebox_override("panel", Tema.caja(Color(1, 1, 1, 0.04), Tema.BORDE, 1, 12.0, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	caja.add_child(v)

	var t := Label.new()
	t.text = "Extractor %d" % (i + 1)
	v.add_child(t)

	# Modo: apagado / encendido / automatico
	var fm := HBoxContainer.new()
	fm.add_theme_constant_override("separation", 6)
	v.add_child(fm)
	var botones: Array = []
	for k: int in MODOS.size():
		var b := Button.new()
		b.text = MODOS_TXT[k]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_elegir_modo.bind(i, k))
		fm.add_child(b)
		botones.append(b)
	_b_modo.append(botones)

	# Ajustes del modo automatico (solo se ven en Automatico)
	var auto := VBoxContainer.new()
	auto.add_theme_constant_override("separation", 6)
	v.add_child(auto)
	_bloque_auto.append(auto)

	auto.add_child(_fila_etiqueta("Decide según"))
	var of := OptionButton.new()
	of.focus_mode = Control.FOCUS_NONE
	for k: int in FUENTES_TXT.size():
		of.add_item(FUENTES_TXT[k])
	of.item_selected.connect(func(idx: int): _fuente[i] = idx)
	auto.add_child(of)
	_o_fuente.append(of)

	var fl := HBoxContainer.new()
	fl.add_theme_constant_override("separation", 8)
	auto.add_child(fl)
	_t_on.append(_spin(fl, "Enciende a", 35.0))
	_t_max.append(_spin(fl, "Máximo a", 40.0))

	_elegir_modo(i, 0)
	return caja


func _fila_etiqueta(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Tema.GRIS)
	return l


func _spin(padre: Control, txt: String, valor: float) -> SpinBox:
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padre.add_child(c)
	c.add_child(_fila_etiqueta(txt))
	var s := SpinBox.new()
	s.min_value = 20.0
	s.max_value = 80.0
	s.step = 0.5
	s.suffix = "°C"
	s.value = valor
	c.add_child(s)
	return s


func _elegir_modo(i: int, k: int) -> void:
	_modo[i] = k
	for j: int in _b_modo[i].size():
		(_b_modo[i][j] as Button).set_pressed_no_signal(j == k)
	_bloque_auto[i].visible = (k == 2)


func _aplicar() -> void:
	if enlace == null:
		return
	for i: int in N_EXTRACTORES:
		var n: int = i + 1
		if _modo[i] == 2:
			if _t_max[i].value <= _t_on[i].value:
				_lbl_resp.text = "Extractor %d: el máximo debe ser mayor que la temperatura de encendido." % n
				_lbl_resp.add_theme_color_override("font_color", Tema.MAL)
				return
			_enviar("X%d FUENTE %s" % [n, FUENTES[_fuente[i]]])
			_enviar("X%d LIM %.1f %.1f" % [n, _t_on[i].value, _t_max[i].value])
		_enviar("X%d MODO %s" % [n, MODOS[_modo[i]]])
	_lbl_resp.text = "Comandos enviados…"
	_lbl_resp.add_theme_color_override("font_color", Tema.GRIS)


func _enviar(linea: String) -> void:
	if enlace != null:
		enlace.enviar_extractor(linea)


func _pintar_estado() -> void:
	var en_vivo: bool = enlace != null and enlace.estado == "online" and enlace.fuente.begins_with("serial")
	_lbl_estado.text = "● ESP32 conectado por serial" if en_vivo else "○ Sin ESP32 en vivo: activa el modo en vivo desde Conexión para controlar los extractores."
	_lbl_estado.add_theme_color_override("font_color", Tema.OK if en_vivo else Tema.AVISO)


# Respuestas: "OK X1 MODO AUTO", "ERR ...", "X1: MODO=AUTO FUENTE=AMB LIM=35.0/40.0 ANG=120 ON=1"
func _al_respuesta(linea: String) -> void:
	if linea.begins_with("ERR"):
		_lbl_resp.text = "ESP32: " + linea
		_lbl_resp.add_theme_color_override("font_color", Tema.MAL)
		return
	if linea.begins_with("OK"):
		_lbl_resp.text = "ESP32 confirmó: " + linea.trim_prefix("OK ")
		_lbl_resp.add_theme_color_override("font_color", Tema.OK)
		return
	# estado completo de un extractor: se refleja en los controles
	var n: int = int(linea.substr(1, 1)) - 1
	if n < 0 or n >= N_EXTRACTORES:
		return
	for par: String in linea.substr(3).strip_edges().split(" ", false):
		var kv: PackedStringArray = par.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"MODO":
				var k: int = MODOS.find(kv[1])
				if k >= 0:
					_elegir_modo(n, k)
			"FUENTE":
				var f: int = FUENTES.find(kv[1])
				if f >= 0:
					_fuente[n] = f
					_o_fuente[n].select(f)
			"LIM":
				var lim: PackedStringArray = kv[1].split("/")
				if lim.size() == 2:
					_t_on[n].value = float(lim[0])
					_t_max[n].value = float(lim[1])
	_lbl_resp.text = "Estado leído del ESP32."
	_lbl_resp.add_theme_color_override("font_color", Tema.OK)
