"""Tests for AI research support: provenance, research.json merge, image candidates.

Run: python3 -m unittest discover -s tools/unit_catalog -p 'test_*.py'
"""
import json
import sys
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalog  # noqa: E402
import server  # noqa: E402
import test_catalog as base  # noqa: E402  (module import, so its test classes don't run twice)

SRC = "https://example.org/k2"
IMG_URL = "https://upload.wikimedia.org/wikipedia/commons/a/ab/K2_side.jpg"
IMG_THUMB = "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/K2_side.jpg/1920px-K2_side.jpg"


def write_research(root, unit_id, research):
    (catalog.unit_dir(root, unit_id) / catalog.RESEARCH_FILE).write_text(json.dumps(research), encoding="utf-8")


class TestProvenanceValidation(base.CatalogTestCase):
    def test_valid_provenance_and_candidates(self):
        unit = base.complete_unit(
            provenance={"dimensions.height": {"source": SRC, "verified": False}, "crew": {"verified": True, "suggested": 3}},
            image_candidates=[{"url": IMG_URL, "view": "side", "license": "CC BY-SA 4.0"}],
        )  # fmt: skip
        self.assertEqual(self.validate(unit), [])

    def test_bad_provenance_rejected(self):
        for prov in [[], {"class": {"verified": False}}, {"crew": {"verified": "no"}}, {"crew": {"oops": 1}}]:
            errors = self.validate(base.complete_unit(provenance=prov))
            self.assertTrue(errors, prov)

    def test_bad_candidates_rejected(self):
        for cand in [{"url": "http://x/a.jpg", "view": "side"}, {"url": IMG_URL, "view": "aerial"},
                     {"url": IMG_URL, "view": "side", "extra": 1}]:  # fmt: skip
            self.assertTrue(self.validate(base.complete_unit(image_candidates=[cand])), cand)

    def test_unverified_dimension_blocks_ready(self):
        unit = base.complete_unit(provenance={"dimensions.height": {"source": SRC, "verified": False}})
        self.assertIn("verify dimensions.height (AI)", catalog.readiness_missing(unit))
        unit["provenance"]["dimensions.height"]["verified"] = True
        self.assertEqual(catalog.readiness_missing(unit), [])

    def test_unverified_non_critical_field_does_not_block(self):
        unit = base.complete_unit(provenance={"crew": {"source": SRC, "verified": False}})
        self.assertEqual(catalog.readiness_missing(unit), [])
        self.assertEqual(catalog.unverified_fields(unit), ["crew"])

    def test_provenance_saved_in_field_order(self):
        catalog.save_unit(self.root, base.complete_unit(
            provenance={"silhouette_features": {"verified": True}, "crew": {"verified": False, "source": SRC}}))  # fmt: skip
        stored = catalog.load_unit(self.root, "leopard_2a4")
        self.assertEqual(list(stored["provenance"]), ["crew", "silhouette_features"])
        self.assertEqual(list(stored["provenance"]["crew"]), ["source", "verified"])


class TestMergeResearch(base.CatalogTestCase):
    def setUp(self):
        super().setUp()
        catalog.create_unit(self.root, "K2 Black Panther", "k2", operators=["poland"])

    def merge(self, research):
        unit = catalog.load_unit(self.root, "k2")
        report = catalog.merge_research(unit, research, base.CLASSES, ["poland"])
        return unit, report

    def test_fills_empty_fields_as_unverified(self):
        unit, report = self.merge({"fields": {
            "weight_t": {"value": 55.0, "source": SRC},
            "dimensions.height": {"value": 2.4, "source": SRC + "/dims"},
            "silhouette_features": {"value": ["a", "b", "c"], "source": SRC},
        }})  # fmt: skip
        self.assertEqual(unit["weight_t"], 55.0)
        self.assertEqual(unit["dimensions"]["height"], 2.4)
        self.assertEqual(unit["dimensions"]["sources"], [SRC + "/dims"])
        self.assertEqual(unit["provenance"]["weight_t"], {"source": SRC, "verified": False})
        self.assertEqual(sorted(report["filled"]), ["dimensions.height", "silhouette_features", "weight_t"])

    def test_human_value_kept_and_different_ai_value_suggested(self):
        unit = catalog.load_unit(self.root, "k2")
        unit["crew"] = "3"
        catalog.save_unit(self.root, unit)
        unit, report = self.merge({"fields": {"crew": {"value": 4, "source": SRC}, "operators": {"value": ["poland"]}}})
        self.assertEqual(unit["crew"], "3")
        self.assertEqual(unit["provenance"]["crew"], {"source": SRC, "verified": True, "suggested": 4})
        self.assertNotIn("operators", unit["provenance"])  # same value: nothing to say
        self.assertEqual(report["suggested"], ["crew"])

    def test_invalid_and_unknown_values_rejected(self):
        unit, report = self.merge({"fields": {
            "weight_t": {"value": -3, "source": SRC},
            "operators": {"value": ["atlantis"], "source": SRC},
            "class": {"value": "infantry", "source": SRC},
            "range_km": "500",
        }})  # fmt: skip
        self.assertEqual(sorted(r["field"] for r in report["rejected"]), ["class", "operators", "range_km", "weight_t"])
        self.assertNotIn("weight_t", unit)
        self.assertEqual(unit["class"], "tank")

    def test_candidates_validated_and_deduplicated(self):
        cands = [{"url": IMG_URL, "view": "side", "license": "CC0"}, {"url": IMG_URL, "view": "side"},
                 {"url": "ftp://x", "view": "side"}]  # fmt: skip
        unit, report = self.merge({"image_candidates": cands, "summary": "chose K2PL"})
        self.assertEqual(unit["image_candidates"], [{"url": IMG_URL, "view": "side", "license": "CC0"}])
        self.assertEqual(report["candidates"], 1)
        self.assertEqual(len(report["rejected"]), 1)
        self.assertEqual(report["summary"], "chose K2PL")

    def test_apply_research_saves_and_removes_file(self):
        write_research(self.root, "k2", {"fields": {"dimensions.width": {"value": 3.6, "source": SRC}}})
        report = catalog.apply_research(self.root, "k2")
        self.assertEqual(report["filled"], ["dimensions.width"])
        stored = catalog.load_unit(self.root, "k2")
        self.assertEqual(stored["dimensions"]["width"], 3.6)
        self.assertEqual(stored["revision"], 2)
        self.assertFalse((catalog.unit_dir(self.root, "k2") / catalog.RESEARCH_FILE).exists())

    def test_apply_without_file_or_with_broken_json(self):
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.apply_research(self.root, "k2")
        self.assertEqual(ctx.exception.status, 404)
        (catalog.unit_dir(self.root, "k2") / catalog.RESEARCH_FILE).write_text("{oops", encoding="utf-8")
        with self.assertRaises(catalog.CatalogError):
            catalog.apply_research(self.root, "k2")

    def test_candidate_download_and_dismiss(self):
        unit = catalog.load_unit(self.root, "k2")
        unit["image_candidates"] = [{"url": IMG_URL, "view": "side", "license": "CC0"}, {"url": IMG_URL + "2", "view": "top"}]
        catalog.save_unit(self.root, unit)
        entry = catalog.add_image_bytes(self.root, "k2", "side", base.PNG, IMG_URL, "CC0", drop_candidate=IMG_URL)
        self.assertEqual(entry["file"], "side_1.png")
        catalog.dismiss_candidate(self.root, "k2", IMG_URL + "2")
        stored = catalog.load_unit(self.root, "k2")
        self.assertNotIn("image_candidates", stored)
        self.assertEqual(stored["images"][0]["source_url"], IMG_URL)
        with self.assertRaises(catalog.CatalogError):
            catalog.dismiss_candidate(self.root, "k2", "https://nope")


class TestResearchServer(base.ServerCase):
    def setUp(self):
        base.CatalogTestCase.setUp(self)
        self.shots = Path(self.tmp) / "shots"
        self.shots.mkdir()
        self.fetched = []

        self.broken = set()

        def fake_fetch(url):
            self.fetched.append(url)
            if url in self.broken:
                raise catalog.CatalogError([{"field": "url", "message": "HTTP 404"}], 502)
            return base.JPG

        self.httpd = server.make_server(0, self.root, self.shots, fetch=fake_fetch)
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        catalog.create_unit(self.root, "K2", "k2")

    def test_pending_research_flag_and_apply(self):
        self.assertFalse(self.jreq("GET", "/api/units/k2")[1]["pending_research"])
        write_research(self.root, "k2", {"fields": {"crew": {"value": 3, "source": SRC}},
                                         "image_candidates": [{"url": IMG_URL, "view": "side"}]})  # fmt: skip
        self.assertTrue(self.jreq("GET", "/api/units/k2")[1]["pending_research"])
        status, data = self.jreq("POST", "/api/units/k2/research/apply")
        self.assertEqual(status, 200)
        self.assertEqual(data["report"]["filled"], ["crew"])
        self.assertEqual(data["unit"]["provenance"]["crew"]["verified"], False)
        self.assertFalse(data["pending_research"])
        self.assertEqual(self.jreq("POST", "/api/units/k2/research/apply")[0], 404)

    def test_candidate_endpoints(self):
        unit = catalog.load_unit(self.root, "k2")
        unit["image_candidates"] = [{"url": IMG_URL, "view": "drawing", "license": "PD", "source_page": "https://c/f"}]
        catalog.save_unit(self.root, unit)
        self.assertEqual(self.jreq("POST", "/api/units/k2/candidates", {"action": "x", "url": IMG_URL})[0], 400)
        self.assertEqual(self.jreq("POST", "/api/units/k2/candidates", {"action": "download", "url": "https://other"})[0], 404)
        status, data = self.jreq("POST", "/api/units/k2/candidates", {"action": "download", "url": IMG_URL})
        self.assertEqual(status, 201)
        self.assertEqual(self.fetched, [IMG_THUMB])  # reduced Wikimedia size first
        self.assertEqual(data["image"], {"file": "drawing_1.jpg", "view": "drawing", "source_url": IMG_URL,
                                         "license": "PD", "note": "https://c/f"})  # fmt: skip
        self.assertNotIn("image_candidates", data["unit"])

    def test_reference_falls_back_to_original(self):
        self.broken.add(IMG_THUMB)
        unit = catalog.load_unit(self.root, "k2")
        unit["image_candidates"] = [{"url": IMG_URL, "view": "side"}]
        catalog.save_unit(self.root, unit)
        self.assertEqual(self.jreq("POST", "/api/units/k2/candidates", {"action": "download", "url": IMG_URL})[0], 201)
        self.assertEqual(self.fetched, [IMG_THUMB, IMG_URL])

    def test_reference_urls(self):
        self.assertEqual(server.reference_urls(IMG_URL), [IMG_THUMB, IMG_URL])
        self.assertEqual(server.reference_urls("https://example.org/a.jpg"), ["https://example.org/a.jpg"])

    def test_restore_missing_images(self):
        unit = catalog.load_unit(self.root, "k2")
        unit["images"] = [{"file": "side_1.jpg", "view": "side", "source_url": IMG_URL},
                          {"file": "top_1.png", "view": "top"}]  # fmt: skip
        catalog.save_unit(self.root, unit)  # as after a fresh clone: listed in unit.json, files not in git
        status, data = self.jreq("GET", "/api/catalog")
        self.assertEqual(data["units"][0]["missing_images"], 2)
        self.assertEqual(self.jreq("GET", "/api/units/k2")[1]["missing_images"], ["side_1.jpg", "top_1.png"])
        status, data = self.jreq("POST", "/api/units/k2/images/restore", {})
        self.assertEqual(status, 200)
        self.assertEqual(data["report"]["restored"], ["side_1.jpg"])
        self.assertEqual([f["file"] for f in data["report"]["failed"]], ["top_1.png"])
        self.assertEqual(data["missing_images"], ["top_1.png"])
        self.assertEqual((catalog.unit_dir(self.root, "k2") / "side_1.jpg").read_bytes(), base.JPG)
        status, data = self.jreq("POST", "/api/images/restore", {})
        self.assertEqual([r["unit_id"] for r in data["reports"]], ["k2"])

    def test_restore_image_checks(self):
        unit = catalog.load_unit(self.root, "k2")
        unit["images"] = [{"file": "side_1.png", "view": "side", "source_url": IMG_URL}]
        catalog.save_unit(self.root, unit)
        with self.assertRaises(catalog.CatalogError):  # source now serves a jpg
            catalog.restore_image(self.root, "k2", "side_1.png", base.JPG)
        with self.assertRaises(catalog.CatalogError):
            catalog.restore_image(self.root, "k2", "side_2.png", base.PNG)  # not listed
        catalog.restore_image(self.root, "k2", "side_1.png", base.PNG)
        with self.assertRaises(catalog.CatalogError):
            catalog.restore_image(self.root, "k2", "side_1.png", base.PNG)  # no longer missing

    def test_fetch_image_refuses_plain_http(self):
        with self.assertRaises(catalog.CatalogError):
            server.fetch_image("http://example.org/a.jpg")


if __name__ == "__main__":
    unittest.main()
