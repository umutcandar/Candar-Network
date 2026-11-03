extends Node

#Functions for you: show_banner(), hide_banner(), show_interstitial(),
#show_rewarded(), show_rewarded_interstitial().

@export_category("Settings")
@export_enum("G", "PG", "T", "MA") var max_ad_content_rating: String = "G"
@export_category("Allowed Ads")
@export_group("Banner")
@export var enable: bool
@export_enum("Top", "Bottom", "Left", "Right") var position: int
@export var ad_unit_id: String
@export_group("Interstitial")
@export var Enable: bool
@export var Ad_unit_id: String
@export_group("Rewarded")
@export var enable_: bool
@export var ad_unit_id_: String
@export_group("Rewarded Interstitial")
@export var Enable_: bool
@export var Ad_unit_id_: String

signal rewarded_watched
signal rewarded_interstitial_watched

func _ready():
	#BANNER
	if position == 0:
		$banner._on_top_pressed()
	elif position == 1:
		$banner._on_bottom_pressed()
	elif position == 2:
		$banner._on_left_pressed()
	elif position == 3:
		$banner._on_right_pressed()
		
	if enable:
		$banner._on_load_banner_pressed()
		$banner._on_hide_banner_pressed()
		
	#INTERSTITIAL
	if Enable:
		$interstitial._on_load_pressed()
	
	#REWARDED
	if enable_:
		$rewarded._on_load_pressed()
	
	#REWARDED INTERSTITIAL
	if Enable_:
		$rewarded_intertitial._on_load_pressed()

func show_banner():
	$banner._on_show_banner_pressed()

func hide_banner():
	$banner._on_hide_banner_pressed()

func show_interstitial():
	$interstitial._on_show_pressed()

func show_rewarded():
	$rewarded._on_show_pressed()

func show_rewarded_interstitial():
	$rewarded_intertitial._on_show_pressed()
