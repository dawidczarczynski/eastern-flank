class_name AudioSalvoEffects
extends SalvoEffects
## Sound of a rocket salvo (TASK-123): one launch sound per rocket at its tube and an explosion
## where it lands, on top of the visual effects `inner` (SalvoFxPool or the empty base class),
## which still get every hook.

## Rockets launch a little apart (index mod 3 steps of this many seconds): no single hard attack.
const STAGGER := 0.05

var _inner: SalvoEffects
var _director: AudioDirector
var _fire_id: StringName
var _damage: int


func _init(
	inner: SalvoEffects, director: AudioDirector, shooter: UnitDefinition, damage: int
) -> void:
	_inner = inner if inner != null else SalvoEffects.new()
	_director = director
	_fire_id = SoundPlanner.fire_sound(shooter)
	_damage = damage


func begin(context: Dictionary) -> void:
	_inner.begin(context)


func on_launch(index: int, mouth: Vector3, tube_dir: Vector3) -> void:
	_inner.on_launch(index, mouth, tube_dir)
	_director.play_at_later(_fire_id, mouth, STAGGER * float(index % 3))


func on_flight(index: int, from: Vector3, to: Vector3, s: float, motor: bool) -> void:
	_inner.on_flight(index, from, to, s, motor)


func on_impact(index: int, point: Vector3, first: bool, last: bool) -> void:
	_inner.on_impact(index, point, first, last)
	_director.play_at(
		SoundPlanner.EXPLOSION_ROCKET, point, SoundPlanner.impact_gain_db(_damage, true)
	)


func end(target_centre: Vector3) -> void:
	_inner.end(target_centre)
