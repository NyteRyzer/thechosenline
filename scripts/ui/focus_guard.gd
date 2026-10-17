extends RefCounted
## Temporarily removes keyboard focus from controls behind a modal panel so
## Tab and arrow navigation stay inside the panel.


## Disables focus on every Control under `root` except the `keep` subtree.
## Returns the list to pass to restore().
static func suspend(root: Node, keep: Node) -> Array:
	var suspended: Array = []
	_collect(root, keep, suspended)
	return suspended


static func restore(suspended: Array) -> void:
	for entry in suspended:
		if is_instance_valid(entry[0]):
			entry[0].focus_mode = entry[1]
	suspended.clear()


static func _collect(node: Node, keep: Node, out: Array) -> void:
	for child in node.get_children():
		if child == keep:
			continue
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			out.append([child, child.focus_mode])
			child.focus_mode = Control.FOCUS_NONE
		_collect(child, keep, out)
