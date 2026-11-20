"""Recursive-descent parser for Godot 4 text resource (.tres) save files."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
from typing import Any


class TresParseError(ValueError):
    """Raised when a .tres resource file is empty, incomplete, or malformed."""


@dataclass(frozen=True, slots=True)
class _Token:
    kind: str
    value: Any
    pos: int


_RESOURCE_HEADER_RE = re.compile(r"^\[resource(?:\s+[^\]]*)?\]$")
_NUMBER_RE = re.compile(r"[+-]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?")
_IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

_SINGLE_CHAR_TOKENS = {
    "{": "LBRACE",
    "}": "RBRACE",
    "[": "LBRACKET",
    "]": "RBRACKET",
    "(": "LPAREN",
    ")": "RPAREN",
    ":": "COLON",
    ",": "COMMA",
    "=": "EQUALS",
    "/": "SLASH",
}

_SIMPLE_ESCAPES = {
    '"': '"',
    "'": "'",
    "\\": "\\",
    "/": "/",
    "a": "\a",
    "b": "\b",
    "f": "\f",
    "n": "\n",
    "r": "\r",
    "t": "\t",
    "v": "\v",
}


def _find_resource_body_start(text: str) -> int:
    """Locate the byte/char offset immediately after the `[resource]` section header."""
    n = len(text)
    i = 0
    depth = 0
    in_string = False
    escaped = False
    at_line_start = True

    while i < n:
        ch = text[i]

        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            elif ch == "\n":
                at_line_start = False
            i += 1
            continue

        if at_line_start:
            while i < n and text[i] in (" ", "\t"):
                i += 1
            if i >= n:
                break
            ch = text[i]
            if ch == ";":
                nl = text.find("\n", i)
                if nl < 0:
                    break
                i = nl + 1
                at_line_start = True
                continue
            if depth == 0 and ch == "[":
                nl = text.find("\n", i)
                line_end = n if nl < 0 else nl + 1
                raw_line = text[i:nl] if nl >= 0 else text[i:]
                stripped = raw_line.split(";", 1)[0].strip()
                if _RESOURCE_HEADER_RE.match(stripped):
                    return line_end
                i = line_end
                at_line_start = True
                continue
            at_line_start = False

        if ch == '"':
            in_string = True
        elif ch == ";":
            nl = text.find("\n", i)
            if nl < 0:
                break
            i = nl + 1
            at_line_start = True
            continue
        elif ch in ("{", "[", "("):
            depth += 1
        elif ch in ("}", "]", ")"):
            depth = max(0, depth - 1)
        elif ch == "\n":
            at_line_start = True

        i += 1

    raise TresParseError("Missing [resource] section in .tres file")


def _parse_string(text: str, pos: int) -> tuple[str, int]:
    """Parse a double-quoted Godot string starting at `pos` (opening quote)."""
    n = len(text)
    if pos >= n or text[pos] != '"':
        raise TresParseError(f"Expected string at position {pos}")

    i = pos + 1
    chars: list[str] = []
    while i < n:
        ch = text[i]
        if ch == '"':
            return "".join(chars), i + 1
        if ch == "\\":
            i += 1
            if i >= n:
                raise TresParseError(f"Unterminated escape sequence at position {pos}")
            esc = text[i]
            if esc in _SIMPLE_ESCAPES:
                chars.append(_SIMPLE_ESCAPES[esc])
                i += 1
            elif esc == "u":
                hex_part = text[i + 1 : i + 5]
                if len(hex_part) != 4:
                    raise TresParseError(f"Invalid \\u escape at position {i}")
                try:
                    chars.append(chr(int(hex_part, 16)))
                except ValueError as exc:
                    raise TresParseError(f"Invalid \\u escape at position {i}") from exc
                i += 5
            elif esc == "U":
                hex_part = text[i + 1 : i + 9]
                if len(hex_part) != 8:
                    raise TresParseError(f"Invalid \\U escape at position {i}")
                try:
                    chars.append(chr(int(hex_part, 16)))
                except ValueError as exc:
                    raise TresParseError(f"Invalid \\U escape at position {i}") from exc
                i += 9
            elif esc == "x":
                hex_part = text[i + 1 : i + 3]
                if len(hex_part) != 2:
                    raise TresParseError(f"Invalid \\x escape at position {i}")
                try:
                    chars.append(chr(int(hex_part, 16)))
                except ValueError as exc:
                    raise TresParseError(f"Invalid \\x escape at position {i}") from exc
                i += 3
            else:
                chars.append(esc)
                i += 1
        else:
            chars.append(ch)
            i += 1

    raise TresParseError(f"Unterminated string literal starting at position {pos}")


def _tokenize(text: str, start: int) -> list[_Token]:
    """Tokenize the `[resource]` section body starting at `start`."""
    tokens: list[_Token] = []
    n = len(text)
    i = start

    while i < n:
        ch = text[i]
        if ch in (" ", "\t", "\r", "\n"):
            i += 1
            continue
        if ch == ";":
            nl = text.find("\n", i)
            if nl < 0:
                break
            i = nl + 1
            continue

        if ch in _SINGLE_CHAR_TOKENS:
            tokens.append(_Token(_SINGLE_CHAR_TOKENS[ch], ch, i))
            i += 1
            continue

        if ch in ("&", "^") and i + 1 < n and text[i + 1] == '"':
            val, next_i = _parse_string(text, i + 1)
            tokens.append(_Token("STRING", val, i))
            i = next_i
            continue

        if ch == '"':
            val, next_i = _parse_string(text, i)
            tokens.append(_Token("STRING", val, i))
            i = next_i
            continue

        if ch in ("-", "+") and text[i + 1 : i + 4] == "inf":
            after = i + 4
            if after >= n or not (text[after].isalnum() or text[after] == "_"):
                val = float("-inf") if ch == "-" else float("inf")
                tokens.append(_Token("NUMBER", val, i))
                i = after
                continue

        num_match = _NUMBER_RE.match(text, i)
        if num_match:
            raw = num_match.group(0)
            if "." in raw or "e" in raw or "E" in raw:
                tokens.append(_Token("NUMBER", float(raw), i))
            else:
                tokens.append(_Token("NUMBER", int(raw), i))
            i = num_match.end()
            continue

        ident_match = _IDENT_RE.match(text, i)
        if ident_match:
            tokens.append(_Token("IDENT", ident_match.group(0), i))
            i = ident_match.end()
            continue

        raise TresParseError(f"Unexpected character {ch!r} at position {i}")

    tokens.append(_Token("EOF", None, n))
    return tokens


class _Parser:
    """Recursive-descent parser over Godot `.tres` `[resource]` tokens."""

    def __init__(self, tokens: list[_Token]) -> None:
        self._tokens = tokens
        self._idx = 0

    def _peek(self, offset: int = 0) -> _Token:
        pos = min(self._idx + offset, len(self._tokens) - 1)
        return self._tokens[pos]

    def _advance(self) -> _Token:
        tok = self._tokens[self._idx]
        if self._idx < len(self._tokens) - 1:
            self._idx += 1
        return tok

    def _expect(self, kind: str) -> _Token:
        tok = self._peek()
        if tok.kind != kind:
            raise TresParseError(f"Expected {kind}, got {tok.kind} ({tok.value!r}) at position {tok.pos}")
        return self._advance()

    def parse_resource(self) -> dict[str, Any]:
        props: dict[str, Any] = {}
        while True:
            tok = self._peek()
            if tok.kind == "EOF":
                break
            # Next [section] header starts outside any container.
            if tok.kind == "LBRACKET":
                break
            key = self._parse_property_key()
            self._expect("EQUALS")
            val = self._parse_value()
            props[key] = val
        return props

    def _parse_property_key(self) -> str:
        tok = self._peek()
        if tok.kind == "STRING":
            return str(self._advance().value)
        if tok.kind != "IDENT":
            raise TresParseError(
                f"Expected property name, got {tok.kind} ({tok.value!r}) at position {tok.pos}"
            )
        parts = [str(self._advance().value)]
        while self._peek().kind == "SLASH":
            self._advance()
            seg = self._expect("IDENT")
            parts.append(str(seg.value))
        return "/".join(parts)

    def _parse_value(self) -> Any:
        tok = self._peek()
        if tok.kind == "LBRACE":
            return self._parse_dict()
        if tok.kind == "LBRACKET":
            return self._parse_array()
        if tok.kind in ("STRING", "NUMBER"):
            return self._advance().value
        if tok.kind == "IDENT":
            ident = str(self._advance().value)
            if ident == "true":
                return True
            if ident == "false":
                return False
            if ident == "null":
                return None
            if ident == "inf":
                return float("inf")
            if ident == "nan":
                return float("nan")

            # Typed Godot 4 containers like Dictionary[int, Dictionary]({...})
            # or Array[String]([...])
            if self._peek().kind == "LBRACKET":
                self._skip_balanced("LBRACKET", "RBRACKET")
                self._expect("LPAREN")
                return self._parse_container_or_call(ident)

            # Resource/type constructors like ExtResource("1"), SubResource("x"), Vector2(0, 0)
            if self._peek().kind == "LPAREN":
                self._advance()
                return self._parse_container_or_call(ident)

            return ident

        raise TresParseError(f"Unexpected token {tok.kind} ({tok.value!r}) at position {tok.pos}")

    def _parse_container_or_call(self, ident: str) -> Any:
        if ident == "Dictionary" and self._peek().kind == "LBRACE":
            result = self._parse_dict()
            self._expect("RPAREN")
            return result
        if ident == "Array" and self._peek().kind == "LBRACKET":
            result = self._parse_array()
            self._expect("RPAREN")
            return result

        depth = 1
        while depth > 0:
            tok = self._advance()
            if tok.kind == "EOF":
                raise TresParseError(f"Unterminated call '{ident}(...)' at position {tok.pos}")
            if tok.kind == "LPAREN":
                depth += 1
            elif tok.kind == "RPAREN":
                depth -= 1
        return None

    def _skip_balanced(self, open_kind: str, close_kind: str) -> None:
        self._expect(open_kind)
        depth = 1
        while depth > 0:
            tok = self._advance()
            if tok.kind == "EOF":
                raise TresParseError(f"Unterminated {open_kind} type annotation at position {tok.pos}")
            if tok.kind == open_kind:
                depth += 1
            elif tok.kind == close_kind:
                depth -= 1

    def _parse_dict(self) -> dict[Any, Any]:
        self._expect("LBRACE")
        result: dict[Any, Any] = {}
        while self._peek().kind != "RBRACE":
            if self._peek().kind == "EOF":
                raise TresParseError("Unterminated dictionary '{' in .tres file")
            key = self._parse_dict_key()
            self._expect("COLON")
            val = self._parse_value()
            result[key] = val
            if self._peek().kind == "COMMA":
                self._advance()
                continue
            if self._peek().kind != "RBRACE":
                tok = self._peek()
                raise TresParseError(
                    f"Expected ',' or '}}' in dictionary, got {tok.kind} at position {tok.pos}"
                )
        self._expect("RBRACE")
        return result

    def _parse_dict_key(self) -> Any:
        tok = self._peek()
        if tok.kind in ("STRING", "NUMBER", "IDENT"):
            return self._advance().value
        raise TresParseError(
            f"Unsupported dictionary key {tok.kind} ({tok.value!r}) at position {tok.pos}"
        )

    def _parse_array(self) -> list[Any]:
        self._expect("LBRACKET")
        items: list[Any] = []
        while self._peek().kind != "RBRACKET":
            if self._peek().kind == "EOF":
                raise TresParseError("Unterminated array '[' in .tres file")
            items.append(self._parse_value())
            if self._peek().kind == "COMMA":
                self._advance()
                continue
            if self._peek().kind != "RBRACKET":
                tok = self._peek()
                raise TresParseError(
                    f"Expected ',' or ']' in array, got {tok.kind} at position {tok.pos}"
                )
        self._expect("RBRACKET")
        return items


def parse_tres_text(text: str) -> dict[str, Any]:
    """Parse SaveData fields from the `[resource]` section of a `.tres` string."""
    if not text or not text.strip():
        raise TresParseError("Empty .tres content")

    body_start = _find_resource_body_start(text)
    tokens = _tokenize(text, body_start)
    props = _Parser(tokens).parse_resource()

    raw_name = props.get("player_name", "PLAYER")
    player_name = raw_name if isinstance(raw_name, str) and raw_name.strip() else "PLAYER"
    records = props.get("records")
    player_profiles = props.get("player_profiles")

    return {
        "player_name": player_name,
        "records": records if isinstance(records, dict) else {},
        "player_profiles": player_profiles if isinstance(player_profiles, dict) else {},
    }


def parse_tres_file(path: Path) -> dict[str, Any]:
    """Read and parse a `.tres` save file using UTF-8 (with optional BOM)."""
    content = path.read_text(encoding="utf-8-sig")
    return parse_tres_text(content)
