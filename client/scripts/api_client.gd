extends Node
## ApiClient: /health and /v1/memory/update via HTTPRequest; streamed /v1/chat via a
## polled HTTPClient so the game loop never blocks (SPEC 5.3). Events are newline-delimited JSON.

signal text_delta(request_id: String, text: String)
signal reply_done(request_id: String, speaker_id: String, addressee: String)
signal reply_failed(request_id: String, message: String)
signal health_checked(ok: bool, mode: String)

const TIMEOUT_S := 90.0

var base_url: String
## The most recent /v1/chat body per speaker, kept in memory only, so tests and
## developers can inspect exactly what context a character was given (SPEC 10.4-3).
var last_chat_requests: Dictionary = {}
var _host: String
var _port: int
var _streams: Dictionary = {}  # request_id -> _Stream


class _Stream:
	var http := HTTPClient.new()
	var body: String
	var sent := false
	var buffer := PackedByteArray()
	var elapsed := 0.0


func _ready() -> void:
	base_url = String(Defs.config.backend_url).trim_suffix("/")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--backend-url="):
			base_url = arg.get_slice("=", 1).trim_suffix("/")
	var host_port := base_url.trim_prefix("http://").get_slice("/", 0)
	_host = host_port.get_slice(":", 0)
	_port = int(host_port.get_slice(":", 1)) if ":" in host_port else 80


func check_health() -> void:
	var req := HTTPRequest.new()
	req.timeout = 5.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _headers, body: PackedByteArray) -> void:
		req.queue_free()
		var data: Variant = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
		if result == HTTPRequest.RESULT_SUCCESS and data is Dictionary:
			health_checked.emit(true, str(data.get("mode", "?")))
		else:
			health_checked.emit(false, ""))
	if req.request(base_url + "/health") != OK:
		req.queue_free()
		health_checked.emit(false, "")


## One-shot JSON POST (memory updates). Calls on_result(code, data); code 0 means
## the backend could not be reached.
func post_json(path: String, body: Dictionary, on_result: Callable, timeout := 60.0) -> void:
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _headers, raw: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			on_result.call(0, null)
		else:
			on_result.call(code, JSON.parse_string(raw.get_string_from_utf8())))
	var headers := ["Content-Type: application/json"]
	if req.request(base_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		req.queue_free()
		on_result.call(0, null)


func stream_chat(body: Dictionary) -> void:
	last_chat_requests[body.speaker_id] = body
	var s := _Stream.new()
	s.body = JSON.stringify(body)
	_streams[body.request_id] = s
	if s.http.connect_to_host(_host, _port) != OK:
		_fail(body.request_id, "Could not open a connection to the local backend.")


func cancel(request_id: String) -> void:
	if _streams.has(request_id):
		_streams[request_id].http.close()
		_streams.erase(request_id)


func is_streaming(request_id: String) -> bool:
	return _streams.has(request_id)


func _process(delta: float) -> void:
	for id: String in _streams.keys():
		_poll(id, _streams[id], delta)


func _poll(id: String, s: _Stream, delta: float) -> void:
	s.elapsed += delta
	if s.elapsed > TIMEOUT_S:
		_fail(id, "The reply took too long.")
		return
	s.http.poll()
	match s.http.get_status():
		HTTPClient.STATUS_CONNECTED:
			if not s.sent:
				s.sent = true
				var headers := ["Content-Type: application/json", "Accept: application/x-ndjson"]
				if s.http.request(HTTPClient.METHOD_POST, "/v1/chat", headers, s.body) != OK:
					_fail(id, "Could not send the message to the local backend.")
			else:
				_fail(id, "The backend ended the reply early.")
		HTTPClient.STATUS_BODY:
			var code := s.http.get_response_code()
			if code != 200:
				_fail(id, "The local backend rejected the request (HTTP %d)." % code)
				return
			var chunk := s.http.read_response_body_chunk()
			if not chunk.is_empty():
				s.buffer.append_array(chunk)
				_drain(id, s)
		HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, \
		HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_fail(id, "Can't reach the local backend at %s. Is it running?" % base_url)
		HTTPClient.STATUS_DISCONNECTED:
			if s.sent:
				_fail(id, "The connection to the backend closed unexpectedly.")


## Splits buffered bytes on newlines; decodes UTF-8 only for complete records.
func _drain(id: String, s: _Stream) -> void:
	while _streams.has(id):
		var nl := s.buffer.find(10)
		if nl == -1:
			return
		var line := s.buffer.slice(0, nl).get_string_from_utf8()
		s.buffer = s.buffer.slice(nl + 1)
		if line.strip_edges().is_empty():
			continue
		var ev: Variant = JSON.parse_string(line)
		if not ev is Dictionary:
			_fail(id, "The backend sent an unreadable reply.")
			return
		match ev.get("type"):
			"text_delta":
				text_delta.emit(id, str(ev.get("text", "")))
			"done":
				cancel(id)
				reply_done.emit(id, str(ev.get("speaker_id", "")), str(ev.get("addressee", "player")))
			"error":
				_fail(id, str(ev.get("message", "The reply failed.")))


func _fail(id: String, message: String) -> void:
	cancel(id)
	reply_failed.emit(id, message)
