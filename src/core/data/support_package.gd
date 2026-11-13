class_name SupportPackage
extends Resource
## One package of outside support (TASK-121, GDD "Outside support"), a sub-resource of
## OperationDefinition.support_packages: what a supporter sends to a side, when it is available,
## what asking for it costs and how late it arrives. Effects: `formations` (TASK-122 adds means).

@export var id: StringName
## Translation key (English).
@export var display_name: String
@export var supporter: SupporterDefinition
## The recipient side (player index); equals the supporter's side.
@export var side: int = 0
## Escalation levels (inclusive) at which the package can be requested.
@export var min_level: int = 0
@export var max_level: int = 0
## The requester's net escalation caused (caused - deescalated) may be at most this; -1 = no limit.
@export var max_caused: int = -1
## Packages of the other side; once one of them is requested this package is free and ignores the
## level, record and cost conditions.
@export var response_to: Array[StringName] = []
## Escalation steps the request costs (cause `support_request`).
@export var escalation_cost: int = 0
## Formations delivered into a country aligned with the recipient give the other side a casus belli.
@export var entry_casus_belli: bool = false
## Turns between the request and the delivery.
@export var delay_turns: int = 0
## The conditions are checked again at delivery; unmet, the package is withdrawn.
@export var withdraw_if_unmet: bool = false
## Formations that arrive; `coord` is the entry hex, `player` the side.
@export var formations: Array[FormationPlacement] = []
