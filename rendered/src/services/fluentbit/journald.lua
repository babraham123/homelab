-- /etc/opt/fluentbit/journald.lua
-- Script to parse systemd logs from journald
-- Ref:
--   https://docs.fluentbit.io/manual/pipeline/filters/lua
--   https://www.freedesktop.org/software/systemd/man/latest/systemd.journal-fields.html

-- devtop and gaming share one GPU, so one of them is usually off and vmagent logs its
-- unreachable exporter every scrape. Only the can't-connect errors go; anything else from a
-- running desktop's exporter stays.
local desktop_off_errors = {"no route to host", "context deadline exceeded",
  "Client.Timeout exceeded", "connection refused"}

function is_desktop_off(service, message)
  if service ~= "vmagent" or not message:find('job="nvidia_gpu_desktops"', 1, true) then
    return false
  end
  for _, err in ipairs(desktop_off_errors) do
    if message:find(err, 1, true) then
      return true
    end
  end
  return false
end

function process_msg(tag, timestamp, record)
  local retention_period = 14 * 24 * 60 * 60
  local now = os.time()
  local new_timestamp = timestamp
  if record["source_realtime_timestamp"] then
    new_timestamp = tonumber(record["source_realtime_timestamp"]) / 1e6
  end
  if (now - new_timestamp) > retention_period then
    return -1, new_timestamp, {}
  end

  local new_record = {}
  new_record["date"] = math.floor(new_timestamp * 1000)
  new_record["hostname"] = record["hostname"] or ""
  -- Host services have no container_name: name them after their unit, like the quadlets.
  -- The systemd input turns _SYSTEMD_UNIT into systemd_unit (strip_underscores, lowercase).
  new_record["service"] = record["container_name"]
    or (record["systemd_unit"] or ""):gsub("%.service$", "")
  new_record["message"] = record["message"] or ""
  if is_desktop_off(new_record["service"], new_record["message"]) then
    return -1, new_timestamp, {}
  end
  new_record["code"] = (record["code_func"] or "") .. " " .. (record["code_file"] or "") .. ":" .. (record["code_line"] or "")
  new_record["priority"] = record["priority"] or ""
  if record["errno"] then
    new_record["errno"] = record["errno"]
  end
  new_record["pid"] = record["pid"] or ""
  new_record["tid"] = record["tid"] or ""
  new_record["invocation_id"] = record["systemd_invocation_id"] or ""
  new_record["boot_id"] = record["boot_id"] or ""

  -- Traefik access log (src/services/traefik/static.yml.j2), already split by the json parser:
  -- keep its CamelCase and request_/downstream_ header fields, redact the one query
  -- parameter that carries a session token, and replace the JSON blob with one line.
  if record["RequestMethod"] then
    for key, value in pairs(record) do
      if key:match("^[A-Z]") or key:match("^request_") or key:match("^downstream_") or key == "entryPointName" then
        new_record[key] = value
      end
    end
    local path = (record["RequestPath"] or ""):gsub("access_token=[^&]*", "access_token=REDACTED")
    new_record["RequestPath"] = path
    new_record["message"] = string.format("%s %s%s %s %dms %s", record["RequestMethod"] or "",
      record["RequestHost"] or "", path, record["DownstreamStatus"] or "",
      math.floor((record["Duration"] or 0) / 1e6), record["ClientHost"] or "")
  end
  return 1, new_timestamp, new_record
end
