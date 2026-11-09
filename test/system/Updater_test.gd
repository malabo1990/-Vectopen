extends GdUnitTestSuite

## Actualizaciones desde GitHub: comparar versiones, elegir la release y el
## paquete de cada sistema.

const U = preload("res://autoloads/Updater.gd")

func test_comparar_versiones() -> void:
	assert_int(U.compare_versions("v0.2.2", "0.2.1")).is_equal(1)
	assert_int(U.compare_versions("0.2.1", "v0.2.1")).is_equal(0)
	assert_int(U.compare_versions("0.2.0-alpha", "0.2.1")).is_equal(-1)
	assert_int(U.compare_versions("0.2.0", "0.2.0-alpha")).is_equal(1)
	assert_int(U.compare_versions("0.10.0", "0.9.9")).is_equal(1)
	assert_int(U.compare_versions("1.0.0-beta", "1.0.0-alpha")).is_equal(1)

func _rel(tag: String, draft := false) -> Dictionary:
	return {"tag_name": tag, "name": "Vectopen " + tag, "draft": draft, "html_url": "https://x/" + tag, "body": "notas",
		"assets": [{"name": "vectopen-%s-1.x86_64.rpm" % tag.trim_prefix("v"), "browser_download_url": "https://x/a.rpm", "size": 10},
			{"name": "vectopen_%s-1_amd64.deb" % tag.trim_prefix("v"), "browser_download_url": "https://x/a.deb", "size": 10},
			{"name": "Vectopen-%s-windows-x64.zip" % tag.trim_prefix("v"), "browser_download_url": "https://x/w.zip", "size": 10},
			{"name": "Vectopen-%s-macos-universal.dmg" % tag.trim_prefix("v"), "browser_download_url": "https://x/m.dmg", "size": 10},
			{"name": "Vectopen-%s-linux-x86_64.tar.gz" % tag.trim_prefix("v"), "browser_download_url": "https://x/l.tgz", "size": 10},
			{"name": "Vectopen-%s-android.apk" % tag.trim_prefix("v"), "browser_download_url": "https://x/a.apk", "size": 10},
			{"name": "SHA256SUMS.txt", "browser_download_url": "https://x/s.txt", "size": 1}]}

func test_elige_la_release_mas_nueva_publicada() -> void:
	var rels := [_rel("v0.2.0-alpha"), _rel("v0.3.0", true), _rel("v0.2.2"), _rel("v0.2.1")]
	var info := U.pick_update(rels, "0.2.1")
	assert_str(info.get("version", "")).is_equal("0.2.2")   # el borrador 0.3.0 no cuenta
	assert_int((info["assets"] as Array).size()).is_equal(7)
	assert_bool(U.pick_update(rels, "0.2.2").is_empty()).is_true()
	assert_bool(U.pick_update(null, "0.1").is_empty()).is_true()

func test_paquete_por_sistema() -> void:
	var assets: Array = U.pick_update([_rel("v9.0.0")], "0.1")["assets"]
	assert_str(U.asset_for(assets, "rpm")["name"]).ends_with(".rpm")
	assert_str(U.asset_for(assets, "deb")["name"]).ends_with(".deb")
	assert_str(U.asset_for(assets, "windows")["name"]).contains("windows")
	assert_str(U.asset_for(assets, "macos")["name"]).ends_with(".dmg")
	assert_str(U.asset_for(assets, "tar")["name"]).ends_with(".tar.gz")
	assert_str(U.asset_for(assets, "android")["name"]).ends_with(".apk")
	assert_bool(U.asset_for([], "rpm").is_empty()).is_true()
