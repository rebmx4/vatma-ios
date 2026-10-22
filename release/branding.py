"""Change display copy while preserving lookup keys, URLs and legal attribution."""

import re


_STRING = r'"(?:\\.|[^"\\])*"'
# Product names also touch CJK text and take suffixes in translated copy.
_BRAND = re.compile(r"Brave|Брейв", re.IGNORECASE)
_URL = re.compile(r"https?://[^\s\"<>]+")
_LEGAL = re.compile(r"copyright|©|Mozilla Public License|MPL-2\.0|Brave Software", re.IGNORECASE)


def rebrand_display_text(text):
    if _LEGAL.search(text):
        return text
    urls = []

    def protect_url(match):
        urls.append(match.group(0))
        return f"\x00URL{len(urls) - 1}\x00"

    result = _BRAND.sub("ATMA", _URL.sub(protect_url, text))
    for index, url in enumerate(urls):
        result = result.replace(f"\x00URL{index}\x00", url)
    return result


def rebrand_strings(source):
    """Edit only the value of an Apple .strings entry, including escaped quotes."""
    pattern = re.compile(rf'(?P<prefix>{_STRING}\s*=\s*)(?P<value>{_STRING})(?P<suffix>\s*;)')
    return pattern.sub(
        lambda match: match['prefix'] + rebrand_display_text(match['value']) + match['suffix'],
        source,
    )


def rebrand_swift_values(source):
    """Edit NSLocalizedString fallback values; table and lookup names stay stable."""
    pattern = re.compile(rf'(?P<prefix>\bvalue\s*:\s*)(?P<value>{_STRING})')
    return pattern.sub(
        lambda match: match['prefix'] + rebrand_display_text(match['value']), source
    )


def rebrand_grit(source):
    pattern = re.compile(
        r'(?P<open><(?P<tag>message|translation)\b[^>]*>)(?P<value>.*?)(?P<close></(?P=tag)>)',
        re.DOTALL,
    )
    return pattern.sub(
        lambda match: match['open'] + rebrand_display_text(match['value']) + match['close'],
        source,
    )
