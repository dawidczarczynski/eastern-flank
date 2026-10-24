"""Tests for the mechanisms registry and the per-unit `mechanisms` (TASK-041).

Run: python3 -m unittest discover -s tools/unit_catalog -p 'test_*.py'
"""
import copy
import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalog  # noqa: E402
import test_catalog as base  # noqa: E402  (module import, so its test classes don't run twice)

SRC = "https://example.org/homar"


def fields(errors):
    return [e["field"] for e in errors]


class TestRegistry(unittest.TestCase):
    def setUp(self):
        self.registry = catalog.load_mechanisms(catalog.DEFAULT_ROOT)

    def test_shipped_registry_and_classes_load(self):
        ids = [m["id"] for m in self.registry]
        self.assertEqual(ids, ["wheels", "squad_march", "launcher", "stabilisers", "blast_shields",
                               "turret_traverse", "gun_recoil"])  # fmt: skip
        classes = catalog.load_classes(catalog.DEFAULT_ROOT)
        catalog.validate_classes(classes, self.registry)
        by_id = {c["id"]: c for c in classes}
        self.assertEqual(by_id["mlrs"]["default_mechanisms"], ["wheels", "launcher", "stabilisers"])
        self.assertEqual(by_id["infantry"]["default_mechanisms"], ["squad_march"])

    def rejected(self, mutate):
        registry = copy.deepcopy(self.registry)
        mutate(registry)
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.validate_mechanisms(registry)
        return fields(ctx.exception.errors)

    def test_duplicate_id_rejected(self):
        found = self.rejected(lambda r: r[1].update(id="wheels"))
        self.assertEqual(found, ["mechanisms[1].id"])

    def test_unknown_param_type_rejected(self):
        found = self.rejected(lambda r: r[2]["params"]["stowed"].update(type="colour"))
        self.assertEqual(found, ["mechanisms.launcher.params.stowed.type"])

    def test_default_outside_range_rejected(self):
        found = self.rejected(lambda r: r[2]["params"]["max_elevation_deg"].update(default=120))
        self.assertEqual(found, ["mechanisms.launcher.params.max_elevation_deg.default"])
        found = self.rejected(lambda r: r[2]["params"]["stowed"].update(default="side"))
        self.assertEqual(found, ["mechanisms.launcher.params.stowed.default"])
        found = self.rejected(lambda r: r[5]["params"]["elevation_deg"].update(default="full"))
        self.assertEqual(found, ["mechanisms.turret_traverse.params.elevation_deg.default"])

    def test_missing_default_and_help_rejected(self):
        def mutate(r):
            del r[2]["params"]["stowed"]["default"]
            del r[2]["params"]["stowed"]["help"]

        found = self.rejected(mutate)
        self.assertIn("mechanisms.launcher.params.stowed.default", found)
        self.assertIn("mechanisms.launcher.params.stowed.help", found)

    def test_invalid_registry_file_is_an_error(self):
        import shutil
        import tempfile

        tmp = Path(tempfile.mkdtemp(prefix="unit_catalog_reg_"))
        try:
            (tmp / catalog.MECHANISMS_FILE).write_text("{not json", encoding="utf-8")
            with self.assertRaises(catalog.CatalogError):
                catalog.load_mechanisms(tmp)
            self.assertEqual(catalog.load_mechanisms(tmp / "nothing_here"), [])
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_class_default_mechanisms_validated(self):
        classes = copy.deepcopy(base.CLASSES)
        classes[0]["default_mechanisms"] = ["wheels", "jetpack"]
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.validate_classes(classes, self.registry)
        self.assertEqual(fields(ctx.exception.errors), ["classes[0].default_mechanisms"])


class TestUnitValidation(base.CatalogTestCase):
    def check(self, mechanisms):
        return fields(self.validate(base.complete_unit(mechanisms=mechanisms)))

    def test_valid_values(self):
        for mechs in [{"launcher": {"traverse_deg": "full"}}, {"launcher": {"traverse_deg": [-30, 30]}},
                      {"launcher": {"max_elevation_deg": 55, "stowed": "front"}},
                      {"turret_traverse": {"elevation_deg": [-10, 25]}}, {"wheels": {}}]:  # fmt: skip
            self.assertEqual(self.check(mechs), [], mechs)

    def test_invalid_values_name_the_field(self):
        cases = [
            ({"launcher": {"traverse_deg": [10, 30]}}, "mechanisms.launcher.traverse_deg"),
            ({"launcher": {"traverse_deg": [-200, 30]}}, "mechanisms.launcher.traverse_deg"),
            ({"launcher": {"traverse_deg": [30, -30]}}, "mechanisms.launcher.traverse_deg"),
            ({"launcher": {"traverse_deg": [0, 0]}}, "mechanisms.launcher.traverse_deg"),
            ({"launcher": {"traverse_deg": [-30]}}, "mechanisms.launcher.traverse_deg"),
            ({"launcher": {"max_elevation_deg": 0}}, "mechanisms.launcher.max_elevation_deg"),
            ({"launcher": {"max_elevation_deg": 91}}, "mechanisms.launcher.max_elevation_deg"),
            ({"launcher": {"max_elevation_deg": True}}, "mechanisms.launcher.max_elevation_deg"),
            ({"launcher": {"stowed": "side"}}, "mechanisms.launcher.stowed"),
            ({"turret_traverse": {"elevation_deg": "full"}}, "mechanisms.turret_traverse.elevation_deg"),
            ({"jetpack": {}}, "mechanisms.jetpack"),
            ({"launcher": {"speed": 3}}, "mechanisms.launcher.speed"),
            ({"launcher": "full"}, "mechanisms.launcher"),
        ]  # fmt: skip
        for mechs, field in cases:
            self.assertEqual(self.check(mechs), [field], mechs)

    def test_mechanisms_must_be_an_object(self):
        self.assertEqual(self.check([]), ["mechanisms"])

    def test_provenance_paths_validated_against_registry(self):
        ok = {"mechanisms.launcher": {"source": SRC, "verified": True},
              "mechanisms.launcher.stowed": {"source": SRC, "verified": True}}  # fmt: skip
        self.assertEqual(fields(self.validate(base.complete_unit(provenance=ok))), [])
        for bad in ["mechanisms.jetpack", "mechanisms.launcher.speed", "mechanisms.wheels.x", "mechanisms"]:
            errors = self.validate(base.complete_unit(provenance={bad: {"verified": True}}))
            self.assertEqual(fields(errors), ["provenance." + bad], bad)


class TestSaving(base.CatalogTestCase):
    def test_missing_params_are_filled_with_defaults(self):
        saved = catalog.save_unit(self.root, base.complete_unit(mechanisms={"launcher": {}}))
        self.assertEqual(saved["mechanisms"], {"launcher": {"traverse_deg": "full", "max_elevation_deg": 40, "stowed": "rear"}})
        prov = saved["provenance"]
        for name in ("traverse_deg", "max_elevation_deg", "stowed"):
            self.assertEqual(prov["mechanisms.launcher." + name], {"source": "default", "verified": False})
        self.assertEqual(len(prov), 3)

    def test_keys_are_written_in_registry_order(self):
        unit = base.complete_unit(mechanisms={
            "launcher": {"stowed": "front", "traverse_deg": [-30, 30]}, "wheels": {}, "stabilisers": {}})  # fmt: skip
        unit["provenance"] = {"mechanisms.stabilisers": {"verified": True}, "mechanisms.launcher.stowed": {"verified": True},
                              "crew": {"verified": True}, "mechanisms.wheels": {"verified": True}}  # fmt: skip
        catalog.save_unit(self.root, unit)
        text = (catalog.unit_dir(self.root, "leopard_2a4") / "unit.json").read_text(encoding="utf-8")
        stored = json.loads(text)
        self.assertEqual(list(stored["mechanisms"]), ["wheels", "launcher", "stabilisers"])
        self.assertEqual(list(stored["mechanisms"]["launcher"]), ["traverse_deg", "max_elevation_deg", "stowed"])
        # traverse_deg was given without provenance (human value), max_elevation_deg was defaulted
        self.assertEqual(list(stored["provenance"]), ["crew", "mechanisms.wheels", "mechanisms.launcher.max_elevation_deg",
                                                       "mechanisms.launcher.stowed", "mechanisms.stabilisers"])  # fmt: skip
        keys = list(stored)
        self.assertLess(keys.index("silhouette_features"), keys.index("mechanisms"))
        self.assertLess(keys.index("mechanisms"), keys.index("images"))

    def test_empty_mechanisms_object_is_dropped_but_empty_params_kept(self):
        saved = catalog.save_unit(self.root, base.complete_unit(mechanisms={"wheels": {}}))
        self.assertEqual(saved["mechanisms"], {"wheels": {}})
        saved = catalog.save_unit(self.root, base.complete_unit(mechanisms={}))
        self.assertNotIn("mechanisms", saved)

    def test_saving_twice_does_not_bump_revision(self):
        first = catalog.save_unit(self.root, base.complete_unit(mechanisms={"launcher": {}}))
        again = catalog.save_unit(self.root, catalog.load_unit(self.root, "leopard_2a4"))
        self.assertEqual(first["revision"], again["revision"])

    def test_removing_a_mechanism_removes_its_provenance(self):
        catalog.save_unit(self.root, base.complete_unit(mechanisms={"wheels": {}, "launcher": {}},
                                                        provenance={"mechanisms.launcher": {"source": SRC, "verified": True},
                                                                    "crew": {"verified": True}}))  # fmt: skip
        unit = catalog.load_unit(self.root, "leopard_2a4")
        del unit["mechanisms"]["launcher"]
        saved = catalog.save_unit(self.root, unit)
        self.assertEqual(list(saved["provenance"]), ["crew"])

    def test_invalid_mechanism_is_not_saved(self):
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.save_unit(self.root, base.complete_unit(mechanisms={"launcher": {"max_elevation_deg": 91}}))
        self.assertEqual(fields(ctx.exception.errors), ["mechanisms.launcher.max_elevation_deg"])

    def test_ready_for_model_with_defaults_is_blocked(self):
        with self.assertRaises(catalog.CatalogError) as ctx:
            catalog.save_unit(self.root, base.complete_unit(mechanisms={"launcher": {}}, status="ready_for_model"))
        self.assertIn("verify mechanisms.launcher.stowed (default)", ctx.exception.errors[0]["missing"])


class TestCreateAndReadiness(base.CatalogTestCase):
    def setUp(self):
        super().setUp()
        classes = copy.deepcopy(base.CLASSES) + [
            {"id": "mlrs", "label": "MLRS", "mobility": "wheeled", "required_views": ["side"],
             "default_mechanisms": ["wheels", "launcher", "stabilisers"]},
        ]  # fmt: skip
        catalog.save_classes(self.root, classes)
        self.classes = classes

    def test_create_unit_prefills_class_defaults(self):
        unit = catalog.create_unit(self.root, "Test MLRS", "test_mlrs", **{"class": "mlrs"})
        self.assertEqual(unit["mechanisms"], {"wheels": {}, "stabilisers": {},
                                              "launcher": {"traverse_deg": "full", "max_elevation_deg": 40, "stowed": "rear"}})  # fmt: skip
        self.assertEqual(list(unit["mechanisms"]), ["wheels", "launcher", "stabilisers"])
        expected = ["mechanisms.wheels", "mechanisms.launcher", "mechanisms.launcher.traverse_deg",
                    "mechanisms.launcher.max_elevation_deg", "mechanisms.launcher.stowed", "mechanisms.stabilisers"]  # fmt: skip
        self.assertEqual(list(unit["provenance"]), expected)
        for entry in unit["provenance"].values():
            self.assertEqual(entry, {"source": "class default", "verified": False})

    def test_class_without_defaults_gets_no_mechanisms(self):
        unit = catalog.create_unit(self.root, "Some tank", "some_tank", **{"class": "tank"})
        self.assertNotIn("mechanisms", unit)

    def test_readiness_lists_unverified_mechanisms_until_verified(self):
        unit = catalog.create_unit(self.root, "Test MLRS", "test_mlrs", **{"class": "mlrs"})
        unit.update(base.complete_unit(id="test_mlrs", **{"class": "mlrs"}))
        unit["mechanisms"] = catalog.load_unit(self.root, "test_mlrs")["mechanisms"]
        unit["provenance"] = catalog.load_unit(self.root, "test_mlrs")["provenance"]
        missing = catalog.readiness_missing(unit)
        self.assertEqual(missing[0], "verify mechanisms.wheels (default)")
        self.assertEqual(len(missing), 6)
        self.assertIn("verify mechanisms.launcher.stowed (default)", missing)
        for entry in unit["provenance"].values():
            entry["verified"] = True
        self.assertEqual(catalog.readiness_missing(unit), [])

    def test_researched_unverified_value_says_ai(self):
        unit = base.complete_unit(provenance={"mechanisms.launcher": {"source": SRC, "verified": False}})
        self.assertIn("verify mechanisms.launcher (AI)", catalog.readiness_missing(unit))

    def test_empty_or_missing_mechanisms_is_not_ready(self):
        for unit in [base.complete_unit(mechanisms={}), {k: v for k, v in base.complete_unit().items() if k != "mechanisms"}]:
            self.assertEqual(catalog.readiness_missing(unit), ["mechanisms"])


class TestMergeMechanisms(base.CatalogTestCase):
    def setUp(self):
        super().setUp()
        catalog.create_unit(self.root, "Homar K", "homar_k", operators=["poland"])

    def merge(self, fields_, unit=None):
        unit = unit or catalog.load_unit(self.root, "homar_k")
        report = catalog.merge_research(unit, {"fields": fields_}, base.CLASSES, ["poland"],
                                        catalog.load_mechanisms(self.root))
        return unit, report

    def test_new_mechanism_is_added_unverified(self):
        unit, report = self.merge({"mechanisms.blast_shields": {"value": {}, "source": SRC}})
        self.assertEqual(unit["mechanisms"], {"blast_shields": {}})
        self.assertEqual(unit["provenance"]["mechanisms.blast_shields"], {"source": SRC, "verified": False})
        self.assertEqual(report["filled"], ["mechanisms.blast_shields"])
        saved = catalog.save_unit(self.root, unit)
        self.assertIn("blast_shields", saved["mechanisms"])

    def test_param_of_undeclared_mechanism_adds_the_mechanism(self):
        unit, report = self.merge({"mechanisms.launcher.stowed": {"value": "front", "source": SRC}})
        self.assertEqual(unit["mechanisms"], {"launcher": {"stowed": "front"}})
        self.assertEqual(unit["provenance"]["mechanisms.launcher"], {"source": SRC, "verified": False})
        self.assertEqual(unit["provenance"]["mechanisms.launcher.stowed"], {"source": SRC, "verified": False})
        self.assertEqual(report["rejected"], [])
        saved = catalog.save_unit(self.root, unit)  # the other params get their defaults
        self.assertEqual(saved["mechanisms"]["launcher"]["traverse_deg"], "full")

    def human_set_unit(self):
        unit = catalog.load_unit(self.root, "homar_k")
        unit["mechanisms"] = {"launcher": {"traverse_deg": "full", "max_elevation_deg": 50, "stowed": "rear"}}
        unit["provenance"] = {"mechanisms.launcher": {"verified": True}}
        return catalog.save_unit(self.root, unit)

    def test_different_value_over_human_value_becomes_suggested(self):
        unit = self.human_set_unit()
        unit, report = self.merge({"mechanisms.launcher.max_elevation_deg": {"value": 55, "source": SRC}}, unit)
        self.assertEqual(unit["mechanisms"]["launcher"]["max_elevation_deg"], 50)
        entry = unit["provenance"]["mechanisms.launcher.max_elevation_deg"]
        self.assertEqual(entry["suggested"], 55)
        self.assertEqual(report["suggested"], ["mechanisms.launcher.max_elevation_deg"])

    def test_researched_value_replaces_a_default(self):
        unit = catalog.load_unit(self.root, "homar_k")
        unit["mechanisms"] = {"launcher": {}}
        unit = catalog.save_unit(self.root, unit)
        unit, report = self.merge({"mechanisms.launcher.max_elevation_deg": {"value": 55, "source": SRC}}, unit)
        self.assertEqual(unit["mechanisms"]["launcher"]["max_elevation_deg"], 55)
        self.assertEqual(unit["provenance"]["mechanisms.launcher.max_elevation_deg"], {"source": SRC, "verified": False})
        self.assertEqual(report["suggested"], [])

    def test_invalid_entries_are_rejected_and_reported(self):
        unit, report = self.merge({
            "mechanisms.launcher.max_elevation_deg": {"value": 120, "source": SRC},
            "mechanisms.stabilisers.x": {"value": 1, "source": SRC},
            "mechanisms.jetpack": {"value": {}, "source": SRC},
            "mechanisms.launcher": {"value": {"stowed": "front"}, "source": SRC},
        })  # fmt: skip
        self.assertEqual([r["field"] for r in report["rejected"]],
                         ["mechanisms.launcher.max_elevation_deg", "mechanisms.stabilisers.x", "mechanisms.jetpack",
                          "mechanisms.launcher"])  # fmt: skip
        self.assertNotIn("mechanisms", unit)
        self.assertEqual(unit.get("provenance", {}), {})


if __name__ == "__main__":
    unittest.main()


class TestShippedEntries(unittest.TestCase):
    def test_every_shipped_unit_validates(self):
        root = catalog.DEFAULT_ROOT
        classes = catalog.load_classes(root)
        factions = [f["id"] for f in catalog.load_factions(root)]
        registry = catalog.load_mechanisms(root)
        for uid in catalog.list_unit_ids(root):
            with self.subTest(unit=uid):
                unit = catalog.load_unit(root, uid)
                self.assertEqual(catalog.validate_unit(unit, classes, factions, registry), [])

    def test_homar_k_declares_its_mechanisms(self):
        unit = catalog.load_unit(catalog.DEFAULT_ROOT, "homar_k")
        self.assertEqual(unit["mechanisms"], {
            "wheels": {},
            "launcher": {"traverse_deg": "full", "max_elevation_deg": 40, "stowed": "rear"},
        })  # fmt: skip
        self._assert_mechanisms_verified(unit)

    def test_uragan_declares_its_verified_mechanisms(self):
        unit = catalog.load_unit(catalog.DEFAULT_ROOT, "bm27_uragan")
        self.assertEqual(unit["mechanisms"], {
            "wheels": {},
            "launcher": {"traverse_deg": [-30, 30], "max_elevation_deg": 55, "stowed": "front"},
            "stabilisers": {},
            "blast_shields": {},
        })  # fmt: skip
        self._assert_mechanisms_verified(unit)

    def _assert_mechanisms_verified(self, unit):
        prov = unit["provenance"]
        for mid, params in unit["mechanisms"].items():
            for path in ["mechanisms." + mid] + ["mechanisms.%s.%s" % (mid, k) for k in params]:
                self.assertTrue(prov[path]["verified"], path)


class TestMechanismsHttp(base.ServerCase):
    """The registry reaches the UI and mechanisms round-trip through the HTTP handler (TASK-042)."""

    def setUp(self):
        super().setUp()
        catalog.create_unit(self.root, "Leopard 2A4", "leopard_2a4", **{"class": "tank", "operators": ["poland"]})

    def put(self, **over):
        return self.jreq("PUT", "/api/units/leopard_2a4", base.complete_unit(**over))

    def test_catalog_contains_the_registry(self):
        status, data = self.jreq("GET", "/api/catalog")
        self.assertEqual(status, 200)
        self.assertEqual(data["mechanisms"], catalog.load_mechanisms(self.root))
        self.assertEqual([m["id"] for m in data["mechanisms"]][:3], ["wheels", "squad_march", "launcher"])
        self.assertEqual(data["classes"][0].get("default_mechanisms", []), [])

    def test_traverse_without_zero_is_a_400_naming_the_field(self):
        status, data = self.put(mechanisms={"launcher": {"traverse_deg": [10, 30]}})
        self.assertEqual(status, 400)
        self.assertEqual(fields(data["errors"]), ["mechanisms.launcher.traverse_deg"])

    def test_valid_put_round_trips_in_registry_order(self):
        mechs = {"wheels": {}, "launcher": {"traverse_deg": [-30, 30], "max_elevation_deg": 55, "stowed": "front"}}
        status, first = self.put(mechanisms=mechs, provenance={"mechanisms.launcher": {"source": SRC, "verified": True}})
        self.assertEqual(status, 200)
        stored = first["unit"]
        self.assertEqual(stored["mechanisms"], mechs)
        self.assertEqual(list(stored["mechanisms"]["launcher"]), ["traverse_deg", "max_elevation_deg", "stowed"])
        status, second = self.jreq("PUT", "/api/units/leopard_2a4", stored)
        self.assertEqual(status, 200)
        self.assertEqual(second["unit"]["revision"], stored["revision"])  # unchanged content: no bump
        changed = copy.deepcopy(second["unit"])
        changed["mechanisms"]["launcher"]["max_elevation_deg"] = 50
        status, third = self.jreq("PUT", "/api/units/leopard_2a4", changed)
        self.assertEqual(third["unit"]["revision"], stored["revision"] + 1)

    def test_removing_a_mechanism_prunes_its_provenance(self):
        prov = {"mechanisms.launcher": {"source": SRC, "verified": True},
                "mechanisms.launcher.stowed": {"source": SRC, "verified": True}}  # fmt: skip
        status, data = self.put(mechanisms={"wheels": {}, "launcher": {}}, provenance=prov)
        self.assertEqual(status, 200)
        unit = data["unit"]
        del unit["mechanisms"]["launcher"]  # the client leaves the stale provenance in place
        status, data = self.jreq("PUT", "/api/units/leopard_2a4", unit)
        self.assertEqual(status, 200)
        self.assertFalse([p for p in data["unit"].get("provenance", {}) if p.startswith("mechanisms.launcher")])


class TestAppHasNoRegistryLiterals(unittest.TestCase):
    """The UI is built from `catalog.mechanisms`: no mechanism id or param name is hard-coded in app.js."""

    def test_app_js_does_not_name_registry_entries(self):
        source = (Path(__file__).resolve().parent / "app.js").read_text(encoding="utf-8")
        registry = catalog.load_mechanisms(catalog.DEFAULT_ROOT)
        names = {m["id"] for m in registry}
        for m in registry:
            names |= set(m.get("params", {}))
        # Every name is matched as a quoted literal and as a whole word (identifiers, strings, comments). A future
        # registry name that is also an ordinary word in app.js (e.g. "height") needs an exception here.
        self.assertGreater(len(names), 10)
        offenders = []
        for name in sorted(names):
            if re.search(r"""(["'`])%s\1""" % re.escape(name), source) or re.search(r"\b%s\b" % re.escape(name), source):
                offenders.append(name)
        self.assertEqual(offenders, [])
