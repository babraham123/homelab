#!/usr/bin/env python3
# Generate individual HAProxy map files PER COUNTRY from MaxMind GeoLite2 data.
# Usage:
#   /usr/local/bin/geoip_generator.py

import os
import sys
import shutil
import urllib.request
import urllib.error
import tarfile
import tempfile
import subprocess
import re
import glob
from pathlib import Path

output_dir = "/etc/haproxy/countries"
haproxy_mapper_bin = "/usr/local/bin/haproxy-mapper"
maxmind_license_file = "/etc/opt/secrets/maxmind_license_key"

def main():
  try:
    maxmind_key = Path(maxmind_license_file).read_text().strip()
  except Exception as e:
    print(f"Error: MaxMind license key not found. ({e})", file=sys.stderr)
    sys.exit(1)

  if not shutil.which(haproxy_mapper_bin):
    print(f"Error: Required command '{haproxy_mapper_bin}' not found in PATH.", file=sys.stderr)
    sys.exit(1)

  with tempfile.TemporaryDirectory() as tmp_dir:
    # Download Country Database
    db_url = f"https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key={maxmind_key}&suffix=tar.gz"
    tar_path = os.path.join(tmp_dir, "GeoLite2-Country.tar.gz")
    
    try:
      urllib.request.urlretrieve(db_url, tar_path)
    except urllib.error.URLError as e:
      print(f"Error: Download failed. ({e})", file=sys.stderr)
      sys.exit(1)

    # Extract Database
    with tarfile.open(tar_path, "r:gz") as tar:
      tar.extractall(path=tmp_dir)

    # Look for Country .mmdb
    country_db = None
    for root, _, files in os.walk(tmp_dir):
      for file in files:
        if file == "GeoLite2-Country.mmdb":
          country_db = os.path.join(root, file)
          break

    if not country_db:
      print("Error: GeoLite2-Country.mmdb not found in archive.", file=sys.stderr)
      sys.exit(1)

    # Generate Maps
    mapper_out = os.path.join(tmp_dir, "mapper_output")
    os.makedirs(mapper_out, exist_ok=True)
    try:
      # You can use -city-db pointing to a country file as they share schemas.
      subprocess.run(
        [haproxy_mapper_bin, "-outdir", mapper_out, "-city-db", country_db, "-country"],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
      )
    except subprocess.CalledProcessError:
      print("Error: haproxy-mapper execution failed.", file=sys.stderr)
      sys.exit(1)

    # Split Logic
    ip_to_country_file = os.path.join(mapper_out, "ip_to_country")
    os.makedirs(output_dir, exist_ok=True)
    for old_map in glob.glob(os.path.join(output_dir, "*.map")):
      os.remove(old_map)

    country_pattern = re.compile(r"^[A-Za-z0-9]+$")
    file_handles = {}
    try:
      with open(ip_to_country_file, "r") as f:
        for line in f:
          parts = line.strip().split()
          if len(parts) >= 2:
            cidr, country = parts[0], parts[1]
            if country_pattern.match(country):
              if country not in file_handles:
                file_handles[country] = open(os.path.join(output_dir, f"{country}.map"), "w")
              file_handles[country].write(f"{cidr}\n")
    finally:
      for fh in file_handles.values():
        fh.close()

    print(f"Successfully Generated {len(file_handles)} country files in: {output_dir}")

if __name__ == "__main__":
  main()
