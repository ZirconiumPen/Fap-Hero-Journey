class_name Modal
extends Control

const ModalScene = preload("uid://c6jif1ka1bf81")

@onready var panel_container: PanelContainer = %PanelContainer
@onready var content: Container = %Content
@onready var title_label: Label = %TitleLabel


static func generate(title: String, min_size := Vector2(720, 520)) -> Modal:
	var out: Modal = ModalScene.instantiate()
	out.title_label.text = title
	out.panel_container.custom_minimum_size = min_size
	return out
