"""Tests for the unit catalog tool. Run: python3 -m unittest discover -s tools/unit_catalog -p 'test_*.py'"""
import base64
import http.client
import json
import shutil
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalog  # noqa: E402
import server  # noqa: E402

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 24
JPG = b"\xff\xd8\xff\xe0" + b"\x00" * 24
CLASSES = [
    {"id": "tank", "label": "Tank", "mobility": "tracked", "required_views": ["side", "top"]},
    {"id": "infantry", "label": "Infantry", "mobility": "foot", "required_views": ["side"]},
]
FACTION = {
    "id": "poland", "name": "Poland", "iso_code": "PL", "color": "#5b93d6",
    "camo": ["#4b5320", "#3b2f22", "#1e1f1a"], "vest_color": "#4f5934", "notes": "",
}  # fmt: skip


def b64(data):
    return base64.b64encode(data).decode("ascii")


def complete_unit(**over):
    unit = {
        "id": "leopard_2a4", "real_name": "Leopard 2A4", "class": "tank", "mobility": "tracked",
        "operators": ["poland"], "status": "draft",
        "dimensions": {"hull_length": 7.7, "width": 3.7, "height": 3.0},
        "silhouette_features": ["flat turret", "long barrel", "boxy hull"], "mechanisms": {"wheels": {}},
        "images": [{"file": "side_1.png", "view": "side"}],
    }  # fmt: skip
    unit.update(over)
    return unit


class CatalogTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="unit_catalog_test_")
        self.root = Path(self.tmp) / "units_root"
        self.root.mkdir()
        shutil.copy(catalog.DEFAULT_ROOT / catalog.MECHANISMS_FILE, self.root / catalog.MECHANISMS_FILE)
        catalog.save_classes(self.root, CLASSES)
        catalog.create_faction(self.root, FACTION)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def validate(self, unit):
        return catalog.validate_unit(unit, CLASSES, ["poland"])


class TestIdsAndPaths(CatalogTestCase):
    def test_valid_ids(self):
        self.assertTrue(catalog.is_valid_id("leopard_2a4"))
        self.assertTrue(catalog.is_valid_id("t72b3"))

    def test_slug(self):
        self.assertEqual(catalog.slugify("Leopard 2A4"), "leopard_2a4")
        self.assertEqual(catalog.slugify("  M1A2 SEPv3 Abrams "), "m1a2_sepv3_abrams")

    def test_rejected_ids(self):
        for bad in ["../x", "a", "", "UPPER", "a/b", "a\\b", "/etc/passwd", "x" * 49, None]:
            self.assertFalse(catalog.is_valid_id(bad), bad)
            with self.assertRaises(catalog.CatalogError):
                catalog.check_id(bad)

    def test_unsafe_image_names_rejected(self):
        for bad in ["../side_1.png", "a/side_1.png", "/etc/passwd", "side_1.txt", "..\\side_1.png",
                    "side_1.png/..", "unknown_1.png", "side_x.png"]:  # fmt: skip
            with self.assertRaises(catalog.CatalogError, msg=bad):
                catalog.check_image_file_name(bad)
        self.assertEqual(catalog.check_image_file_name("side_1.png"), "side_1.png")

    def test_unsafe_unit_id_in_paths(self):
        with self.assertRaises(catalog.CatalogError):
            catalog.unit_dir(self.root, "../x")
        with self.assertRaises(catalog.CatalogError):
            catalog.delete_image(self.root, "../x", "side_1.png")

    def test_resolve_inside(self):
        self.assertIsNone(catalog.resolve_inside(self.root, "../project.godot"))
        self.assertIsNone(catalog.resolve_inside(self.root, "/etc/passwd"))
        self.assertIsNotNone(catalog.resolve_inside(self.root, "classes.json"))


class TestValidation(CatalogTestCase):
    def test_valid_unit(self):
        self.assertEqual(self.validate(complete_unit()), [])

    def test_unknown_class_and_operator(self):
        errs = self.validate(complete_unit(**{"class": "ufo", "operators": ["mars"]}))
        fields = [e["field"] for e in errs]
        self.assertIn("class", fields)
        self.assertIn("operators", fields)

    def test_negative_dimension(self):
        errs = self.validate(complete_unit(dimensions={"height": -1}))
        self.assertEqual([e["field"] for e in errs], ["dimensions.height"])

    def test_bad_status(self):
        self.assertEqual([e["field"] for e in self.validate(complete_unit(status="x"))], ["status"])


class TestReadiness(CatalogTestCase):
    def test_missing_height_and_side_image(self):
        unit = complete_unit(images=[{"file": "front_1.png", "view": "front"}],
                             dimensions={"hull_length": 7.7, "width": 3.7})  # fmt: skip
        self.assertEqual(catalog.readiness_missing(unit), ["height", "side or drawing image"])
        unit["status"] = "ready_for_model"
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.save_unit(self.root, unit)
        self.assertEqual(ctx.exception.errors[0]["field"], "status")
        self.assertEqual(ctx.exception.errors[0]["missing"], ["height", "side or drawing image"])

    def test_complete_unit_can_be_ready(self):
        unit = complete_unit(status="ready_for_model")
        self.assertEqual(catalog.readiness_missing(unit), [])
        self.assertEqual(catalog.save_unit(self.root, unit)["status"], "ready_for_model")

    def test_foot_unit_needs_only_soldier_height_and_any_soldier_photo(self):
        unit = complete_unit(id="pl_squad", real_name="Squad", **{"class": "infantry"}, mobility="foot",
                             dimensions={"height": 1.8}, images=[{"file": "front_1.jpg", "view": "front"}])  # fmt: skip
        self.assertEqual(catalog.readiness_missing(unit), [])
        unit["images"] = [{"file": "three_quarter_1.jpg", "view": "three_quarter"}]
        self.assertEqual(catalog.readiness_missing(unit), [])
        unit["images"] = [{"file": "detail_1.jpg", "view": "detail"}]
        unit["dimensions"] = {"width": 0.6}
        self.assertEqual(catalog.readiness_missing(unit), ["height", "side, front or three-quarter photo of a soldier"])

    def test_foot_unit_unverified_ai_width_does_not_block(self):
        unit = complete_unit(**{"class": "infantry"}, mobility="foot", dimensions={"height": 1.8, "width": 0.6},
                             provenance={"dimensions.width": {"source": "https://x.org", "verified": False},
                                         "dimensions.height": {"source": "https://x.org", "verified": False}})  # fmt: skip
        self.assertEqual(catalog.readiness_missing(unit), ["verify dimensions.height (AI)"])

    def test_vehicle_still_needs_all_three_dimensions(self):
        unit = complete_unit(dimensions={"height": 3.0})
        self.assertEqual(catalog.readiness_missing(unit), ["width", "hull_length"])

    def test_going_back_to_draft_is_allowed(self):
        catalog.save_unit(self.root, complete_unit(status="ready_for_model"))
        unit = complete_unit(status="draft", dimensions={})
        self.assertEqual(catalog.save_unit(self.root, unit)["status"], "draft")


class TestSaveLoad(CatalogTestCase):
    def test_round_trip_and_stable_bytes(self):
        unit = complete_unit(variant_note="", armament={"secondary": "MG3", "main": "120 mm"}, weight_t=55.2)
        catalog.save_unit(self.root, unit, today="2026-01-01")
        path = self.root / "units" / "leopard_2a4" / "unit.json"
        first = path.read_bytes()
        loaded = catalog.load_unit(self.root, "leopard_2a4")
        self.assertEqual(loaded["real_name"], "Leopard 2A4")
        self.assertEqual(loaded["dimensions"]["height"], 3.0)
        self.assertNotIn("variant_note", loaded)
        catalog.save_unit(self.root, loaded, today="2026-01-01")
        self.assertEqual(path.read_bytes(), first)
        text = first.decode("utf-8")
        self.assertTrue(text.endswith("}\n"))
        self.assertIn('\n  "id": "leopard_2a4",\n', text)
        self.assertLess(text.index('"main"'), text.index('"secondary"'))
        self.assertLess(text.index('"real_name"'), text.index('"class"'))
        self.assertEqual(list(self.root.rglob(".tmp_*")), [])

    def test_create_unit_slug_and_duplicates(self):
        unit = catalog.create_unit(self.root, "Leopard 2A4", **{"class": "tank", "operators": ["poland"]})
        self.assertEqual(unit["id"], "leopard_2a4")
        self.assertEqual(unit["status"], "draft")
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.create_unit(self.root, "Leopard 2A4")
        self.assertEqual(ctx.exception.status, 409)

    def test_faction_validation(self):
        bad = dict(FACTION, camo=["#fff"])
        with self.assertRaises(catalog.CatalogError):
            catalog.save_faction(self.root, "poland", bad)

    def test_unit_listed_with_completeness(self):
        catalog.save_unit(self.root, complete_unit())
        summary = catalog.catalog_summary(self.root)
        self.assertEqual([u["id"] for u in summary["units"]], ["leopard_2a4"])
        self.assertTrue(0 < summary["units"][0]["completeness"] <= 1)


class TestImages(CatalogTestCase):
    def setUp(self):
        super().setUp()
        catalog.save_unit(self.root, complete_unit(images=[]))

    def test_sniff(self):
        self.assertEqual(catalog.sniff_image(PNG), "png")
        self.assertEqual(catalog.sniff_image(JPG), "jpg")
        self.assertEqual(catalog.sniff_image(b"RIFF\x00\x00\x00\x00WEBPVP8 "), "webp")
        self.assertIsNone(catalog.sniff_image(b"hello, not an image"))

    def test_upload_and_numbering(self):
        e1 = catalog.add_image(self.root, "leopard_2a4", "side", b64(PNG), "http://x", "CC0")
        e2 = catalog.add_image(self.root, "leopard_2a4", "side", b64(JPG))
        e3 = catalog.add_image(self.root, "leopard_2a4", "front", b64(PNG))
        self.assertEqual([e1["file"], e2["file"], e3["file"]], ["side_1.png", "side_2.jpg", "front_1.png"])
        udir = self.root / "units" / "leopard_2a4"
        self.assertEqual((udir / "side_1.png").read_bytes(), PNG)
        self.assertEqual(len(catalog.load_unit(self.root, "leopard_2a4")["images"]), 3)

    def test_text_file_renamed_png_rejected(self):
        with self.assertRaises(catalog.CatalogError):
            catalog.add_image(self.root, "leopard_2a4", "side", b64(b"just text pretending to be a png"))
        self.assertEqual(catalog.load_unit(self.root, "leopard_2a4").get("images", []), [])

    def test_size_limit_and_bad_view(self):
        big = PNG + b"\x00" * catalog.MAX_IMAGE_BYTES
        with self.assertRaises(catalog.CatalogError):
            catalog.add_image(self.root, "leopard_2a4", "side", b64(big))
        with self.assertRaises(catalog.CatalogError):
            catalog.add_image(self.root, "leopard_2a4", "bogus", b64(PNG))

    def test_delete_image(self):
        e = catalog.add_image(self.root, "leopard_2a4", "side", b64(PNG))
        catalog.delete_image(self.root, "leopard_2a4", e["file"])
        self.assertFalse((self.root / "units" / "leopard_2a4" / e["file"]).exists())
        with self.assertRaises(catalog.CatalogError):
            catalog.delete_image(self.root, "leopard_2a4", "../../classes.json")

    def test_update_cannot_invent_images_but_edits_metadata(self):
        e = catalog.add_image(self.root, "leopard_2a4", "side", b64(PNG))
        unit = catalog.load_unit(self.root, "leopard_2a4")
        unit["images"] = [dict(e, view="drawing", note="n"), {"file": "side_9.png", "view": "side"}]
        saved = catalog.update_unit(self.root, "leopard_2a4", unit)
        self.assertEqual([(i["file"], i["view"], i["note"]) for i in saved["images"]], [("side_1.png", "drawing", "n")])


class TestSheet(CatalogTestCase):
    def test_latest_sheet(self):
        shots = Path(self.tmp) / "shots"
        shots.mkdir()
        self.assertIsNone(catalog.latest_sheet(shots, "leopard_2a4"))
        (shots / "leopard_2a4_v1_sheet.png").write_bytes(PNG)
        (shots / "other_v1_sheet.png").write_bytes(PNG)
        self.assertEqual(catalog.latest_sheet(shots, "leopard_2a4"), "leopard_2a4_v1_sheet.png")


class ServerCase(CatalogTestCase):
    def setUp(self):
        super().setUp()
        self.shots = Path(self.tmp) / "shots"
        self.shots.mkdir()
        self.httpd = server.make_server(0, self.root, self.shots)
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(5)
        super().tearDown()

    def req(self, method, path, body=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        data = json.dumps(body).encode() if body is not None else None
        conn.request(method, path, body=data, headers={"Content-Type": "application/json"})
        resp = conn.getresponse()
        raw = resp.read()
        conn.close()
        return resp.status, raw

    def jreq(self, method, path, body=None):
        status, raw = self.req(method, path, body)
        return status, json.loads(raw.decode("utf-8"))

class TestServer(ServerCase):
    def test_binds_localhost_only(self):
        self.assertEqual(self.httpd.server_address[0], "127.0.0.1")

    def test_catalog_has_classes(self):
        status, data = self.jreq("GET", "/api/catalog")
        self.assertEqual(status, 200)
        self.assertEqual([c["id"] for c in data["classes"]], ["tank", "infantry"])
        self.assertEqual(data["factions"][0]["id"], "poland")

    def test_static_index(self):
        status, raw = self.req("GET", "/")
        self.assertEqual(status, 200)
        self.assertIn(b"<html", raw)

    def test_create_put_get_and_images(self):
        status, data = self.jreq("POST", "/api/units", {"real_name": "Leopard 2A4", "class": "tank", "operators": ["poland"]})
        self.assertEqual(status, 201)
        self.assertEqual(data["unit"]["id"], "leopard_2a4")
        unit = data["unit"]
        unit["variant_note"] = "Polish upgrade"
        unit["dimensions"] = {"height": 3.0}
        status, data = self.jreq("PUT", "/api/units/leopard_2a4", unit)
        self.assertEqual(status, 200)
        status, data = self.jreq("GET", "/api/units/leopard_2a4")
        self.assertEqual(data["unit"]["variant_note"], "Polish upgrade")
        self.assertIn("hull_length", data["missing"])
        status, data = self.jreq("POST", "/api/units/leopard_2a4/images", {"view": "side", "data": b64(PNG)})
        self.assertEqual(status, 201)
        self.assertEqual(data["image"]["file"], "side_1.png")
        status, raw = self.req("GET", "/files/units/leopard_2a4/side_1.png")
        self.assertEqual((status, raw), (200, PNG))
        status, data = self.jreq("DELETE", "/api/units/leopard_2a4/images/side_1.png")
        self.assertEqual(status, 200)
        self.assertEqual(data["unit"].get("images", []), [])

    def test_validation_error_is_400(self):
        status, data = self.jreq("POST", "/api/units", {"real_name": "Xyz", "class": "ufo"})
        self.assertEqual(status, 400)
        self.assertEqual(data["errors"][0]["field"], "class")

    def test_bad_unit_id_rejected(self):
        status, _ = self.jreq("GET", "/api/units/..%2Fx")
        self.assertEqual(status, 400)
        status, _ = self.jreq("DELETE", "/api/units/leopard_2a4/images/..%2F..%2Fclasses.json")
        self.assertIn(status, (400, 404))

    def test_path_traversal_blocked(self):
        for path in ["/files/../../project.godot", "/files/%2e%2e/%2e%2e/project.godot", "/files//etc/passwd",
                     "/files/..%2F..%2Fproject.godot", "/files/units/../../../project.godot"]:  # fmt: skip
            status, _ = self.req("GET", path)
            self.assertIn(status, (403, 404), path)

    def test_files_are_read_only_and_screenshots_served(self):
        (self.shots / "leopard_2a4_x_sheet.png").write_bytes(PNG)
        self.assertEqual(self.req("GET", "/files/screenshots/leopard_2a4_x_sheet.png")[0], 200)
        self.assertEqual(self.req("PUT", "/files/classes.json", [])[0], 404)

    def test_foreign_host_header_rejected(self):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.request("GET", "/api/catalog", headers={"Host": "evil.example"})
        self.assertEqual(conn.getresponse().status, 403)
        conn.close()

    def test_faction_post_then_put(self):
        russia = dict(FACTION, id="russia", name="Russia", iso_code="RU")
        self.assertEqual(self.jreq("PUT", "/api/factions/russia", russia)[0], 404)
        self.assertEqual(self.jreq("POST", "/api/factions", russia)[0], 201)
        self.assertEqual(self.jreq("POST", "/api/factions", russia)[0], 409)
        status, data = self.jreq("PUT", "/api/factions/russia", dict(russia, name="Russian Federation"))
        self.assertEqual(status, 200)
        status, data = self.jreq("GET", "/api/catalog")
        self.assertEqual(sorted(f["id"] for f in data["factions"]), ["poland", "russia"])


class TestHardening(CatalogTestCase):
    def test_regexes_reject_trailing_newline(self):
        self.assertFalse(catalog.is_valid_id("ab\n"))
        with self.assertRaises(catalog.CatalogError):
            catalog.check_image_file_name("side_1.png\n")
        with self.assertRaises(catalog.CatalogError):
            catalog.save_faction(self.root, "poland", dict(FACTION, iso_code="PL\n"))
        with self.assertRaises(catalog.CatalogError):
            catalog.save_faction(self.root, "poland", dict(FACTION, color="#5b93d6\n"))

    def test_unknown_keys_rejected(self):
        for unit in (complete_unit(bogus=1), complete_unit(dimensions={"depth": 1}),
                     complete_unit(armament={"tertiary": "x"}),
                     complete_unit(images=[{"file": "side_1.png", "view": "side", "x": 1}])):  # fmt: skip
            self.assertTrue(self.validate(unit))

    def test_concurrent_uploads_get_distinct_names(self):
        catalog.save_unit(self.root, complete_unit(images=[]))
        names, errors = [], []

        def upload():
            try:
                names.append(catalog.add_image(self.root, "leopard_2a4", "side", b64(PNG))["file"])
            except Exception as exc:  # pragma: no cover
                errors.append(exc)

        threads = [threading.Thread(target=upload) for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(errors, [])
        self.assertEqual(sorted(names), ["side_1.png", "side_2.png"])
        files = [i["file"] for i in catalog.load_unit(self.root, "leopard_2a4")["images"]]
        self.assertEqual(sorted(files), ["side_1.png", "side_2.png"])

    def test_stale_put_keeps_image_added_in_between(self):
        catalog.save_unit(self.root, complete_unit(images=[]))
        stale = catalog.load_unit(self.root, "leopard_2a4")
        catalog.add_image(self.root, "leopard_2a4", "side", b64(PNG))
        stale.pop("revision")  # a client without revision check still must not drop the image
        stale["variant_note"] = "x"
        saved = catalog.update_unit(self.root, "leopard_2a4", stale)
        self.assertEqual([i["file"] for i in saved["images"]], ["side_1.png"])

    def test_revision_conflict(self):
        catalog.save_unit(self.root, complete_unit())
        mine = catalog.load_unit(self.root, "leopard_2a4")
        other = dict(mine, variant_note="other")
        catalog.update_unit(self.root, "leopard_2a4", other)
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.update_unit(self.root, "leopard_2a4", dict(mine, variant_note="mine"))
        self.assertEqual(ctx.exception.status, 409)
        self.assertEqual(catalog.load_unit(self.root, "leopard_2a4")["variant_note"], "other")

    def test_delete_saves_json_before_unlinking(self):
        catalog.save_unit(self.root, complete_unit(images=[]))
        e = catalog.add_image(self.root, "leopard_2a4", "front", b64(PNG))
        path = self.root / "units" / "leopard_2a4" / e["file"]
        original = catalog.save_unit

        def failing(*a, **k):
            raise catalog.CatalogError([{"field": "x", "message": "boom"}])

        catalog.save_unit = failing
        try:
            with self.assertRaises(catalog.CatalogError):
                catalog.delete_image(self.root, "leopard_2a4", e["file"])
        finally:
            catalog.save_unit = original
        self.assertTrue(path.exists())
        self.assertEqual(len(catalog.load_unit(self.root, "leopard_2a4")["images"]), 1)

    def test_delete_last_side_image_of_ready_unit_refused(self):
        catalog.save_unit(self.root, complete_unit(images=[]))
        e = catalog.add_image(self.root, "leopard_2a4", "side", b64(PNG))
        unit = catalog.load_unit(self.root, "leopard_2a4")
        catalog.save_unit(self.root, dict(unit, status="ready_for_model"))
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.delete_image(self.root, "leopard_2a4", e["file"])
        self.assertIn("draft", str(ctx.exception))
        self.assertTrue((self.root / "units" / "leopard_2a4" / e["file"]).exists())
        self.assertEqual(catalog.load_unit(self.root, "leopard_2a4")["status"], "ready_for_model")

    def test_delete_front_photo_of_ready_foot_unit_allowed_when_another_soldier_photo_remains(self):
        squad = complete_unit(**{"class": "infantry"}, mobility="foot", dimensions={"height": 1.8}, images=[])
        catalog.save_unit(self.root, squad)
        front = catalog.add_image(self.root, "leopard_2a4", "front", b64(JPG))
        catalog.add_image(self.root, "leopard_2a4", "three_quarter", b64(JPG))
        unit = catalog.load_unit(self.root, "leopard_2a4")
        catalog.save_unit(self.root, dict(unit, status="ready_for_model"))
        catalog.delete_image(self.root, "leopard_2a4", front["file"])
        self.assertEqual(len(catalog.load_unit(self.root, "leopard_2a4")["images"]), 1)

    def test_failed_add_image_removes_file(self):
        catalog.save_unit(self.root, complete_unit(images=[]))
        original = catalog.save_unit

        def failing(*a, **k):
            raise catalog.CatalogError([{"field": "x", "message": "boom"}])

        catalog.save_unit = failing
        try:
            with self.assertRaises(catalog.CatalogError):
                catalog.add_image(self.root, "leopard_2a4", "side", b64(PNG))
        finally:
            catalog.save_unit = original
        self.assertEqual(list((self.root / "units" / "leopard_2a4").glob("side_*")), [])

    def test_cannot_remove_class_in_use(self):
        catalog.save_unit(self.root, complete_unit())
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.save_classes(self.root, [CLASSES[1]])
        self.assertIn("leopard_2a4", str(ctx.exception))
        self.assertEqual(len(catalog.load_classes(self.root)), 2)

    def test_duplicate_faction_create_conflicts(self):
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.create_faction(self.root, FACTION)
        self.assertEqual(ctx.exception.status, 409)

    def test_written_files_are_world_readable(self):
        catalog.save_unit(self.root, complete_unit())
        mode = (self.root / "units" / "leopard_2a4" / "unit.json").stat().st_mode & 0o777
        self.assertEqual(mode, 0o644)


class TestServerHardening(ServerCase):
    def raw(self, method, path, body=b"", headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.request(method, path, body=body, headers=headers or {})
        resp = conn.getresponse()
        raw = resp.read()
        conn.close()
        return resp.status, raw

    def test_csrf_content_type_required(self):
        body = json.dumps({"real_name": "Abc", "class": "tank"}).encode()
        self.assertEqual(self.raw("POST", "/api/units", body, {"Content-Type": "text/plain"})[0], 403)
        self.assertEqual(self.raw("POST", "/api/units", body)[0], 403)
        self.assertEqual(self.raw("POST", "/api/units", body, {"Content-Type": "application/json"})[0], 201)

    def test_csrf_origin_checked(self):
        body = json.dumps({"real_name": "Abc", "class": "tank"}).encode()
        base = {"Content-Type": "application/json"}
        self.assertEqual(self.raw("POST", "/api/units", body, dict(base, Origin="http://evil.example"))[0], 403)
        self.assertEqual(self.raw("POST", "/api/units", body, dict(base, Origin="http://localhost:1"))[0], 403)
        ok = dict(base, Origin="http://localhost:%d" % self.port)
        self.assertEqual(self.raw("POST", "/api/units", body, ok)[0], 201)

    def test_non_object_body_is_400(self):
        h = {"Content-Type": "application/json"}
        for body in (b"[1,2]", b"3", b"null", b"{bad"):
            status, raw = self.raw("POST", "/api/units", body, h)
            self.assertEqual(status, 400, body)
            self.assertNotIn(b"Traceback", raw)

    def test_bad_content_length(self):
        h = {"Content-Type": "application/json", "Content-Length": "-5"}
        self.assertEqual(self.raw("POST", "/api/units", b"", h)[0], 400)
        h = {"Content-Type": "application/json", "Content-Length": str(server.MAX_BODY + 1)}
        self.assertEqual(self.raw("POST", "/api/units", b"", h)[0], 413)

    def test_classes_put_and_in_use(self):
        self.jreq("POST", "/api/units", {"real_name": "Abc", "class": "tank"})
        status, data = self.jreq("PUT", "/api/classes", {"classes": [CLASSES[1]]})
        self.assertEqual(status, 409)
        self.assertIn("abc", data["errors"][0]["message"])
        self.assertEqual(self.jreq("PUT", "/api/classes", {"classes": CLASSES})[0], 200)

    def test_port_out_of_range(self):
        self.assertEqual(server.main(["--port=70000"]), 2)
        self.assertEqual(server.main(["--port=0"]), 2)



if __name__ == "__main__":
    unittest.main()
