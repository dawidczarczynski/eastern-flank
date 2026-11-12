class_name StrikeWeaponLook
extends Resource
## How one strike weapon looks on the staff map (TASK-141b): its glyph, the colour shade, speed and
## arc of its trace and the burst of its warhead. Presentation data kept as
## data/strike/looks/<means_id>.tres, apart from the core StrikeMeansDefinition (rule 3: the view
## reads the means, the core never reads a look). Values are [ASSUMPTION]s to be tuned in play.

const DIR := "res://data/strike/looks/"
const GLYPHS: Array[StringName] = [&"missile", &"ballistic", &"drone", &"rocket", &"loitering"]
const WARHEADS: Array[StringName] = [&"blast", &"heavy_blast", &"small", &"cluster"]
const ARC_MIN := 0.02
const ARC_MAX := 0.45
## Flight time limits (s): slow enough to follow a missile by eye (TASK-147 playtest).
const DURATION_MIN := 1.2
const DURATION_MAX := 4.0

## One of GLYPHS (StaffMapWeaponGlyph draws it).
@export var glyph: StringName = &"missile"
## Shade of the trace: the striker's side colour is mixed towards this colour by its alpha
## (alpha 0 = the plain side colour, 1 = this colour), so the palette stays the side's.
@export var trail_color: Color = Color(1, 1, 1, 0.0)
## Flight speed in hexes per second; the duration is distance / speed, clamped DURATION_MIN .. MAX.
@export_range(1.0, 1000.0) var speed_hexes_per_s: float = 12.0
## Height of the arc's apex as a fraction of the flight distance.
@export_range(0.02, 0.45) var arc_height: float = 0.03
## Sideways wobble of the flight, 0 (straight) to 1 (drones).
@export_range(0.0, 1.0) var wobble: float = 0.0
## Share of the path (0 – 1) that is drawn bright behind the head while the missile flies.
@export_range(0.0, 1.0) var trail_length: float = 0.5
## Draw the trace as dots instead of a solid line.
@export var dotted := false
## One of WARHEADS: the burst of a hit.
@export var warhead: StringName = &"blast"
## Scale of the burst (1 = the standard blast).
@export_range(0.3, 2.0) var burst_scale: float = 1.0


## The look of the weapon (data/strike/looks/<means_id>.tres) or the default look when it has no
## file, so a weapon of a hand-made test state still draws.
static func for_means(means_id: StringName) -> StrikeWeaponLook:
	var file_name := String(means_id)
	if file_name != "" and file_name.is_valid_filename() and not file_name.contains("."):
		var path := DIR + file_name + ".tres"
		if ResourceLoader.exists(path):
			var look := load(path) as StrikeWeaponLook
			if look != null:
				return look
	return StrikeWeaponLook.new()


## "" when every value is in range, else the first problem.
func problem() -> String:
	if not GLYPHS.has(glyph):
		return "unknown glyph '%s'" % glyph
	if not WARHEADS.has(warhead):
		return "unknown warhead '%s'" % warhead
	if arc_height < ARC_MIN or arc_height > ARC_MAX:
		return "arc_height %.2f outside %.2f .. %.2f" % [arc_height, ARC_MIN, ARC_MAX]
	if wobble < 0.0 or wobble > 1.0 or trail_length < 0.0 or trail_length > 1.0:
		return "wobble and trail_length must be 0 .. 1"
	if speed_hexes_per_s <= 0.0 or burst_scale <= 0.0:
		return "speed_hexes_per_s and burst_scale must be positive"
	return ""


## Flight time of a missile over `distance_hexes`.
func duration(distance_hexes: float) -> float:
	return clampf(distance_hexes / speed_hexes_per_s, DURATION_MIN, DURATION_MAX)


## The trace colour for a striker's side colour.
func shade(side_colour: Color) -> Color:
	var mixed := side_colour.lerp(Color(trail_color, 1.0), trail_color.a)
	return Color(mixed, side_colour.a)
