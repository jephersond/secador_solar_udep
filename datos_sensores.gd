class_name DatosSensores
extends Node

# ======================================================================
#  datos_sensores.gd - CARGA Y PROCESAMIENTO DE REGISTROS CSV
# ======================================================================

signal datos_cargados(info: Dictionary)
signal carga_fallida(mensaje: String)
signal minuto_cambiado(minuto: float)
signal reproduccion_cambiada(activa: bool)
signal correccion_cambiada(activa: bool)
signal lectura_agregada(minuto: float)      # llego una lectura en vivo
signal modo_vivo_cambiado(activo: bool)

# Configuración de hardware
const AIRE := 2
const VIENTO := [15, 16]
const INVALIDOS := [1]
const INVERTIDOS := [6]
const OFFSETS := {6: -2.8, 4: 1.4}
const ORDEN_UI := [2, 6, 5, 4, 7, 8, 9]

const T_MIN := 10.0
const T_MAX := 70.0
const H_MIN := 5.0
const H_MAX := 95.0

# Estado de cada sensor
#   REGISTRO   : se esta viendo un archivo
#   ESPERANDO  : modo en vivo, aun no llega su primer dato
#   EN_VIVO    : dato reciente
#   RETENIDO   : no llego dato nuevo; se mantiene el ultimo valor hasta que se refresque
#   SIN_SENAL  : paso demasiado tiempo sin dato -> NaN
enum Estado { REGISTRO, ESPERANDO, EN_VIVO, RETENIDO, SIN_SENAL }
const ESPERA_INICIAL_S := 60.0     # al activar el modo en vivo: maximo esperando el primer dato
const FRESCO_MIN_S := 10.0         # "en vivo" si el dato tiene menos de esto (o 1,5 ciclos, lo que sea mayor)
const RETENER_MIN_S := 18.0        # se retiene el ultimo valor hasta esto (o 3 ciclos, lo que sea mayor)

const DIR_REGISTROS := "user://registros"
const ARCHIVO_ULTIMO := "user://ultimo_registro.txt"
const ARCHIVO_CONFIG := "user://config_visor.cfg"

const NOMBRES := {
	1: "ID1 (sin identificar)", 2: "BME280 (aire)",
	6: "Bandeja 1 · ID6", 5: "Bandeja 2 · ID5", 4: "Bandeja 3 · ID4",
	7: "Bandeja 4 · ID7", 8: "Bandeja 5 · ID8", 9: "Bandeja 6 · ID9",
	15: "WS200 (ID15)", 16: "PR-3000 (ID16)",
}

const COLORES := {
	2: "#222222", 6: "#e6194b", 5: "#3cb44b", 4: "#4363d8", 7: "#f58231",
	8: "#911eb4", 9: "#008080", 15: "#9a6324", 16: "#808000",
}

# Estado
var dir_registros: String = ""
var archivo: String = ""
var inicio_texto: String = ""
var t0_unix: float = 0.0
var t_min := PackedFloat32Array()
var series: Dictionary = {}
var duracion: float = 0.0

var minuto: float = 0.0
var reproduciendo: bool = false
var velocidad: float = 60.0

# Modo en vivo (lecturas que llegan del puente Python)
var en_vivo: bool = false
var seguir_vivo: bool = true      # el cursor sigue a la ultima lectura
var _ult_ts: float = -INF
var _t_inicio_vivo_ms: int = 0
var _ultimo_ok_ms: Dictionary = {}    # id -> instante (ms del PC) de su ultima lectura valida
var _llegadas_ms: Array[int] = []     # instantes de llegada de los ultimos ciclos

var corregir: bool = false:
	set(v):
		if corregir != v:
			corregir = v
			correccion_cambiada.emit(v)


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(ARCHIVO_CONFIG) == OK:
		dir_registros = str(cfg.get_value("registros", "carpeta", ""))


# ======================================================================
#  CARGA DE ARCHIVOS CSV
# ======================================================================
func cargar_csv(ruta: String) -> bool:
	reproduciendo = false
	var f := FileAccess.open(ruta, FileAccess.READ)
	if f == null:
		return _fallo("No pude abrir '%s' (error %d)" % [ruta, FileAccess.get_open_error()])

	var cab := f.get_csv_line()
	if cab.size() > 0:
		cab[0] = cab[0].trim_prefix("\ufeff")

	var col_fecha := -1
	var cols := {}
	var re := RegEx.new()
	re.compile("^ID(\\d+)_r(\\d+)$")

	for i in cab.size():
		var col_nom := cab[i].strip_edges()
		if col_nom.to_lower() == "fecha":
			col_fecha = i
			continue
		var m := re.search(col_nom)
		if m:
			var id := int(m.get_string(1))
			var r := int(m.get_string(2))
			if not cols.has(id):
				cols[id] = {}
			cols[id][r] = i

	if col_fecha < 0:
		return _fallo("El archivo no tiene columna 'Fecha'.")
	if cols.is_empty():
		return _fallo("No se encontraron columnas de sensores tipo IDn_r1.")

	var tmp := {}
	for id in cols.keys():
		tmp[id] = {"T": [], "H": [], "P": [], "V": [], "N": [], "a": [], "b": []}

	var seg: Array = []
	var t0 := NAN
	var ult := -INF
	var descartadas := 0
	var primera_fecha := ""

	while not f.eof_reached():
		var c := f.get_csv_line()
		if c.size() < 2:
			continue
		
		var txt: String = c[col_fecha] if col_fecha < c.size() else ""
		var ts := _a_segundos(txt)
		if is_nan(ts) or ts <= ult:
			descartadas += 1
			continue
		if is_nan(t0):
			t0 = ts
			primera_fecha = txt.strip_edges()

		ult = ts
		seg.append(ts - t0)

		for id in cols.keys():
			var cc: Dictionary = cols[id]
			var r1 := _num(c, cc.get(1, -1))
			var r2 := _num(c, cc.get(2, -1))
			var r3 := _num(c, cc.get(3, -1))
			var d: Dictionary = tmp[id]

			_decodificar(d, id, r1, r2, r3)
	f.close()

	if seg.size() < 2:
		return _fallo("Muy pocas lecturas válidas (%d)." % seg.size())

	# Construcción de series empacadas + pre-cálculo de arrays corregidos
	var nueva := {}
	for id in tmp.keys():
		var tipo := _tipo_de(id)
		
		var arr_T := PackedFloat32Array(tmp[id]["T"])
		var dict_sensor := {
			"tipo": tipo,
			"T": arr_T,
			"H": PackedFloat32Array(tmp[id]["H"]),
			"P": PackedFloat32Array(tmp[id]["P"]),
			"V": PackedFloat32Array(tmp[id]["V"]),
			"N": PackedFloat32Array(tmp[id]["N"]),
			"a": PackedFloat32Array(tmp[id]["a"]),
			"b": PackedFloat32Array(tmp[id]["b"]),
		}
		
		# Pre-cálculo de la serie corregida: evita clonar arrays en cada cuadro
		if OFFSETS.has(id) and not arr_T.is_empty():
			var arr_corr := arr_T.duplicate()
			var off: float = OFFSETS[id]
			for idx in arr_corr.size():
				arr_corr[idx] += off
			dict_sensor["T_corr"] = arr_corr

		nueva[id] = dict_sensor

	series = nueva
	t_min = PackedFloat32Array()
	for s in seg:
		t_min.append(s / 60.0)

	duracion = t_min[t_min.size() - 1]
	archivo = ruta
	inicio_texto = primera_fecha
	minuto = 0.0
	t0_unix = t0

	var info := resumen()
	info["descartadas"] = descartadas
	print("[DATOS] Cargado '%s': %d lecturas en %.1f min (IDs %s)" % [
		ruta.get_file(), info["n"], info["duracion"], str(series.keys())])
	
	_guardar_copia(ruta)
	datos_cargados.emit(info)
	minuto_cambiado.emit(minuto)
	return true


# Convierte los registros crudos de UN sensor en las series (T, H, P, V...).
# Lo usan igual el CSV y el modo en vivo: la regla de cada ID vive solo aqui.
func _decodificar(d: Dictionary, id: int, r1: float, r2: float, r3: float) -> void:
	if id in VIENTO:
		d["V"].append(r1 / 10.0)
		d["N"].append(r2)
	elif id in INVALIDOS:
		d["a"].append(r1)
		d["b"].append(r2)
	elif id in INVERTIDOS:
		d["T"].append(r1 / 10.0)
		d["H"].append(r2 / 10.0)
	else:
		d["H"].append(r1 / 10.0)
		d["T"].append(r2 / 10.0)
		if id == AIRE:
			d["P"].append(r3)


func _tipo_de(id: int) -> String:
	if id == AIRE: return "aire"
	if id in VIENTO: return "viento"
	if id in INVALIDOS: return "invalido"
	return "sonda"


func _fallo(msg: String) -> bool:
	push_warning("[DATOS] " + msg)
	carga_fallida.emit(msg)
	return false


func _num(c: PackedStringArray, idx: int) -> float:
	if idx < 0 or idx >= c.size():
		return NAN
	var s := c[idx].strip_edges()
	return NAN if (s == "" or s.to_lower() == "nan") else s.to_float()


func _a_segundos(txt: String) -> float:
	var p := txt.strip_edges().replace("T", " ").split(" ", false)
	if p.size() < 2: return NAN
	var d := p[0].split("-")
	var h := p[1].split(":")
	if d.size() < 3 or h.size() < 2: return NAN
	var sec: float = float(h[2]) if h.size() > 2 else 0.0
	var dic := {
		"year": int(d[0]), "month": int(d[1]), "day": int(d[2]),
		"hour": int(h[0]), "minute": int(h[1]), "second": int(sec)
	}
	return float(Time.get_unix_time_from_datetime_dict(dic)) + (sec - floorf(sec))


# ======================================================================
#  CONSULTAS Y ACCESOS RÁPIDOS
# ======================================================================
func hay_datos() -> bool:
	return not t_min.is_empty()

func nombre(id: int) -> String:
	return NOMBRES.get(id, "ID%d" % id)

func color_de(id: int) -> Color:
	return Color.html(COLORES.get(id, "#888888"))

func ids_termo() -> Array:
	var r: Array = []
	for id in ORDEN_UI:
		if series.has(id): r.append(id)
	for id in series.keys():
		if series[id]["tipo"] in ["sonda", "aire"] and not (id in r):
			r.append(id)
	return r

func ids_viento() -> Array:
	var r: Array = []
	for id in series.keys():
		if series[id]["tipo"] == "viento": r.append(id)
	r.sort()
	return r


# Retorno instantáneo de la serie sin clonación de memoria
func serie(id: int, campo: String) -> PackedFloat32Array:
	if not series.has(id):
		return PackedFloat32Array()
	var s: Dictionary = series[id]
	if campo == "T" and corregir and s.has("T_corr"):
		return s["T_corr"]
	return s.get(campo, PackedFloat32Array())


func _idx(m: float) -> int:
	var a := 0
	var b := t_min.size() - 1
	while a < b:
		var c := (a + b) >> 1
		if t_min[c] < m:
			a = c + 1
		else:
			b = c
	return a


func _interp(arr: PackedFloat32Array, m: float) -> float:
	var n := arr.size()
	if n == 0: return NAN
	if n < 2: return arr[0]
	var i := clampi(maxi(1, _idx(m)), 1, n - 1)
	var dt := maxf(t_min[i] - t_min[i - 1], 0.000001)
	var u := clampf((m - t_min[i - 1]) / dt, 0.0, 1.0)
	var a := arr[i - 1]
	var b := arr[i]
	return (a if u < 0.5 else b) if (is_nan(a) or is_nan(b)) else lerpf(a, b, u)


# Igual que _interp, pero en vivo y en la ultima lectura: si el sensor no respondio en este
# ciclo se mantiene su ultimo valor hasta que se refresque o pase demasiado tiempo (SIN_SENAL).
func _interp_vivo(arr: PackedFloat32Array, m: float, id: int) -> float:
	var v := _interp(arr, m)
	if not is_nan(v) or not en_vivo or m < duracion - 0.0001:
		return v
	var est: int = estado_sensor(id)
	if est != Estado.EN_VIVO and est != Estado.RETENIDO:
		return v
	var i := arr.size() - 1
	var tope := maxi(0, arr.size() - 60)
	while i >= tope:
		if not is_nan(arr[i]):
			return arr[i]
		i -= 1
	return v


# Segundos entre ciclos completos, medidos con el reloj del PC (0 si aun no hay dos ciclos)
func ciclo_vivo_s() -> float:
	var n := _llegadas_ms.size()
	if n < 2:
		return 0.0
	return float(_llegadas_ms[n - 1] - _llegadas_ms[0]) / 1000.0 / float(n - 1)


# Segundos desde la ultima lectura valida del sensor (INF si aun no llego ninguna)
func edad_s(id: int) -> float:
	if not _ultimo_ok_ms.has(id):
		return INF
	return float(Time.get_ticks_msec() - int(_ultimo_ok_ms[id])) / 1000.0


func estado_sensor(id: int) -> int:
	if not en_vivo:
		return Estado.REGISTRO
	var edad := edad_s(id)
	if is_inf(edad):
		var espera := float(Time.get_ticks_msec() - _t_inicio_vivo_ms) / 1000.0
		return Estado.ESPERANDO if espera < ESPERA_INICIAL_S else Estado.SIN_SENAL
	var ciclo := ciclo_vivo_s()
	if edad <= maxf(FRESCO_MIN_S, 1.5 * ciclo):
		return Estado.EN_VIVO
	if edad <= maxf(RETENER_MIN_S, 3.0 * ciclo):
		return Estado.RETENIDO
	return Estado.SIN_SENAL


func valor(id: int, m: float) -> Dictionary:
	if not series.has(id):
		return {"T": NAN, "H": NAN}
	var s: Dictionary = series[id]
	var t_arr: PackedFloat32Array = s["T_corr"] if (corregir and s.has("T_corr")) else s["T"]
	return {"T": _interp_vivo(t_arr, m, id), "H": _interp_vivo(s["H"], m, id)}


func viento(id: int, m: float) -> float:
	return _interp_vivo(series[id]["V"], m, id) if series.has(id) else NAN

func presion(m: float) -> float:
	return _interp_vivo(series[AIRE]["P"], m, AIRE) if series.has(AIRE) else NAN

func delta_vs_aire(id: int, m: float) -> float:
	return valor(id, m)["T"] - valor(AIRE, m)["T"]

func punto_rocio(t: float, h: float) -> float:
	if is_nan(t) or is_nan(h) or h <= 0.0:
		return NAN
	var g := log(h / 100.0) + 17.62 * t / (243.12 + t)
	return 243.12 * g / (17.62 - g)

func en_alarma(t: float, h: float) -> bool:
	return is_nan(t) or is_nan(h) or t < T_MIN or t > T_MAX or h < H_MIN or h > H_MAX


func instante(m: float) -> Dictionary:
	var d := Time.get_datetime_dict_from_unix_time(int(t0_unix + m * 60.0))
	return {
		"doy": Clima.dia_del_anio(int(d["year"]), int(d["month"]), int(d["day"])),
		"hora": float(d["hour"]) + float(d["minute"]) / 60.0 + float(d["second"]) / 3600.0,
		"fecha": "%02d/%02d/%04d" % [d["day"], d["month"], d["year"]],
		"iso": "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]],
	}


func lecturas_ok(id: int) -> int:
	if not series.has(id): return 0
	var tipo: String = series[id]["tipo"]
	if tipo == "invalido": return t_min.size()
	var arr: PackedFloat32Array = series[id]["V"] if tipo == "viento" else series[id]["T"]
	var k := 0
	for v in arr:
		if not is_nan(v): k += 1
	return k


func resumen() -> Dictionary:
	var n := t_min.size()
	var suma := 0.0
	var mayor := 0.0
	for i in range(1, n):
		var g := (t_min[i] - t_min[i - 1]) * 60.0
		suma += g
		mayor = maxf(mayor, g)
	return {
		"archivo": archivo, "inicio": inicio_texto, "n": n, "duracion": duracion,
		"ciclo_medio": suma / maxf(n - 1, 1), "hueco_max": mayor, "ids": series.keys(),
	}


# ======================================================================
#  REPRODUCCIÓN Y CONTROL DE SIMULACIÓN
# ======================================================================
func _process(delta: float) -> void:
	if not reproduciendo or t_min.is_empty():
		return
	set_minuto(minuto + delta * velocidad / 60.0)
	if minuto >= duracion:
		reproduciendo = false
		reproduccion_cambiada.emit(false)

func set_minuto(m: float) -> void:
	minuto = clampf(m, 0.0, duracion)
	if en_vivo:
		seguir_vivo = minuto >= duracion - 0.05
	minuto_cambiado.emit(minuto)

func reproducir() -> void:
	if t_min.is_empty(): return
	if minuto >= duracion - 0.001: minuto = 0.0
	reproduciendo = true
	reproduccion_cambiada.emit(true)

func pausar() -> void:
	reproduciendo = false
	reproduccion_cambiada.emit(false)

func alternar() -> void:
	if reproduciendo: pausar()
	else: reproducir()

func reiniciar() -> void:
	pausar()
	set_minuto(0.0)


# ======================================================================
#  GESTIÓN DE ARCHIVOS Y RUTAS
# ======================================================================
func carpeta_registros() -> String:
	if dir_registros != "" and DirAccess.dir_exists_absolute(dir_registros):
		return dir_registros
	return ProjectSettings.globalize_path(DIR_REGISTROS)

func set_carpeta_registros(ruta: String) -> void:
	dir_registros = ruta
	var cfg := ConfigFile.new()
	cfg.set_value("registros", "carpeta", ruta)
	cfg.save(ARCHIVO_CONFIG)

func _guardar_copia(ruta: String) -> void:
	if ruta.begins_with("res://"): 
		return
	var carpeta := carpeta_registros()
	var ya_guardado := ruta.begins_with("user://") or ruta.replace("\\", "/").begins_with(carpeta.replace("\\", "/"))
	var destino := ruta
	
	if not ya_guardado:
		DirAccess.make_dir_recursive_absolute(carpeta)
		# Guarda con el nombre limpio sin el sello largo de hora (evita duplicados)
		destino = "%s/%s" % [carpeta, ruta.get_file()]
		if DirAccess.copy_absolute(ruta, destino) != OK:
			return

	var f := FileAccess.open(ARCHIVO_ULTIMO, FileAccess.WRITE)
	if f != null:
		f.store_string(destino)

func ultimo_registro() -> String:
	if not FileAccess.file_exists(ARCHIVO_ULTIMO): return ""
	var r := FileAccess.get_file_as_string(ARCHIVO_ULTIMO).strip_edges()
	return r if FileAccess.file_exists(r) else ""


# ======================================================================
#  MODO EN VIVO (lecturas que llegan del puente Python)
# ======================================================================
func iniciar_vivo() -> void:
	reproduciendo = false
	series = {}
	t_min = PackedFloat32Array()
	duracion = 0.0
	minuto = 0.0
	t0_unix = 0.0
	inicio_texto = ""
	archivo = "(en vivo)"
	_ult_ts = -INF
	_t_inicio_vivo_ms = Time.get_ticks_msec()
	_ultimo_ok_ms = {}
	_llegadas_ms = []
	seguir_vivo = true
	en_vivo = true
	modo_vivo_cambiado.emit(true)


func terminar_vivo() -> void:
	if not en_vivo:
		return
	en_vivo = false
	modo_vivo_cambiado.emit(false)
	if hay_datos():
		datos_cargados.emit(resumen())      # la sesion queda disponible para revisarla


# msg = {"t": "2026-10-23 09:28:53.412", "ids": {"2": [521,348,1009], "9": null, ...}}
# Los registros llegan CRUDOS (T y HR x10); null = el sensor no respondio.
func agregar_lectura(msg: Dictionary) -> bool:
	if not en_vivo:
		iniciar_vivo()
	var ids = msg.get("ids", null)
	if typeof(ids) != TYPE_DICTIONARY:
		return false

	var txt := str(msg.get("t", ""))
	var ts := _a_segundos(txt)
	if is_nan(ts):
		txt = Time.get_datetime_string_from_system(false, true)
		ts = _a_segundos(txt)
	if ts <= _ult_ts:
		return false                        # repetida o fuera de orden
	if t_min.is_empty():
		t0_unix = ts
		inicio_texto = txt
	var n_prev := t_min.size()

	# sensores nuevos: se crean con NaN en las lecturas anteriores
	for k in ids.keys():
		var id := int(k)
		if not series.has(id):
			series[id] = _nuevo_sensor(id)
			for i in n_prev:
				_agregar_a(id, NAN, NAN, NAN)

	# una lectura por cada sensor conocido (los que faltan en el mensaje, NaN)
	var ahora_ms: int = Time.get_ticks_msec()
	for id in series.keys():
		var regs = ids.get(str(id), null)
		var r1 := NAN
		var r2 := NAN
		var r3 := NAN
		if typeof(regs) == TYPE_ARRAY:
			if regs.size() > 0 and regs[0] != null: r1 = float(regs[0])
			if regs.size() > 1 and regs[1] != null: r2 = float(regs[1])
			if regs.size() > 2 and regs[2] != null: r3 = float(regs[2])
		if not (is_nan(r1) and is_nan(r2) and is_nan(r3)):
			_ultimo_ok_ms[id] = ahora_ms
		_agregar_a(id, r1, r2, r3)
	_llegadas_ms.append(ahora_ms)
	if _llegadas_ms.size() > 8:
		_llegadas_ms.pop_front()

	t_min.append((ts - t0_unix) / 60.0)
	_ult_ts = ts
	duracion = t_min[t_min.size() - 1]
	if seguir_vivo:
		minuto = duracion
		minuto_cambiado.emit(minuto)
	lectura_agregada.emit(duracion)
	return true


func _nuevo_sensor(id: int) -> Dictionary:
	var s := {
		"tipo": _tipo_de(id),
		"T": PackedFloat32Array(), "H": PackedFloat32Array(), "P": PackedFloat32Array(),
		"V": PackedFloat32Array(), "N": PackedFloat32Array(),
		"a": PackedFloat32Array(), "b": PackedFloat32Array(),
	}
	if OFFSETS.has(id):
		s["T_corr"] = PackedFloat32Array()
	return s


func _agregar_a(id: int, r1: float, r2: float, r3: float) -> void:
	var s: Dictionary = series[id]
	_decodificar(s, id, r1, r2, r3)
	if s.has("T_corr"):
		var t: PackedFloat32Array = s["T"]
		s["T_corr"].append(t[t.size() - 1] + float(OFFSETS[id]))
