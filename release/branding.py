"""Change display copy while preserving lookup keys, URLs and legal attribution."""

import re


_STRING = r'"(?:\\.|[^"\\])*"'
# Product names also touch CJK text and take suffixes in translated copy.
_BRAND = re.compile(r"Brave|Брейв", re.IGNORECASE)
_URL = re.compile(r"https?://[^\s\"<>]+")
_LEGAL = re.compile(r"copyright|©|Mozilla Public License|MPL-2\.0|Brave Software", re.IGNORECASE)


def _swift_string_end(text, start):
    quote_start = start
    while text[quote_start] == '#':
        quote_start += 1
    hashes = text[start:quote_start]
    quote = '"""' if text.startswith('"""', quote_start) else '"'
    closing = quote + hashes
    escape = '\\' + hashes
    index = quote_start + len(quote)
    while index < len(text):
        if text.startswith(closing, index):
            return index + len(closing)
        if text.startswith(escape + '(', index):
            index = _swift_paren_end(text, index + len(escape))
        elif text.startswith(escape, index):
            index += len(escape) + 1
        else:
            index += 1
    raise ValueError('Unterminated Swift string')


def _swift_token_end(text, index):
    if text[index] == '"' or (text[index] == '#' and re.match(r'#+"', text[index:index + 16])):
        return _swift_string_end(text, index)
    if text.startswith('//', index):
        end = text.find('\n', index)
        return len(text) if end == -1 else end + 1
    if text.startswith('/*', index):
        depth, cursor = 1, index + 2
        while cursor < len(text) and depth:
            if text.startswith('/*', cursor):
                depth += 1
                cursor += 2
            elif text.startswith('*/', cursor):
                depth -= 1
                cursor += 2
            else:
                cursor += 1
        return cursor
    return None


def _swift_paren_end(text, start):
    depth, index = 1, start + 1
    while index < len(text):
        end = _swift_token_end(text, index)
        if end is not None:
            index = end
            continue
        if text[index] == '(':
            depth += 1
        elif text[index] == ')':
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    raise ValueError('Unterminated Swift interpolation/call')


def rebrand_display_text(text):
    if not _BRAND.search(text) or _LEGAL.search(text):
        return text
    protected = []

    def protect(value):
        protected.append(value)
        return f"\x00PROTECTED{len(protected) - 1}\x00"

    parts, cursor, index = [], 0, 0
    while index < len(text):
        if text.startswith('\\\\', index):
            index += 2
            continue
        interpolation = re.match(r'\\#*\(', text[index:index + 16]) if text[index] == '\\' else None
        if interpolation:
            end = _swift_paren_end(text, index + interpolation.end() - 1)
            parts.extend((text[cursor:index], protect(text[index:end])))
            cursor = index = end
        else:
            index += 1
    parts.append(text[cursor:])
    result = re.sub(r'<[^>]*>|' + _URL.pattern, lambda match: protect(match.group(0)), ''.join(parts))
    result = _BRAND.sub("ATMA", result)
    for index, value in enumerate(protected):
        result = result.replace(f"\x00PROTECTED{index}\x00", value)
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
    if 'NSLocalizedString' not in source:
        return source
    changes, index = [], 0
    while index < len(source):
        end = _swift_token_end(source, index)
        if end is not None:
            index = end
            continue
        call = re.match(r'NSLocalizedString\s*\(', source[index:index + 40]) if source[index] == 'N' else None
        if call and (index == 0 or not (source[index - 1].isalnum() or source[index - 1] == '_')):
            end = _swift_paren_end(source, index + call.end() - 1)
            cursor = index + call.end()
            while cursor < end - 1:
                token_end = _swift_token_end(source, cursor)
                if token_end is not None:
                    cursor = token_end
                    continue
                if source[cursor] == '(':
                    cursor = _swift_paren_end(source, cursor)
                    continue
                value = re.match(r'\bvalue\s*:\s*', source[cursor:cursor + 40]) if source[cursor] == 'v' else None
                if value:
                    start = cursor + value.end()
                    if source[start] == '"' or re.match(r'#+"', source[start:start + 16]):
                        value_end = _swift_string_end(source, start)
                        changes.append((start, value_end, rebrand_display_text(source[start:value_end])))
                    break
                cursor += 1
            index = end
        else:
            index += 1
    for start, end, replacement in reversed(changes):
        source = source[:start] + replacement + source[end:]
    return source


def rebrand_swift_literals(source):
    """Change display literals in the UA module, preserving executable interpolation."""
    changes, index = [], 0
    while index < len(source):
        end = _swift_token_end(source, index)
        if end is not None:
            if source[index] in ('"', '#'):
                changes.append((index, end, rebrand_display_text(source[index:end])))
            index = end
        else:
            index += 1
    for start, end, replacement in reversed(changes):
        source = source[:start] + replacement + source[end:]
    return source


def rebrand_grit(source):
    pattern = re.compile(
        r'(?P<open><(?P<tag>message|translation)\b[^>]*>)(?P<value>.*?)(?P<close></(?P=tag)>)',
        re.DOTALL,
    )
    return pattern.sub(
        lambda match: match['open'] + rebrand_display_text(match['value']) + match['close'],
        source,
    )
