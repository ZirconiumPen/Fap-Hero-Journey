extends Node

const MONTHS: Array = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]


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


# ISO datetime ("2026-06-12T14:30:25" to "Jun 12").
# Falls back to the raw date portion if parsing fails.
func format_short_date(iso: String) -> String:
	if iso.is_empty():
		return ""
	var dt: Dictionary = Time.get_datetime_dict_from_datetime_string(iso, false)
	var month: int = int(dt.get("month", 0))
	var day: int = int(dt.get("day", 0))
	if month <= 0 or month > 12 or day <= 0:
		return iso.split("T")[0]
	return "%s %d" % [MONTHS[month - 1], day]
