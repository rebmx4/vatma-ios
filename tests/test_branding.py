import importlib.util
import unittest
from pathlib import Path


MODULE = Path(__file__).resolve().parents[1] / "release" / "branding.py"
spec = importlib.util.spec_from_file_location("atma_branding", MODULE)
branding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(branding)


class BrandingTests(unittest.TestCase):
    def test_localized_values_keep_lookup_keys_and_format_arguments(self):
        original = '/* Copyright The Brave Authors */\n"BraveWelcome" = "Welcome to Brave, %1$@";\n'
        self.assertEqual(
            branding.rebrand_strings(original),
            '/* Copyright The Brave Authors */\n"BraveWelcome" = "Welcome to ATMA, %1$@";\n',
        )

    def test_service_addresses_and_legal_notices_are_preserved(self):
        original = (
            '"Help" = "Brave help: https://support.brave.com/a?name=Brave";\n'
            '"License" = "Copyright 2026 The Brave Authors. MPL-2.0";\n'
        )
        updated = branding.rebrand_strings(original)
        self.assertIn('"ATMA help: https://support.brave.com/a?name=Brave"', updated)
        self.assertIn('"Copyright 2026 The Brave Authors. MPL-2.0"', updated)

    def test_swift_fallback_changes_only_display_value(self):
        source = 'NSLocalizedString("BraveTitle", tableName: "Brave", value: "Open in Brave", comment: "Brave title")'
        self.assertEqual(
            branding.rebrand_swift_values(source),
            'NSLocalizedString("BraveTitle", tableName: "Brave", value: "Open in ATMA", comment: "Brave title")',
        )

    def test_product_name_is_replaced_next_to_non_latin_text_and_inflections(self):
        self.assertEqual(
            branding.rebrand_strings('"BraveTitle" = "Brave浏览器 Braveで開く Brave에서 Bravelta";'),
            '"BraveTitle" = "ATMA浏览器 ATMAで開く ATMA에서 ATMAlta";',
        )

    def test_grit_message_keeps_identifier_and_placeholders(self):
        source = '<message name="IDS_BRAVE_TITLE" desc="Brave title">Open Brave <ph name="NUMBER">$1<ex>2</ex></ph></message>'
        expected = '<message name="IDS_BRAVE_TITLE" desc="Brave title">Open ATMA <ph name="NUMBER">$1<ex>2</ex></ph></message>'
        self.assertEqual(branding.rebrand_grit(source), expected)

    def test_grit_preserves_placeholder_attributes(self):
        source = '<message name="IDS_BRAVE"><ph name="BRAVE_ACCOUNT_BEGIN">$1</ph>Brave浏览器<ph name="BRAVE_ACCOUNT_END">$2</ph></message>'
        self.assertEqual(branding.rebrand_grit(source), source.replace('Brave浏览器', 'ATMA浏览器'))

    def test_nonlocalized_swift_values_and_interpolation_code_are_preserved(self):
        metric = r'Metric(value: "\(serpMetrics.braveSearchCountForYesterday)")'
        self.assertEqual(branding.rebrand_swift_values(metric), metric)
        source = r'NSLocalizedString("BraveKey", value: "Brave \(BraveCertificateUtils.name("x(y)"))", comment: "Brave title")'
        self.assertEqual(branding.rebrand_swift_values(source), source.replace('value: "Brave ', 'value: "ATMA '))

    def test_multiline_user_agent_literals_preserve_code_names(self):
        source = 'let braveUA = "Brave \\(braveMajorVersion)"\nreturn """\nMozilla \\(braveUA)\n"""'
        self.assertEqual(branding.rebrand_swift_literals(source), source.replace('= "Brave ', '= "ATMA '))

    def test_raw_localized_fallback_preserves_interpolation(self):
        source = 'NSLocalizedString("BraveKey", value: #"Brave \\#(BraveAPI.name)"#, comment: "Brave title")'
        self.assertEqual(branding.rebrand_swift_values(source), source.replace('value: #"Brave ', 'value: #"ATMA '))

    def test_repeated_preparation_does_not_change_output(self):
        source = r'"BraveTitle" = "Brave: \"Private\"";' + '\r\n'
        once = branding.rebrand_strings(source)
        self.assertEqual(branding.rebrand_strings(once), once)
        self.assertEqual(once, r'"BraveTitle" = "ATMA: \"Private\"";' + '\r\n')


if __name__ == "__main__":
    unittest.main()
