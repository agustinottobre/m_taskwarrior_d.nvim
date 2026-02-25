# Work Plan: Fix Task Corruption in m_taskwarrior_d.nvim

## Executive Summary

Fix critical task corruption bugs in the m_taskwarrior_d.nvim Neovim plugin that cause tasks to become unusable after cycling through all status states with TWToggle.

**Root Cause**: The plugin doesn't properly handle deleted tasks - when a task is deleted in Taskwarrior and the user tries to sync, the plugin doesn't detect this and causes UUID/reference corruption.

---

## Issues to Fix

### Issue 1: Deleted Tasks Not Handled (CRITICAL)
**Location**: `lua/m_taskwarrior_d/utils.lua:366-378`

**Problem**: When a task is deleted in Taskwarrior, `task <uuid> export` still returns the task with `status: "deleted"`. The plugin checks `get_task_by(uuid) == nil` which returns FALSE (task exists!), so it proceeds to sync a deleted task as if it were valid.

**Evidence**: 
```
$ task <uuid> export
[{"id":0,"status":"deleted","uuid":"..."}]
$ echo $?
0
```

**CORRECTED Fix**: Taskwarrior can RESTORE deleted tasks by modifying status to pending - the UUID stays the same! Don't create a new task.

---

### Issue 2: +BLOCKED Query Edge Cases  
**Location**: `lua/m_taskwarrior_d/task.lua:125-134`

**Problem**: The result check `result == "[\n]"` may not cover all whitespace variations in Taskwarrior 3.x output.

**Fix**: Use vim.fn.trim() for robust whitespace handling.

---

### Issue 3: Redundant Status Modification
**Location**: `lua/m_taskwarrior_d/utils.lua:416`

**Problem**: After syncing an existing task, the plugin unconditionally calls `modify_task_status()` even when status is already correct.

**Fix**: Only modify status if markdown status differs from TW status.

---

## Implementation Tasks

### Task 1: Fix Deleted Task Detection (CORRECTED)
**File**: `lua/m_taskwarrior_d/utils.lua`

After line 366 (`local new_task = require("m_taskwarrior_d.task").get_task_by(uuid, "task")`), add:

```lua
-- Check if task was deleted in Taskwarrior - restore it
-- Taskwarrior can restore deleted tasks by modifying status to pending
-- This keeps the same UUID - no need to create a new task!
if new_task and new_task.status == "deleted" then
  require("m_taskwarrior_d.task").modify_task_status(uuid, " ")
  new_task.status = "pending"
end
```

---

### Task 2: Fix check_if_task_is_blocked Robustness  
**File**: `lua/m_taskwarrior_d/task.lua`

Replace the if condition around line 130:

```lua
local trimmed = result and vim.fn.trim(result) or ""
if code ~= 0 or trimmed == "" or trimmed == "[]" then
  return false
end
```

---

### Task 3: Add Status Comparison Before Modification
**File**: `lua/m_taskwarrior_d/utils.lua:416`

Replace: `require("m_taskwarrior_d.task").modify_task_status(uuid, status)`

With:

```lua
-- Only modify if status differs from current TW status
if uuid and status then
  local tw_task = require("m_taskwarrior_d.task").get_task_by(uuid, "task")
  if tw_task then
    local tw_status = tw_task.status
    if tw_task.start then tw_status = "active" end
    local target_status = M.status_map[status]
    if tw_status ~= target_status then
      require("m_taskwarrior_d.task").modify_task_status(uuid, status)
    end
  end
end
```

---

## Use Case Analysis

### Use Case 1: Cycle Through All Statuses
| Step | Markdown Status | TW Status | Plugin Action |
|------|-----------------|-----------|---------------|
| 1 | `- [ ] Task` | pending | Sync OK |
| 2 | `- [>] Task` | active | TWToggle → start |
| 3 | `- [x] Task` | completed | TWToggle → done |
| 4 | `- [~] Task` | deleted | TWToggle → delete |
| 5 | `- [ ] Task` | ??? | TWToggle → ? |

**Problem at step 5**: When user toggles from deleted to pending, the plugin syncs. But if the task was deleted in TW directly, the plugin needs to detect this.

**Fix Verified**: When sync detects `status: "deleted"`, restore it with `modify_task_status(uuid, " ")` - keeps same UUID!

---

### Use Case 2: Delete Task in TW, Then Sync from Markdown
| Step | Action | Expected Behavior |
|------|--------|-------------------|
| 1 | Create task in markdown | Creates in TW with UUID |
| 2 | Delete task in TW directly | TW status = deleted |
| 3 | Run TWSyncTasks | Detect deleted, restore to pending |

**Fix Verified**: Sync flow checks `new_task.status == "deleted"` and restores.

---

### Use Case 3: Blocked Task Toggle
| Step | Action | Expected Behavior |
|------|--------|-------------------|
| 1 | Create tasks with dependency | Parent blocked by child |
| 2 | Try to toggle parent | Plugin checks `check_if_task_is_blocked()` |
| 3 | If blocked | Show "This task is blocked" |

**Fix Verified**: The +BLOCKED check uses trimmed comparison.

---

### Use Case 4: No Changes to Status
| Step | Action | Expected Behavior |
|------|--------|-------------------|
| 1 | Task already in correct status | No TW call needed |
| 2 | Run TWSyncTasks | Compare status, skip if same |

**Fix Verified**: Status comparison avoids redundant TW calls.

---

## Verification Plan

1. **Test Cycle Through All States**:
   - Create task with `:TWSyncTasks`
   - Toggle through: pending → active → completed → deleted → pending
   - Verify task remains functional after each cycle

2. **Test Deleted Task Handling**:
   - Delete task in TW directly
   - Run `:TWSyncTasks` 
   - Verify task is restored (not re-created)

3. **Test Blocked Task**:
   - Create parent/child tasks with dependencies
   - Verify blocked check works

4. **Test Status Sync**:
   - Modify task in TW directly
   - Run `:TWSyncTasks`
   - Verify markdown updates to match TW

---

## Scope Boundaries

### IN SCOPE:
- Fix task corruption when cycling through statuses
- Fix deleted task detection and restoration
- Fix blocked task check edge cases
- Avoid redundant TW calls

### OUT OF SCOPE:
- Adding new features
- UI changes
- Performance optimizations
- Documentation updates

---

## Decisions Needed

**DECIDED**: Restore deleted tasks in TW (keep same UUID) instead of re-creating.

**DECIDED**: Continue syncing status from TW to markdown (TW is source of truth).
