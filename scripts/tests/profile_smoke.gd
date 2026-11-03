extends SceneTree
var output: String
var render := false
var failures: Array[String] = []
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool, text: String):
 checks += 1
 if not ok: failures.append(text)
func settle():
 for i in range(12): await process_frame
func snap(name: String):
 await settle()
 if render:
  await RenderingServer.frame_post_draw
  var img=root.get_texture().get_image()
  if img.get_width()>1: img.save_png(output+"/"+name+".png")
func new_profile():
 var scene=load("res://profile.tscn").instantiate()
 root.add_child(scene)
 await settle()
 return scene
func run():
 output=OS.get_cmdline_user_args()[0]
 render=OS.get_cmdline_user_args()[1]=="render"
 TranslationServer.set_locale("tr")
 var f=FileAccess.open("user://uid.txt",FileAccess.WRITE)
 f.store_string("qa-profile-user")
 f.close()
 var global=root.get_node("Global")
 var scene=await new_profile()
 check(scene.status_label.is_inside_tree(), "status feedback has a live parent")
 check(scene.stat_candar_v.text=="12345.67", "points rendered from canonical field")
 check(scene.membership_premium_label.text.contains("Süresi doldu"), "expired premium not reported active")
 check(scene.membership_boost_label.text.contains("Aktif değil"), "expired boost not reported active")
 check(not scene.membership_note_label.text.contains("Reklamsız"), "expired ad-free benefit omitted")
 for button in [scene.btn_share,scene.btn_achievements,scene.btn_leader,scene.btn_reset,scene.btn_logout,scene.delete_btn]:
  check(button.size.y>=80, "large touch target: "+button.text)
 await snap("profile-top")
 check(scene.vbox.get_combined_minimum_size().y<=scene.scroll_container.size.y+1, "all profile features fit without scrolling on iPhone layout")
 check(scene.footer.get_global_rect().end.y<=scene.scroll_container.get_global_rect().end.y+1, "footer fits below all actions")
 scene.scroll_container.ensure_control_visible(scene.delete_btn)
 await snap("profile-bottom")
 check(scene.delete_btn.get_global_rect().end.y<=scene.scroll_container.get_global_rect().end.y+1, "delete action is scroll-reachable")
 scene._on_share_pressed()
 await snap("profile-invite")
 check(scene._invite_overlay!=null, "invitation opens")
 check(scene._referral_download_link("CANDAR26").contains("CANDAR26"), "invitation link preserves referral")
 scene._close_invite_sheet()
 scene._open_achievements()
 await snap("profile-achievements")
 check(scene._active_sheet.find_child("foot",true,false).text.begins_with("2/9"), "achievement count matches unlocked catalog")
 scene._close_profile_sheet(scene._active_sheet)
 await settle()
 scene._on_delete_pressed()
 await snap("profile-delete-confirm")
 var actions=scene._active_sheet.find_child("actions",true,false)
 check(actions.get_child_count()==2, "delete asks for explicit confirmation")
 check(actions.get_child(0).size.x>120 and actions.get_child(1).size.x>120, "confirmation actions fill panel width")
 actions.get_child(0).pressed.emit()
 await settle()
 check(global.delete_calls==0, "cancel never deletes account")
 scene._open_leaderboard()
 await create_timer(0.15).timeout
 await snap("profile-leaderboard")
 check(scene._active_sheet.find_child("rt",true,false).text.contains("TOP 25"), "leaderboard result displayed")
 scene._close_profile_sheet(scene._active_sheet)
 await settle()
 # Close before the remote answer arrives; the continuation must not use freed UI.
 scene._open_leaderboard()
 scene._close_profile_sheet(scene._active_sheet)
 await create_timer(0.15).timeout
 scene._on_reset_pressed()
 scene._on_reset_pressed()
 check(global.reset_calls==1, "duplicate password reset request blocked")
 check(scene.btn_logout.disabled, "account navigation blocked during reset")
 await create_timer(0.2).timeout
 check(not scene._account_busy and not scene.btn_reset.disabled, "failed reset releases controls")
 scene._close_profile_sheet(scene._active_sheet)
 scene._do_delete_account()
 scene._do_delete_account()
 check(global.delete_calls==1, "duplicate delete request blocked in fake backend")
 await create_timer(0.2).timeout
 check(scene.status_label.visible and not scene.status_label.text.is_empty(), "delete failure visible")
 check(not scene._account_busy and not scene.delete_btn.disabled, "failed delete can be retried")
 scene._close_profile_sheet(scene._active_sheet)
 global.fail_load=true
 await scene._load_user("qa-profile-user")
 check(scene._retry_button.visible and scene.status_label.visible, "load failure offers retry")
 global.fail_load=false
 await scene._retry_profile_load()
 check(not scene._retry_button.visible and not scene.status_label.visible, "successful retry clears failure")
 # Missing referral code must not reset an active user's full rate to x1.
 global.data.erase("referralCode")
 await scene._load_user("qa-profile-user")
 await scene._compute_rate_and_update_ui()
 check(scene.stat_rate_v.text=="x1.60", "rate remains authoritative without referral code")
 global.data["referralCode"]={"stringValue":"CANDAR26"}
 var future=Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system())+86400)+"Z"
 for key in ["premiumExpiresAt","boostExpiresAt","pointsAdFreeUntil"]: global.data[key]={"timestampValue":future}
 await scene._load_user("qa-profile-user")
 check(scene.membership_premium_label.text.contains("Aktif"), "valid premium displayed")
 check(scene.membership_boost_label.text.contains("x2.00"), "valid boost displayed")
 check(scene.membership_note_label.text.contains("Reklamsız"), "valid ad-free benefit displayed")
 check(scene._mask_email("a@example.com")!="a@example.com", "short email stays masked")
 scene.queue_free()
 await settle()
 for size in [Vector2i(360,780),Vector2i(720,1280),Vector2i(720,1560),Vector2i(1024,1366)]:
  root.content_scale_size=size
  root.size=size/2
  scene=await new_profile()
  await settle()
  check(scene.card_user.get_global_rect().position.x>=0 and scene.card_user.get_global_rect().end.x<=size.x, "profile fits "+str(size))
  check(scene.vbox.get_combined_minimum_size().y<=scene.scroll_container.size.y+1, "all actions fit height "+str(size)+" content="+str(scene.vbox.get_combined_minimum_size().y)+" available="+str(scene.scroll_container.size.y))
  if size in [Vector2i(720,1280),Vector2i(720,1560)]:
   # Short iPhone without a notch, and tall iPhone with a notch; both have banners.
   var margin=scene.get_node("MarginContainer")
   margin.add_theme_constant_override("margin_top",146 if size.y==1280 else 220)
   margin.add_theme_constant_override("margin_bottom",96 if size.y==1280 else 132)
   await settle()
   check(scene.vbox.get_combined_minimum_size().y<=scene.scroll_container.size.y+1, "all actions fit with notch and banner clearance content="+str(scene.vbox.get_combined_minimum_size().y)+" available="+str(scene.scroll_container.size.y))
   await snap("profile-compact-safe-area")
  for open_sheet in [scene._on_share_pressed,scene._open_achievements,scene._on_delete_pressed]:
   open_sheet.call()
   await settle()
   var overlay=scene._invite_overlay if is_instance_valid(scene._invite_overlay) else scene._active_sheet
   var stage=overlay.get_child(0)
   check(stage.get_global_rect().end.x<=size.x+1, "sheet width fits "+str(size))
   check(stage.get_combined_minimum_size().y<=size.y+1, "sheet height fits "+str(size)+" "+str(open_sheet.get_method())+" min="+str(stage.get_combined_minimum_size()))
   if is_instance_valid(scene._invite_overlay): scene._close_invite_sheet()
   else: scene._close_profile_sheet(scene._active_sheet)
   await settle()
  scene.queue_free()
  await settle()
 # Force overflow only to check that a drag in the content reaches the scroll.
 root.content_scale_size=Vector2i(720,700)
 root.size=Vector2i(360,350)
 scene=await new_profile()
 var touch=InputEventScreenTouch.new()
 touch.index=0
 touch.pressed=true
 touch.position=scene.card_user.get_global_rect().get_center()
 root.push_input(touch, true)
 await settle()
 var drag=InputEventScreenDrag.new()
 drag.index=0
 drag.position=touch.position-Vector2(0,90)
 drag.relative=Vector2(0,-90)
 root.push_input(drag, true)
 await settle()
 check(scene.scroll_container.scroll_vertical>0, "touch drag from middle of profile scrolls overflowing content")
 touch.pressed=false
 touch.position=drag.position
 root.push_input(touch, true)
 await settle()
 check(not scene.btn_share.disabled, "touch release restores buttons")
 scene.scroll_container.ensure_control_visible(scene.btn_share)
 await settle()
 var mouse=InputEventMouseButton.new()
 mouse.button_index=MOUSE_BUTTON_LEFT
 mouse.pressed=true
 mouse.position=scene.btn_share.get_global_rect().get_center()
 root.push_input(mouse,true)
 var motion=InputEventMouseMotion.new()
 motion.position=mouse.position-Vector2(0,60)
 motion.relative=Vector2(0,-60)
 motion.button_mask=MOUSE_BUTTON_MASK_LEFT
 root.push_input(motion,true)
 check(scene.btn_share.disabled, "drag suppresses action buttons")
 mouse.pressed=false
 mouse.position=motion.position
 root.push_input(mouse,true)
 await settle()
 check(not is_instance_valid(scene._invite_overlay) and not scene.btn_share.disabled, "drag release never opens invitation and restores button")
 scene.queue_free()
 await settle()
 var rates=load("res://rate_actual.gd").new()
 root.add_child(rates)
 var no_count={"referralCode":{"stringValue":"CANDAR26"}}
 var components=await rates.get_user_mining_rate_components("qa", no_count)
 check(components.ref_count==3 and is_equal_approx(components.total_rate,1.15), "missing referral counter queries actual referrals")
 check(rates.referral_queries==1 and rates.writes==0, "rate display never rewrites server counters")
 no_count["referralCount"]={"integerValue":"12"}
 components=await rates.get_user_mining_rate_components("qa",no_count)
 check(is_equal_approx(components.total_rate,1.6) and rates.referral_queries==1, "stored counter avoids redundant referral query")
 no_count["currentMultiplier"]={"doubleValue":2.0}
 no_count["boostExpiresAt"]={"timestampValue":"2020-01-01T00:00:00Z"}
 components=await rates.get_user_mining_rate_components("qa",no_count)
 check(is_equal_approx(components.total_rate,1.6), "actual rate ignores expired boost")
 rates.queue_free()
 await settle()
 if not failures.is_empty():
  for failure in failures: push_error(failure)
  quit(1)
 else:
  print("Profile smoke: %d checks passed; no real account mutations or network requests." % checks)
  quit()
