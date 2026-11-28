import importlib.util
import json
import plistlib
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[3] / 'scripts/check_localizations.py'


class LocalizationChecks(unittest.TestCase):
    def module(self):
        spec = importlib.util.spec_from_file_location('check_localizations', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_missing_translation_and_changed_placeholder_are_rejected(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'Localizable.xcstrings'
            translations = {language: {'stringUnit': {'state': 'translated', 'value': 'Game %@'}}
                            for language in module.LANGUAGES}
            path.write_text(json.dumps({'sourceLanguage': 'en', 'strings': {'Game %@': {'localizations': translations}}, 'version': '1.0'}))
            self.assertEqual(module.check_catalog(path), [])
            del translations['de']
            translations['it']['stringUnit']['value'] = 'Gioco %lld'
            path.write_text(json.dumps({'sourceLanguage': 'en', 'strings': {'Game %@': {'localizations': translations}}, 'version': '1.0'}))
            errors = module.check_catalog(path)
            self.assertTrue(any('de' in error for error in errors))
            self.assertTrue(any('placeholder' in error.lower() for error in errors))

    def test_symbol_names_never_go_through_translation(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / 'View.swift'
            source.write_text('Label(L10n.text("Live output"), systemImage: "terminal")\n')
            self.assertEqual(module.check_sources(Path(root)), [])
            source.write_text('Label(L10n.text("Live output"), systemImage: L10n.text("terminal"))\n')
            errors = module.check_sources(Path(root))
            self.assertEqual(len(errors), 1)
            self.assertIn('View.swift:1', errors[0])

    def test_french_formal_address_is_rejected(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'Localizable.xcstrings'
            translations = {language: {'stringUnit': {'state': 'translated', 'value': 'Game'}}
                            for language in module.LANGUAGES}
            catalog = {'sourceLanguage': 'en', 'strings': {'Game': {'localizations': translations}}, 'version': '1.0'}
            translations['fr']['stringUnit']['value'] = 'Il y a assez de jeux chez toi.'
            path.write_text(json.dumps(catalog))
            self.assertEqual(module.check_catalog(path), [])
            for formal in ('Vous jouez.', 'Votre jeu', 'Vos jeux', 'Le vôtre', 'Choisissez un jeu', 'Faites glisser', 'Réessayez.'):
                translations['fr']['stringUnit']['value'] = formal
                path.write_text(json.dumps(catalog))
                errors = module.check_catalog(path)
                self.assertTrue(errors and 'tu' in errors[0], formal)
            translations['fr'] = {'variations': {'plural': {
                'one': {'stringUnit': {'state': 'translated', 'value': 'Un jeu'}},
                'other': {'stringUnit': {'state': 'translated', 'value': 'Vos jeux'}}}}}
            path.write_text(json.dumps(catalog))
            self.assertEqual(len(module.check_catalog(path)), 1)
            pack = Path(root) / 'achievements-test.json'
            pack.write_text(json.dumps({'achievements': [{'id': 'a', 'title': {'fr': 'Coquillage'},
                                                          'description': {'fr': 'Trouvez un coquillage.'}}]}))
            self.assertEqual(len(module.check_achievements(Path(root))), 1)

    def test_empty_or_incomplete_bundle_is_rejected(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as root:
            catalog = Path(root) / 'Localizable.xcstrings'
            catalog.write_text('{"sourceLanguage": "en", "strings": {}}')
            errors = module.check_app(Path(root) / 'Missing.app', catalog)
            self.assertTrue(errors)
            self.assertTrue(any('bundle' in error.lower() or 'plist' in error.lower() for error in errors))

    def test_the_app_carries_its_source_catalogue_as_written(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as root:
            catalog = Path(root) / 'Localizable.xcstrings'
            catalog.write_text('{"sourceLanguage": "en", "strings": {}}')
            app = Path(root) / 'Game.app'
            info = app / 'Contents/Info.plist'
            info.parent.mkdir(parents=True)
            info.write_bytes(plistlib.dumps({'CFBundleLocalizations': list(module.LANGUAGES)}))
            shipped = app / 'Contents/Resources' / module.BUNDLE / 'Contents/Resources/Localizable.xcstrings'
            self.assertEqual(module.check_app(app, catalog), ['String catalogue missing from the app bundle'])
            shipped.parent.mkdir(parents=True)
            shipped.write_text('{"sourceLanguage": "en", "strings": {"Old": {}}}')
            self.assertEqual(module.check_app(app, catalog),
                             ['The app bundle carries another string catalogue than its source'])
            shipped.write_bytes(catalog.read_bytes())
            self.assertEqual(module.check_app(app, catalog), [])
