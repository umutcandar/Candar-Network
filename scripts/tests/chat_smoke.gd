extends SceneTree
var failures: Array[String] = []
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
 checks += 1
 if not ok: failures.append(message)
func settle():
 for i in range(10): await process_frame
func run():
 TranslationServer.set_locale("tr")
 var scene=load("res://chat.tscn").instantiate()
 root.add_child(scene)
 await settle()
 var firebase=root.get_node("Firebase")
 check(tr("chat_title")=="Candar Ai", "brand capitalization")
 check(firebase.calls==0, "opening chat does not send a message")
 check(scene.find_child("AiNotice",true,false)==null, "no notice beneath chat")
 scene._on_suggestion_pressed("Günlük puanımı nasıl alırım?")
 check(firebase.calls==0 and not scene.input.text.is_empty(), "suggestion prepares a draft without auto-sending")
 await settle()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]+"/chat-clean.png")
 check(scene.row.get_global_rect().end.y<=1560, "composer fits iPhone")
 check(scene.find_children("*", "ConfirmationDialog", true, false).is_empty(), "no permission popup")
 await scene._send()
 check(firebase.calls==1, "first send works directly without extra confirmation")
 check(not firebase.payload.has("aiConsent"), "no invented consent sent to server")
 check(firebase.payload.get("lang").begins_with("tr"), "selected app language used")
 check(firebase.payload.keys().size()==2, "no account data attached")
 check(scene.status_label.text.contains("4"), "remaining messages rendered")
 firebase.fail=true
 scene.input.text="Boost almalı mıyım?"
 scene._send()
 scene._send()
 await create_timer(0.3).timeout
 check(firebase.calls==2, "duplicate sends blocked")
 check(scene.input.text=="Boost almalı mıyım?", "quota failure preserves draft")
 check(not scene.send_btn.disabled and scene.input.editable, "error releases controls")
 scene.input.text="a".repeat(1001)
 await scene._send()
 check(firebase.calls==2, "overlong prompt blocked locally")
 scene.queue_free()
 await settle()
 if failures.is_empty(): print("Candar Ai UI: %d checks passed." % checks); quit()
 else:
  for message in failures: push_error(message)
  quit(1)
