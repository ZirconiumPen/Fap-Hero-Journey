extends Control

# Child of GraphView. Holds the auto-laid-out node widgets as children, and
# draws the edges that connect them via _draw(). Pan/zoom transform is applied
# by the parent GraphView to this control's position + scale, so node positions
# and edge coordinates share the same canvas-local space.

# Edges: list of { from: Vector2, to: Vector2, color: Color }
var edges: Array = []


func set_edges(e: Array) -> void:
	edges = e
	queue_redraw()


func _draw() -> void:
	for e in edges:
		var from: Vector2 = e["from"]
		var to:   Vector2 = e["to"]
		var color: Color  = e["color"]
		var mid_y: float = (from.y + to.y) * 0.5
		var p2: Vector2 = Vector2(from.x, mid_y)
		var p3: Vector2 = Vector2(to.x,   mid_y)
		draw_line(from, p2, color, 2.0, true)
		draw_line(p2,   p3, color, 2.0, true)
		draw_line(p3,   to, color, 2.0, true)
		# Small arrowhead at the destination.
		var a: float = 6.0
		draw_line(to, to + Vector2(-a, -a), color, 2.0, true)
		draw_line(to, to + Vector2( a, -a), color, 2.0, true)
