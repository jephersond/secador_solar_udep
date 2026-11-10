class_name ClimaExterior
extends Node

# ======================================================================
#  clima_exterior.gd - Clima exterior (estimado Open-Meteo)
#  Almacena curvas de 24h y resuelve interpolación con Clima.
# ======================================================================

const CLAVES: Array[String] = ["temp", "hr", "viento", "pres", "rad"]

var clima: Clima
var fecha_iso: String = ""
var fuente: String = ""

var _curvas: Dictionary = {}
var _cache_fecha_in: String = ""
var _cache_fecha_out: String = ""


func recibir(datos: Dictionary) -> void:
	# 1. Filtro estricto: ignorar paquetes cruzados según el modo actual
	var tipo: String = str(datos.get("tipo", ""))
	if clima != null:
		if clima.modo_actual == Clima.Modo.REGISTRO and tipo == "en_vivo":
			return
		if clima.modo_actual == Clima.Modo.AUTO and tipo == "historico":
			return

	var nueva_fecha := str(datos.get("fecha", ""))
	if nueva_fecha == "":
		return
	
	if clima != null and clima.fecha_txt != "" and _fecha_a_iso(clima.fecha_txt) != nueva_fecha:
		return
	
	var nuevas: Dictionary = {}
	for c: String in CLAVES:
		var k: String = "curva_" + c
		if datos.has(k) and datos[k] is Array and (datos[k] as Array).size() >= 24:
			nuevas[c] = datos[k]

	if nuevas.is_empty():
		return

	var cambio := nueva_fecha != fecha_iso or _curvas.is_empty()
	_curvas = nuevas
	fecha_iso = nueva_fecha
	fuente = str(datos.get("fuente", ""))

	if cambio:
		print("[EXTERIOR] Curvas fijadas para %s (%s)" % [fecha_iso, fuente])


func hay_datos() -> bool:
	return not _curvas.is_empty()


func _fecha_a_iso(fecha_txt: String) -> String:
	if fecha_txt == _cache_fecha_in:
		return _cache_fecha_out
	var p := fecha_txt.split("/")
	if p.size() != 3:
		return ""
	_cache_fecha_in = fecha_txt
	_cache_fecha_out = "%s-%s-%s" % [p[2], p[1], p[0]]
	return _cache_fecha_out


func valor(clave: String, hora: float, fecha_txt: String) -> float:
	if not _curvas.has(clave) or fecha_iso == "":
		return NAN

	if _fecha_a_iso(fecha_txt) != fecha_iso:
		return NAN

	var x: float = hora + (0.5 if clave == "rad" else 0.0)
	return Clima.interpolar_curva_24h(_curvas[clave], x)
