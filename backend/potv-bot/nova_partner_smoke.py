"""Private NOVA service connection check: no tokens or media URLs printed."""
import os
from nova_partner import NovaPartner, NovaPartnerError

def main():
    path = os.getenv("POTV_NOVA_SERVICE_FILE", "").strip()
    if not path:
        raise SystemExit("NOT CONFIGURED: POTV_NOVA_SERVICE_FILE")
    service = NovaPartner.from_file(path)
    print("NOVA API version endpoint:", "reachable" if service.app_version() else "empty")
    for name, method in (("movies",service.movies),("series",service.series),
                         ("anime",service.anime),("channels",service.channels)):
        print(name, "returned", len(method()), "entries; playback NOT certified")
    print("NOVA API metadata handshake passed; Android QA remains mandatory.")

if __name__ == "__main__":
    try:main()
    except (OSError, ValueError, NovaPartnerError):
        raise SystemExit("NOVA API handshake failed (review server-only credentials, base URL, or availability)")
