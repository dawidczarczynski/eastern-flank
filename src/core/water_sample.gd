class_name WaterSample
extends RefCounted
## What WaterValidator (TASK-223a) reads: the rivers, lakes and bridges of a map in one small,
## source-independent shape. Today an adapter fills it from the ribbon planner and RiverChannel
## (WaterSampleAdapter); TASK-223c feeds it from `WaterNetwork` instead. Positions are world XZ
## (units of MapScale), widths and heights are metres.


## One river reach, vertices ordered downstream (the surface may only fall along it).
class Reach:
	extends RefCounted
	var points := PackedVector2Array()
	## Whole water width in metres per vertex.
	var width_m := PackedFloat32Array()
	## Water surface height in metres per vertex.
	var level := PackedFloat32Array()


var reaches: Array[Reach] = []
## Callable(x: float, z: float) -> float: ground height in metres as it is drawn (channel dug in).
var ground := Callable()
## Callable(p: Vector2) -> float: the surface height in metres of the lake at `p`, NAN when `p` is
## not on a lake. Empty = no lakes.
var lake_at := Callable()
## Bridges: {position: Vector2, span_m: float}.
var bridges: Array[Dictionary] = []
