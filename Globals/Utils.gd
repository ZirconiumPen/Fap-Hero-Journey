extends Node


func format_duration(total_seconds: int) -> String:
	var h: int = total_seconds / 3600
	var m: int = (total_seconds % 3600) / 60
	var s: int = total_seconds % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%d:%02d" % [m, s]


# Separates by thousands, e.g. 14200 to "14,200".
func format_score(n: int, sep: String = ",") -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = sep + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = ("-" if n < 0 else "") + s + out
	return out
