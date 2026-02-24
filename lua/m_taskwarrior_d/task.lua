local M = {}

function M.set_config(opts)
  for k, v in pairs(opts) do
    M[k] = v
  end
end

function M.get_task_by(task_id, return_data)
  if return_data == nil then
    return_data = "uuid"
  end
  local command = string.format("task %s export", task_id)
  local handle = io.popen(command)
  local result = handle:read("*a")
  handle:close()
  local task_info
  if vim == nil then
    local json = require("cjson")
    task_info = json.decode(result)
  else
    task_info = vim.fn.json_decode(result)
  end
  if task_info and #task_info > 0 then
    if return_data == "task" then
      return task_info[1]
    else
      return task_info[1][return_data]
    end
  else
    return nil
  end
end
-- Execute taskwarrior directly with an argument list, bypassing the shell entirely.
function M.execute_task_args(args, return_data, print_output)
  local obj = vim.system(args, { text = true }):wait()
  local output = obj.stdout or ""
  if not return_data then
    output = output .. (obj.stderr or "")
  end
  if print_output then print(output) end
  return obj.code, output
end

-- Split a whitespace-delimited string and append each token to args.
-- Handles nil and empty strings safely (no-op).
function M.append_tokens(args, str)
  if not str or #str == 0 then return end
  for token in str:gmatch("%S+") do
    table.insert(args, token)
  end
end

-- Function to add a task
function M.add_task(description)
  description = require("m_taskwarrior_d.utils").trim(description)
  local args = { "task", "rc.verbose=new-uuid", "add" }
  M.append_tokens(args, description)
  local _, result = M.execute_task_args(args, true)
  local task_uuid = string.match(result, "%x*-%x*-%x*-%x*-%x*")
  return task_uuid
end

-- Function to list tasks
function M.list_tasks()
  local _, result = M.execute_task_args({ "task" }, true)
  return result
end

-- Function to mark a task as done
function M.mark_task_done(task_id)
  M.execute_task_args({ "task", task_id, "done" })
end

function M.modify_task(task_id, desc)
  local args = { "task", task_id, "mod" }
  M.append_tokens(args, desc)
  M.execute_task_args(args, false)
end

--Function to modify task's status completed, (pending), deleted, started, canceled
function M.modify_task_status(task_id, new_status)
  if M.status_map[new_status] == "active" then
    M.execute_task_args({ "task", task_id, "modify", "status:pending" })
    M.execute_task_args({ "task", task_id, "start" })
  elseif M.status_map[new_status] == "pending" then
  -- When setting to pending, we need to also stop the task to clear the Start date
  -- Otherwise the task remains "active" in Taskwarrior due to having a Start date
    M.execute_task_args({ "task", task_id, "modify", "status:pending" })
    M.execute_task_args({ "task", task_id, "stop" })
  else
    local status = M.status_map[new_status]
    M.execute_task_args({ "task", task_id, "modify", "status:" .. status })
  end
end

function M.add_task_deps(current_task_id, deps)
  M.execute_task_args({ "task", current_task_id, "modify", "dep:" .. table.concat(deps, ",") })
end

function M.get_blocked_tasks_by(uuid)
  local status, result = M.execute_task_args({ "task", "depends.has:" .. uuid, "export" }, true)
  return status, result
end

function M.get_tasks_by(uuids)
  local tasks = {}
  for _, uuid in ipairs(uuids) do
    local _, result = M.execute_task_args({ "task", uuid, "export" }, true)
    if result then
      if vim == nil then
        local json = require("cjson")
        result = json.decode(result)
      else
        result = vim.fn.json_decode(result)
      end
      if result then
        table.insert(tasks, result[1])
      end
    end
  end
  return true, tasks
end

function M.check_if_task_is_blocked(uuid)
  local _, result = M.execute_task_args({ "task", uuid, "-BLOCKED" }, true)
  if #result > 0 then
    return false
  end
  return true
end

return M
