-- client.lua runs inside mGBA, which injects these as globals rather than requiring them --
read_globals = {
	"emu",
	"console",
	"callbacks",
	"socket",
}

globals = {
	"handleMessage",
}

-- Long lines happen in a few of the JSON-building string.format calls; not worth wrapping.
max_line_length = false
