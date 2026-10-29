"""Offline tests for the signed-stream decoder QA operator tool."""
from qa_signed_stream_decode import classify, choose

assert classify("", -11) == "DECODER_CRASH"
assert classify("", 139) == "DECODER_CRASH"
assert classify("HTTP error: Server returned 502 Bad Gateway", 8) == "HTTP_502"
assert classify("Invalid data found when processing input", 1) == "INVALID_MEDIA"
assert classify("unrecognized input", 1) == "DECODE_FAILED"

rows = [
    {"name": "TUDN", "id": "legacy", "hls_url": "https://example.invalid/a"},
    {"name": "TUDN", "id": "nova:42", "hls_url": "https://example.invalid/b"},
]
assert choose(rows, "tudn")["id"] == "nova:42"
assert choose(rows, "missing") is None

print("PASS: decoder crash classification and stable NOVA priority")
