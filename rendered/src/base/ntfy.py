# ntfy push for the Python scripts that run in place from the rendered tree, which import it
# with:
#   sys.path.insert(0, "/root/homelab-rendered/src/base")
#   import ntfy
# Standard library only.

import time
import urllib.request


def notify(url, token, priority, title, message, tags):
  """Posts to an ntfy topic and returns whether it got through. ntfy may still be starting
  after a reboot, so this retries for 4 minutes."""
  request = urllib.request.Request(url, data=message.encode(), headers={
      "Authorization": f"Bearer {token}", "X-Title": title, "X-Priority": str(priority),
      "X-Tags": tags})
  for attempt in range(9):
    try:
      urllib.request.urlopen(request, timeout=15).close()
      return True
    except OSError:
      if attempt < 8:
        time.sleep(30)
  return False
