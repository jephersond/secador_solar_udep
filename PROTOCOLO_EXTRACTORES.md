# Protocolo de control de extractores (Godot -> ESP32)

Texto plano por el mismo USB serial (115200), una orden por línea terminada en `\n`.
El ESP32 **decide y tiene la última palabra**; Godot solo manda modo y límites.
`1` y `2` son los dos dimmers. Temperaturas en °C con punto decimal.

## Órdenes (PC -> ESP32)

| Orden | Significado |
|---|---|
| `X1 MODO OFF` | Extractor 1 apagado |
| `X1 MODO ON` | Encendido manual (ángulo que ya use el firmware) |
| `X1 MODO AUTO` | Automático según fuente y límites |
| `X1 FUENTE EXT` | En auto decide la temperatura del extractor |
| `X1 FUENTE AMB` | En auto decide la temperatura ambiente |
| `X1 LIM 35.0 40.0` | En auto: empieza a abrir a 35.0 °C y llega al ángulo máximo a 40.0 °C (equivale a lim1/lim2 actuales) |
| `X?` | Pide el estado de ambos extractores |

Lo mismo con `X2` para el segundo.

## Respuestas (ESP32 -> PC), una línea cada una

- `OK X1 MODO AUTO`: orden aceptada (repetir la orden recibida).
- `ERR <motivo>`: orden rechazada (por ejemplo `ERR limites`).
- Respuesta a `X?` (una línea por extractor):
  `X1: MODO=AUTO FUENTE=AMB LIM=35.0/40.0 ANG=120 ON=1`

Estas líneas deben empezar exactamente con `OK X1`/`OK X2`, `ERR` o `X1:`/`X2:`.
Así el puente las separa de las líneas de datos (`ID2: ... | ID6: ...`), que no cambian.

## Sugerencias para el firmware

- Guardar modo, fuente y límites en `Preferences`, como ya se hace con lim1/lim2.
- Validar `t_on < t_max` y responder `ERR` si no se cumple.
- La pantalla táctil sigue funcionando; la última orden (pantalla o PC) manda.
- Si no llegan órdenes, el ESP32 sigue con lo último configurado.
