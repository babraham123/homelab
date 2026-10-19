# ntfy push for the Python scripts that run in place from the rendered tree, which import it
# with:
#   sys.path.insert(0, "/root/homelab-rendered/src/base")
#   import ntfy
# Standard library only.

import time
import urllib.error
import urllib.request


def notify(url, token, priority, title, message, tags, attempts=9):
  """Posts to an ntfy topic and returns whether it got through. ntfy may still be starting
  after a reboot, so by default this retries for 4 minutes; a rejected request (4xx other
  than 429) won't pass on a retry, so it fails at once."""
  request = urllib.request.Request(url, data=message.encode(), headers={
      "Authorization": f"Bearer {token}", "X-Title": title, "X-Priority": str(priority),
      "X-Tags": tags})
  for attempt in range(attempts):
    try:
      urllib.request.urlopen(request, timeout=15).close()
      return True
    except urllib.error.HTTPError as e:
      if 400 <= e.code < 500 and e.code != 429:
        return False
    except OSError:
      pass
    if attempt < attempts - 1:
      time.sleep(30)
  return False
