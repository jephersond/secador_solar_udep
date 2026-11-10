class_name Clima
extends Node

# ======================================================================
#  clima.gd - RELOJ ÚNICO Y ESTADO METEOROLÓGICO CENTRAL
# ======================================================================

signal modo_cambiado(nuevo_modo: int)

enum Modo { AUTO, PC, REGISTRO, MANUAL }

const PRESETS := {
	"soleado": {"nubes": 0.05, "lluvia": 0.0},
	"nublado": {"nubes": 0.85, "lluvia": 0.0},
	"lluvia":  {"nubes": 1.0,  "lluvia": 1.0},
}
const DIAS_ACUM := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]

var seg_transicion: float = 10.0
var segundos_por_hora: float = 3.0
var TIEMPO_SIN_PYTHON: float = 25.0
var curva_nubes: Array = []
var curva_precip: Array = []

# Estado público
var modo_actual: Modo = Modo.AUTO
var hora: float = 12.0
var doy: int = 296
var fecha_txt: String = ""
var nubes: float = 0.05
var lluvia: float = 0.0
var nubes_obj: float = 0.05
var lluvia_obj: float = 0.0
var clima_nombre: String = "soleado"
var ciclo_hora: bool = false
var en_fallback: bool = false

# Compatibilidad con panel_clima y otros módulos
var en_respaldo: bool:
	get: return en_fallback
var sigue_registro: bool:
	get: return modo_actual == Modo.REGISTRO
var modo_auto: bool:
	get: return modo_actual == Modo.AUTO

var _seg_sin_datos: float = 0.0


static func dia_del_anio(y: int, m: int, d: int) -> int:
	var bisiesto := (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
	return int(DIAS_ACUM[m - 1]) + d + (1 if (bisiesto and m > 2) else 0)


# Función matemática compartida para interpolar cualquier arreglo de 24 horas
static func interpolar_curva_24h(curva: Array, h: float) -> float:
	if curva.is_empty():
		return NAN
	var n := curva.size()
	var x := clampf(h, 0.0, float(n - 1))
	var i := clampi(int(floor(x)), 0, n - 1)
	var j := mini(i + 1, n - 1)
	var a = curva[i]
	var b = curva[j]
	if typeof(a) != TYPE_FLOAT and typeof(a) != TYPE_INT:
		return NAN
	if typeof(b) != TYPE_FLOAT and typeof(b) != TYPE_INT:
		return float(a)
	return lerpf(float(a), float(b), x - float(i))


# Retorna 0.0 (noche) a 1.0 (pleno día) unificado para todo el proyecto
static func calcular_luz_dia(h: float) -> float:
	return smoothstep(5.5, 7.5, h) * (1.0 - smoothstep(16.5, 18.5, h))


func _ready() -> void:
	cambiar_modo(Modo.AUTO)


func _process(delta: float) -> void:
	if (modo_actual == Modo.AUTO or modo_actual == Modo.PC) and not ciclo_hora:
		_hora_del_pc()

	if modo_actual == Modo.AUTO:
		_seg_sin_datos += delta
		if _seg_sin_datos > TIEMPO_SIN_PYTHON:
			push_warning("[CLIMA] Python sin respuesta -> Fallback a modo PC (Soleado)")
			en_fallback = true
			cambiar_modo(Modo.PC)

	if ciclo_hora:
		hora = fposmod(hora + delta / segundos_por_hora, 24.0)

	var paso := delta / maxf(seg_transicion, 0.1)
	nubes = move_toward(nubes, nubes_obj, paso)
	lluvia = move_toward(lluvia, lluvia_obj, paso)


func cambiar_modo(nuevo: Modo) -> void:
	modo_actual = nuevo
	ciclo_hora = false
	match modo_actual:
		Modo.AUTO:
			en_fallback = false
			_hora_del_pc()
		Modo.PC:
			_hora_del_pc()
			fijar_clima("soleado")
		Modo.REGISTRO, Modo.MANUAL:
			en_fallback = false

	modo_cambiado.emit(int(modo_actual))


func fijar_instante(nuevo_doy: int, nueva_hora: float, fecha: String) -> void:
	if modo_actual != Modo.REGISTRO:
		return
	doy = nuevo_doy
	hora = fposmod(nueva_hora, 24.0)
	fecha_txt = fecha
	if not curva_nubes.is_empty():
		_actualizar_clima_desde_curva(hora)


func _hora_del_pc() -> void:
	var t := Time.get_datetime_dict_from_system()
	hora = float(t["hour"]) + float(t["minute"]) / 60.0 + float(t["second"]) / 3600.0
	_fecha_del_pc(t)


func _fecha_del_pc(t: Dictionary = {}) -> void:
	if t.is_empty():
		t = Time.get_datetime_dict_from_system()
	doy = dia_del_anio(int(t["year"]), int(t["month"]), int(t["day"]))
	fecha_txt = "%02d/%02d/%04d" % [t["day"], t["month"], t["year"]]


func recibir_datos(datos: Dictionary) -> void:
	_seg_sin_datos = 0.0
	var tipo: String = datos.get("tipo", "")
	if (modo_actual == Modo.REGISTRO and tipo == "en_vivo") or (modo_actual == Modo.AUTO and tipo == "historico"):
		return

	if datos.get("fuente") == "sin_internet" and modo_actual == Modo.AUTO:
		en_fallback = true
		cambiar_modo(Modo.PC)
		return

	if datos.has("curva_nubes"): curva_nubes = datos["curva_nubes"]
	if datos.has("curva_precip"): curva_precip = datos["curva_precip"]

	if modo_actual == Modo.REGISTRO and not curva_nubes.is_empty():
		_actualizar_clima_desde_curva(hora)
	elif modo_actual == Modo.AUTO:
		if datos.has("clima") and PRESETS.has(str(datos["clima"])):
			clima_nombre = str(datos["clima"])
			if clima_nombre != "lluvia":
				lluvia = 0.0
				lluvia_obj = 0.0
		if datos.has("nubes"):
			nubes_obj = clampf(float(datos["nubes"]), 0.0, 1.0)
		if datos.has("lluvia") and clima_nombre == "lluvia":
			var ll := float(datos["lluvia"])
			lluvia_obj = clampf(ll, 0.0, 1.0) if ll >= 0.25 else 0.0


func _actualizar_clima_desde_curva(h: float) -> void:
	nubes_obj = interpolar_curva_24h(curva_nubes, h)
	var pr: float = interpolar_curva_24h(curva_precip, h)
	if is_nan(pr): pr = 0.0

	if pr >= 0.5:
		clima_nombre = "lluvia"
		lluvia_obj = clampf(pr / 2.0, 0.25, 1.0)
	else:
		lluvia_obj = 0.0
		lluvia = 0.0
		clima_nombre = "nublado" if nubes_obj >= 0.55 else "soleado"


func fijar_clima(nombre: String) -> void:
	if not PRESETS.has(nombre):
		return
	clima_nombre = nombre
	nubes_obj = PRESETS[nombre]["nubes"]
	lluvia_obj = PRESETS[nombre]["lluvia"]


# ---------- TECLADO ----------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F: cambiar_modo(Modo.AUTO)
		KEY_P: cambiar_modo(Modo.PC)
		KEY_G: cambiar_modo(Modo.REGISTRO)  # Usamos G para dejar la R libre a la cámara
		KEY_1:
			cambiar_modo(Modo.MANUAL)
			fijar_clima("soleado")
		KEY_2:
			cambiar_modo(Modo.MANUAL)
			fijar_clima("nublado")
		KEY_3:
			cambiar_modo(Modo.MANUAL)
			fijar_clima("lluvia")
		KEY_N:
			cambiar_modo(Modo.MANUAL)
			hora = 23.0
		KEY_M:
			cambiar_modo(Modo.MANUAL)
			hora = 12.0
		KEY_T:
			cambiar_modo(Modo.MANUAL)
			hora = 17.8
		KEY_C:
			cambiar_modo(Modo.MANUAL)
			ciclo_hora = not ciclo_hora
		KEY_COMMA:
			cambiar_modo(Modo.MANUAL)
			hora = fposmod(hora - 1.0, 24.0)
		KEY_PERIOD:
			cambiar_modo(Modo.MANUAL)
			hora = fposmod(hora + 1.0, 24.0)
