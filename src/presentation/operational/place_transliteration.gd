class_name PlaceTransliteration
extends RefCounted
## Latin transcription of Cyrillic place names (Belarusian / Russian), shown under the original
## on the staff map (TASK-112). Simplified Polish-readable scheme; pure maths, no nodes.

const _MAP := {
	"а": "a",
	"б": "b",
	"в": "w",
	"г": "g",
	"ґ": "g",
	"д": "d",
	"е": "e",
	"ё": "jo",
	"ж": "ż",
	"з": "z",
	"и": "i",
	"і": "i",
	"й": "j",
	"к": "k",
	"л": "l",
	"м": "m",
	"н": "n",
	"о": "o",
	"п": "p",
	"р": "r",
	"с": "s",
	"т": "t",
	"у": "u",
	"ў": "ŭ",
	"ф": "f",
	"х": "ch",
	"ц": "c",
	"ч": "cz",
	"ш": "sz",
	"щ": "szcz",
	"ъ": "",
	"ы": "y",
	"ь": "",
	"э": "e",
	"ю": "ju",
	"я": "ja",
	"є": "je",
	"ї": "ji",
	"'": "",
	"ʼ": "",
}  # gdlint: ignore=max-line-length

## Established Polish names of Belarusian towns, used instead of a letter-by-letter transcription.
const _KNOWN := {
	"Гродна": "Grodno",
	"Ліда": "Lida",
	"Слонім": "Słonim",
	"Масты": "Mosty",
	"Ваўкавыск": "Wołkowysk",
	"Шчучын": "Szczuczyn",
}


## The Latin transcription of `text`, or "" when it has no Cyrillic letters.
static func latin(text: String) -> String:
	if _KNOWN.has(text):
		return _KNOWN[text]
	var out := ""
	var found := false
	for i in text.length():
		var ch := text[i]
		var key := ch.to_lower()
		if _MAP.has(key):
			found = true
			var piece: String = _MAP[key]
			if ch != key and not piece.is_empty():
				piece = piece.substr(0, 1).to_upper() + piece.substr(1)
			out += piece
		else:
			out += ch
	return out if found else ""
