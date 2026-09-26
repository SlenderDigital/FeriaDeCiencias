class_name PatternLanguage
extends RefCounted
## PatternLanguage — la coherencia visual de los patrones (T9).
##
## El problema reportado: "no hay coherencia entre los tipos de enemigos".
## Ocho patrones con ocho Aspectos distintos hacen ruido. JSAB resuelve esto
## con una JERARQUÍA: todo lo letal es rojo/blanco HDR, y cada patrón se
## diferencia por SILUETA (forma), no por color. El jugadorAprende a leer
## "líneas radiales = hay rayo" sin tener que pensar en el color.
##
## Este archivo es la fuente de verdad de esa jerarquía: cada patrón declara
## a qué familia visual pertenece, qué silueta tiene y cuán lethality es.

enum Family { AMBER, RADIAL, ARC, FIELD, CORRIDOR }

## Una entrada por patrón: familia, nombre legible y lethality (0.5-1.0).
## La lethality ordena el DIBUJO (lo más letal se dibuja encima) y el golpe.
const REGISTRY: Dictionary = {
	"spoke_fan":        {"family": Family.RADIAL,   "name": "abanico",      "lethality": 1.0,  "silhouette": "radial"},
	"mini_fan":         {"family": Family.RADIAL,   "name": "latido radial", "lethality": 0.45, "silhouette": "radial"},
	"pulse_rings":      {"family": Family.RADIAL,   "name": "anillos",      "lethality": 0.9,  "silhouette": "arc"},
	"mini_ring":        {"family": Family.RADIAL,   "name": "latido anillo","lethality": 0.4,  "silhouette": "arc"},
	"laser_sweep":      {"family": Family.ARC,      "name": "barrido",      "lethality": 0.95, "silhouette": "beam"},
	"stripe_wall":      {"family": Family.FIELD,    "name": "muro",         "lethality": 1.0,  "silhouette": "band"},
	"waveform_wall":    {"family": Family.FIELD,    "name": "onda",         "lethality": 0.95, "silhouette": "wave"},
	"squeeze_corridor": {"family": Family.CORRIDOR, "name": "corredor",     "lethality": 0.9,  "silhouette": "pinch"},
	"saw":              {"family": Family.AMBER,    "name": "sierra",       "lethality": 0.5,  "silhouette": "gear"},
	"saw_pair":         {"family": Family.AMBER,    "name": " sierras",     "lethality": 0.6,  "silhouette": "gear"},
	"saw_weave":        {"family": Family.AMBER,    "name": "tejido",       "lethality": 0.7,  "silhouette": "gear"},
	"homing":           {"family": Family.AMBER,    "name": "misil",        "lethality": 0.65, "silhouette": "missile"},
	"drifter":          {"family": Family.AMBER,    "name": "deriva",       "lethality": 0.4,  "silhouette": "dot"},
	"drifter_swarm":    {"family": Family.AMBER,    "name": "enjambre",     "lethality": 0.55, "silhouette": "dot"},
	"perimeter":        {"family": Family.AMBER,    "name": "perímetro",    "lethality": 0.5,  "silhouette": "gear"},
	"closing_perimeter":{"family": Family.AMBER,    "name": "cierre",       "lethality": 0.7,  "silhouette": "gear"},
	"laser_telegraph":  {"family": Family.ARC,      "name": "aviso láser",  "lethality": 0.2,  "silhouette": "beam"},
	"laser_beam":       {"family": Family.ARC,      "name": "haz",          "lethality": 0.9,  "silhouette": "beam"},
}

static func family_of(type_name: String) -> int:
	return int(REGISTRY.get(type_name, {}).get("family", Family.AMBER))

static func lethality_of(type_name: String) -> float:
	return float(REGISTRY.get(type_name, {}).get("lethality", 0.5))

static func display_name(type_name: String) -> String:
	return str(REGISTRY.get(type_name, {}).get("name", type_name))

## Orden de dibujo: menos letal ANTES, más letal DESPUÉS (encima). El jugador
## siempre ve lo que lo mata. Godot 4 tiene Array.sort_custom.
static func draw_sort(a: Dictionary, b: Dictionary) -> bool:
	return lethality_of(str(a.get("type", ""))) < lethality_of(str(b.get("type", "")))
