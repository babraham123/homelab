-- /etc/opt/fluentbit/journald.lua
-- Script to parse systemd logs from journald
-- Ref:
--   https://docs.fluentbit.io/manual/pipeline/filters/lua
--   https://www.freedesktop.org/software/systemd/man/latest/systemd.journal-fields.html

function process_msg(tag, timestamp, record)
  local retention_period = {{ log_retention_days }} * 24 * 60 * 60
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
  new_record["service"] = record["container_name"] or record["unit"] or ""
  new_record["message"] = record["message"] or ""
  new_record["code"] = (record["code_func"] or "") .. " " .. (record["code_file"] or "") .. ":" .. (record["code_line"] or "")
  new_record["priority"] = record["priority"] or ""
  if record["errno"] then
    new_record["errno"] = record["errno"]
  end
  new_record["pid"] = record["pid"] or ""
  new_record["tid"] = record["tid"] or ""
  new_record["invocation_id"] = record["systemd_invocation_id"] or ""
  new_record["boot_id"] = record["boot_id"] or ""
  return 1, new_timestamp, new_record
end
