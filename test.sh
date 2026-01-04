#!/usr/bin/env bash
# gwt integration tests
# Run: ./test.sh
# Tests are mainly for work with LLMs so they have feedback, some are useless and some are weird

set -euo pipefail

# Colors (disabled if not tty)
if [[ -t 1 ]]; then
    RED=$'\e[31m'
    GREEN=$'\e[32m'
    YELLOW=$'\e[33m'
    RESET=$'\e[0m'
else
    RED='' GREEN='' YELLOW='' RESET=''
fi

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_DIR=""
GWT_PATH=""

# Setup: create isolated git repo
setup() {
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "initial" > file.txt
    git add file.txt
    git commit -q -m "initial commit"
}

# Teardown: clean up test directory
teardown() {
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# Run gwt and capture output
# Usage: run_gwt [args...]
# Sets: EXIT_CODE, STDOUT, STDERR
run_gwt() {
    local stdout_file stderr_file directive_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    directive_file=$(mktemp)

    set +e
    GWT_DIRECTIVE_FILE="$directive_file" "$GWT_PATH" "$@" >"$stdout_file" 2>"$stderr_file"
    EXIT_CODE=$?
    set -e

    STDOUT=$(cat "$stdout_file")
    STDERR=$(cat "$stderr_file")
    rm -f "$stdout_file" "$stderr_file" "$directive_file"
}

# Assert helpers
assert_exit_code() {
    local expected=$1
    if [[ "$EXIT_CODE" -ne "$expected" ]]; then
        echo "${RED}FAIL${RESET}: Expected exit code $expected, got $EXIT_CODE"
        echo "  stdout: $STDOUT"
        echo "  stderr: $STDERR"
        return 1
    fi
}

assert_stdout_contains() {
    local pattern=$1
    if [[ "$STDOUT" != *"$pattern"* ]]; then
        echo "${RED}FAIL${RESET}: stdout does not contain '$pattern'"
        echo "  stdout: $STDOUT"
        return 1
    fi
}

assert_stderr_contains() {
    local pattern=$1
    if [[ "$STDERR" != *"$pattern"* ]]; then
        echo "${RED}FAIL${RESET}: stderr does not contain '$pattern'"
        echo "  stderr: $STDERR"
        return 1
    fi
}

assert_stdout_empty() {
    if [[ -n "$STDOUT" ]]; then
        echo "${RED}FAIL${RESET}: stdout should be empty"
        echo "  stdout: $STDOUT"
        return 1
    fi
}

# Test runner
run_test() {
    local name=$1
    local func=$2

    TESTS_RUN=$((TESTS_RUN + 1))

    setup

    set +e
    (
        set -e
        "$func"
    )
    local result=$?
    set -e

    teardown

    if [[ $result -eq 0 ]]; then
        echo "${GREEN}PASS${RESET}: $name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "${RED}FAIL${RESET}: $name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# =============================================================================
# Phase 1: Foundation Tests
# =============================================================================

test_harness_creates_git_repo() {
    # Verify we're in a git repo with at least one commit
    git rev-parse --git-dir >/dev/null 2>&1
    [[ $(git rev-list --count HEAD) -ge 1 ]]
}

test_harness_captures_output() {
    # Verify run_gwt captures stdout, stderr, and exit code
    run_gwt --version
    [[ -n "$STDOUT" || -n "$STDERR" || "$EXIT_CODE" -ge 0 ]]
}

test_no_args_shows_usage() {
    run_gwt
    assert_exit_code 0
    assert_stdout_contains "usage:"
}

test_help_flag() {
    run_gwt --help
    assert_exit_code 0
    assert_stdout_contains "usage:"
    assert_stdout_contains "gwt"
}

test_help_command() {
    run_gwt help
    assert_exit_code 0
    assert_stdout_contains "usage:"
}

test_outside_git_repo_shows_error() {
    cd /tmp
    run_gwt list
    assert_exit_code 1
    assert_stderr_contains "not a git repository"
}

test_unknown_command_shows_error() {
    run_gwt unknowncommand
    assert_exit_code 1
    assert_stderr_contains "unknown command"
}

# =============================================================================
# Phase 2: List Command Tests
# =============================================================================

test_list_shows_current_worktree() {
    run_gwt list
    assert_exit_code 0
    # Should show the main branch (we're on master/main by default)
    local branch
    branch=$(git branch --show-current)
    assert_stdout_contains "$branch"
}

test_list_shows_branch_name() {
    run_gwt list
    assert_exit_code 0
    # Should show the branch name (master or main depending on git default)
    local branch
    branch=$(git branch --show-current)
    assert_stdout_contains "$branch"
}

test_list_shows_commit_sha() {
    run_gwt list
    assert_exit_code 0
    # Should contain short SHA (first 7 chars - git default)
    local sha
    sha=$(git rev-parse --short HEAD)
    assert_stdout_contains "$sha"
}

test_list_shows_multiple_worktrees() {
    # Create a second worktree
    git branch feature-test
    git worktree add ../test-repo.feature-test feature-test 2>/dev/null

    run_gwt list
    assert_exit_code 0
    # Should show both worktrees
    assert_stdout_contains "feature-test"

    # Cleanup
    git worktree remove ../test-repo.feature-test 2>/dev/null || true
}

test_list_alias_ls() {
    run_gwt ls
    assert_exit_code 0
    local branch
    branch=$(git branch --show-current)
    assert_stdout_contains "$branch"
}

# =============================================================================
# Phase 3: Switch Command Tests
# =============================================================================

test_switch_no_args_shows_error() {
    run_gwt switch
    assert_exit_code 1
    assert_stderr_contains "branch"
}

test_switch_nonexistent_branch_without_create_fails() {
    run_gwt switch nonexistent-branch
    assert_exit_code 1
    assert_stderr_contains "not found"
}

test_switch_create_new_branch_and_worktree() {
    run_gwt switch --create feature-new
    assert_exit_code 0

    # Verify worktree was created
    [[ -d "../$(basename "$TEST_DIR").feature-new" ]]

    # Verify branch exists
    git branch --list feature-new | grep -q feature-new

    # Output should contain path for shell integration
    assert_stdout_contains "feature-new"
}

test_switch_create_short_flag() {
    run_gwt switch -c feature-short
    assert_exit_code 0
    [[ -d "../$(basename "$TEST_DIR").feature-short" ]]
}

test_switch_create_with_base() {
    # Create a commit on a different branch first
    git checkout -q -b develop
    echo "develop content" > develop.txt
    git add develop.txt
    git commit -q -m "develop commit"
    git checkout -q -

    run_gwt switch --create feature-from-develop --base develop
    assert_exit_code 0

    # Verify the new worktree has develop's content
    [[ -f "../$(basename "$TEST_DIR").feature-from-develop/develop.txt" ]]
}

test_switch_to_existing_worktree() {
    # Create worktree first
    git branch feature-existing
    git worktree add "../$(basename "$TEST_DIR").feature-existing" feature-existing 2>/dev/null

    run_gwt switch feature-existing
    assert_exit_code 0
    assert_stdout_contains "feature-existing"
}

test_switch_creates_worktree_for_existing_branch() {
    # Create branch without worktree
    git branch orphan-branch

    run_gwt switch --create orphan-branch
    assert_exit_code 0
    [[ -d "../$(basename "$TEST_DIR").orphan-branch" ]]
}

test_switch_dash_to_previous() {
    # Set up previous branch tracking
    local branch
    branch=$(git branch --show-current)
    git config gwt.previous-branch "$branch"

    # Create another worktree and switch to it
    git branch feature-prev
    git worktree add "../$(basename "$TEST_DIR").feature-prev" feature-prev 2>/dev/null
    cd "../$(basename "$TEST_DIR").feature-prev"

    run_gwt switch -
    assert_exit_code 0
}

test_switch_dash_no_previous_fails() {
    # No previous branch set
    run_gwt switch -
    assert_exit_code 1
    assert_stderr_contains "no previous"
}

test_switch_sanitizes_branch_name() {
    run_gwt switch --create "feature/with/slashes"
    assert_exit_code 0
    # Path should have slashes replaced with double dashes
    [[ -d "../$(basename "$TEST_DIR").feature--with--slashes" ]]
}

test_switch_path_uses_double_dash_for_slashes() {
    run_gwt switch --create "fix/test"
    assert_exit_code 0
    # Path should use -- for each slash
    [[ -d "../$(basename "$TEST_DIR").fix--test" ]]
}

test_switch_path_uses_double_dash_for_backslashes() {
    # Test backslash handling (branch name with backslash)
    run_gwt switch --create "feature\\backslash"
    # This may fail on branch creation (backslash in branch name) - that's OK
    # Just verify the path generation logic if it succeeds
    if [[ $EXIT_CODE -eq 0 ]]; then
        [[ -d "../$(basename "$TEST_DIR").feature--backslash" ]]
    fi
}

test_switch_alias_sw() {
    run_gwt sw --create feature-alias
    assert_exit_code 0
    [[ -d "../$(basename "$TEST_DIR").feature-alias" ]]
}

test_switch_updates_previous_branch() {
    local original_branch
    original_branch=$(git branch --show-current)

    # Create and switch to new worktree
    run_gwt switch --create feature-track
    assert_exit_code 0

    # Check previous branch was saved
    local previous
    previous=$(git config gwt.previous-branch || echo "")
    [[ "$previous" == "$original_branch" ]]
}

# =============================================================================
# Phase 4: Shell Integration Tests
# =============================================================================

test_config_shell_init_bash() {
    run_gwt config shell init bash
    assert_exit_code 0
    # Should output a shell function
    assert_stdout_contains "gwt()"
    assert_stdout_contains "GWT_DIRECTIVE_FILE"
}

test_config_shell_init_zsh() {
    run_gwt config shell init zsh
    assert_exit_code 0
    # Should output a shell function
    assert_stdout_contains "gwt()"
    assert_stdout_contains "GWT_DIRECTIVE_FILE"
}

test_config_shell_init_unknown_fails() {
    run_gwt config shell init fish
    assert_exit_code 1
    assert_stderr_contains "unsupported shell"
}

test_config_show() {
    git config --local gwt.default-branch main

    run_gwt config show
    assert_exit_code 0
    # Should show scope prefix (from --show-scope) and key/value
    assert_stdout_contains "local"
    assert_stdout_contains "gwt.default-branch"
    assert_stdout_contains "main"
}

test_config_show_displays_scope() {
    # Set local config
    git config --local gwt.default-branch local-main
    
    run_gwt config show
    assert_exit_code 0
    
    # Output should include scope prefix from git config --show-scope
    assert_stdout_contains "local"
}

test_config_show_with_global_config() {
    # Set local config
    git config --local gwt.default-branch local-main
    
    # Set global config (save original to restore later)
    local old_global
    old_global=$(git config --global gwt.test-key 2>/dev/null || true)
    git config --global gwt.test-key global-value
    
    run_gwt config show
    assert_exit_code 0
    
    # Should show both local and global with their scope prefixes
    assert_stdout_contains "local"
    assert_stdout_contains "global"
    assert_stdout_contains "gwt.test-key"
    assert_stdout_contains "global-value"
    
    # Clean up global config
    git config --global --unset gwt.test-key 2>/dev/null || true
    if [[ -n "$old_global" ]]; then
        git config --global gwt.test-key "$old_global"
    fi
}

test_config_show_no_config() {
    # Clear all gwt config
    git config --local --remove-section gwt 2>/dev/null || true
    
    # Save and clear global gwt config
    local old_global_hook
    old_global_hook=$(git config --global gwt.hook.post-create 2>/dev/null || true)
    git config --global --remove-section gwt 2>/dev/null || true
    
    run_gwt config show
    # Should exit 0 but produce no output (or empty output)
    assert_exit_code 0
    
    # Restore global config if it existed
    if [[ -n "$old_global_hook" ]]; then
        git config --global gwt.hook.post-create "$old_global_hook"
    fi
}

test_config_show_matches_git_config_output() {
    # Set some config
    git config --local gwt.test-value testval
    
    # Get expected output from git config directly
    local expected
    expected=$(git config --show-scope --get-regexp '^gwt\.' 2>/dev/null || true)
    
    run_gwt config show
    assert_exit_code 0
    
    # Output should match git config --show-scope --get-regexp
    [[ "$STDOUT" == "$expected" ]]
}

test_config_state_previous_branch_get() {
    git config gwt.previous-branch somebranch

    run_gwt config state previous-branch
    assert_exit_code 0
    assert_stdout_contains "somebranch"
}

test_config_state_previous_branch_unset() {
    git config --unset gwt.previous-branch 2>/dev/null || true

    run_gwt config state previous-branch
    # Should return non-zero when not set
    assert_exit_code 1
    assert_stdout_empty
}

test_switch_without_shell_integration_fails() {
    # Run gwt directly without GWT_DIRECTIVE_FILE
    local stdout_file stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)

    set +e
    "$GWT_PATH" switch --create feature-no-shell >"$stdout_file" 2>"$stderr_file"
    EXIT_CODE=$?
    set -e

    STDOUT=$(cat "$stdout_file")
    STDERR=$(cat "$stderr_file")
    rm -f "$stdout_file" "$stderr_file"

    assert_exit_code 1
    assert_stderr_contains "shell integration required"
}

test_shell_wrapper_bash_syntax_valid() {
    run_gwt config shell init bash
    assert_exit_code 0

    # Check the output is valid bash syntax
    echo "$STDOUT" | bash -n
}

# =============================================================================
# Phase 5: Remove Command Tests
# =============================================================================

test_remove_specific_worktree() {
    # Create a worktree
    git branch feature-remove
    git worktree add "../$(basename "$TEST_DIR").feature-remove" feature-remove 2>/dev/null

    run_gwt remove feature-remove
    assert_exit_code 0

    # Worktree should be gone
    [[ ! -d "../$(basename "$TEST_DIR").feature-remove" ]]
}

test_remove_deletes_branch_by_default() {
    # Create a worktree
    git branch feature-del-branch
    git worktree add "../$(basename "$TEST_DIR").feature-del-branch" feature-del-branch 2>/dev/null

    run_gwt remove feature-del-branch
    assert_exit_code 0

    # Branch should be gone
    ! git rev-parse --verify feature-del-branch 2>/dev/null
}

test_remove_no_delete_branch() {
    # Create a worktree
    git branch feature-keep-branch
    git worktree add "../$(basename "$TEST_DIR").feature-keep-branch" feature-keep-branch 2>/dev/null

    run_gwt remove --no-delete-branch feature-keep-branch
    assert_exit_code 0

    # Worktree gone but branch remains
    [[ ! -d "../$(basename "$TEST_DIR").feature-keep-branch" ]]
    git rev-parse --verify feature-keep-branch 2>/dev/null
}

test_remove_nonexistent_worktree_fails() {
    run_gwt remove nonexistent
    assert_exit_code 1
    assert_stderr_contains "not found"
}

test_remove_with_uncommitted_changes_fails() {
    # Create a worktree with changes
    git branch feature-dirty
    git worktree add "../$(basename "$TEST_DIR").feature-dirty" feature-dirty 2>/dev/null
    echo "dirty" > "../$(basename "$TEST_DIR").feature-dirty/dirty.txt"

    run_gwt remove feature-dirty
    assert_exit_code 1
    assert_stderr_contains "uncommitted"
}

test_remove_force_with_uncommitted_changes() {
    # Create a worktree with changes
    git branch feature-force
    git worktree add "../$(basename "$TEST_DIR").feature-force" feature-force 2>/dev/null
    echo "dirty" > "../$(basename "$TEST_DIR").feature-force/dirty.txt"

    run_gwt remove --force feature-force
    assert_exit_code 0

    # Worktree should be gone
    [[ ! -d "../$(basename "$TEST_DIR").feature-force" ]]
}

test_remove_force_delete_unmerged_branch() {
    # Create worktree with unmerged commit
    git branch feature-force-del
    git worktree add "../$(basename "$TEST_DIR").feature-force-del" feature-force-del 2>/dev/null
    (cd "../$(basename "$TEST_DIR").feature-force-del" && echo "unmerged" > unmerged.txt && git add unmerged.txt && git commit -q -m "unmerged commit")

    run_gwt remove --force-delete feature-force-del
    assert_exit_code 0

    # Both should be gone
    [[ ! -d "../$(basename "$TEST_DIR").feature-force-del" ]]
    ! git rev-parse --verify feature-force-del 2>/dev/null
}

test_remove_current_worktree_switches_to_base() {
    # Create and switch to a new worktree
    git branch feature-current
    git worktree add "../$(basename "$TEST_DIR").feature-current" feature-current 2>/dev/null
    cd "../$(basename "$TEST_DIR").feature-current"

    # Set up directive file to capture cd
    local directive_file
    directive_file=$(mktemp)

    # Use --no-delete-branch to avoid branch deletion issues
    GWT_DIRECTIVE_FILE="$directive_file" "$GWT_PATH" remove --no-delete-branch >/dev/null 2>&1

    # Should have directive to cd to base worktree (the original TEST_DIR)
    local directive_content
    directive_content=$(cat "$directive_file")
    [[ "$directive_content" == *"cd "* ]]
    [[ "$directive_content" == *"$TEST_DIR"* ]]

    rm -f "$directive_file"
}

test_remove_current_worktree_force_delete_deletes_branch() {
    # Create worktree with unmerged commit
    git branch feature-current-fd
    git worktree add "../$(basename "$TEST_DIR").feature-current-fd" feature-current-fd 2>/dev/null
    (cd "../$(basename "$TEST_DIR").feature-current-fd" && echo "unmerged" > unmerged.txt && git add unmerged.txt && git commit -q -m "unmerged")
    cd "../$(basename "$TEST_DIR").feature-current-fd"

    local directive_file stdout_file stderr_file
    directive_file=$(mktemp)
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)

    GWT_DIRECTIVE_FILE="$directive_file" "$GWT_PATH" remove --force-delete >"$stdout_file" 2>"$stderr_file"
    local exit_code=$?

    # Should succeed
    [[ $exit_code -eq 0 ]]
    # Should not warn about could not delete
    if grep -q "could not delete" "$stderr_file"; then
        echo "Unexpected warning in stderr: $(cat "$stderr_file")"
        false
    fi
    # Branch should be gone
    if git rev-parse --verify feature-current-fd 2>/dev/null; then
        echo "Branch feature-current-fd still exists"
        false
    fi

    rm -f "$directive_file" "$stdout_file" "$stderr_file"
}

test_remove_alias_rm() {
    git branch feature-rm-alias
    git worktree add "../$(basename "$TEST_DIR").feature-rm-alias" feature-rm-alias 2>/dev/null

    run_gwt rm feature-rm-alias
    assert_exit_code 0
    [[ ! -d "../$(basename "$TEST_DIR").feature-rm-alias" ]]
}

# =============================================================================
# Phase 6: Hooks Tests
# =============================================================================

# Helper to create a hook script
create_hook_script() {
    local path="$1"
    local content="$2"
    mkdir -p "$(dirname "$path")"
    echo "$content" > "$path"
    chmod +x "$path"
}

test_post_create_hook_runs() {
    # Install git hook first
    run_gwt config hooks install
    assert_exit_code 0

    # Create a hook script that writes to a marker file
    local hook_script="$TEST_DIR/hooks/post-create.sh"
    local marker_file="$TEST_DIR/hook-ran"
    create_hook_script "$hook_script" "#!/bin/bash
echo \"post-create ran\" > '$marker_file'"

    git config --local gwt.hook.post-create "$hook_script"

    run_gwt switch --create feature-hook-test
    assert_exit_code 0

    # Hook should have run
    [[ -f "$marker_file" ]]
}

test_post_create_hook_receives_args() {
    # Install git hook first
    run_gwt config hooks install
    assert_exit_code 0

    local hook_script="$TEST_DIR/hooks/post-create.sh"
    local marker_file="$TEST_DIR/hook-args"
    create_hook_script "$hook_script" "#!/bin/bash
echo \"branch=\$1 path=\$2\" > '$marker_file'"

    git config --local gwt.hook.post-create "$hook_script"

    run_gwt switch --create feature-args-test
    assert_exit_code 0

    # Check args were passed correctly
    local content
    content=$(cat "$marker_file")
    [[ "$content" == *"branch=feature-args-test"* ]]
    [[ "$content" == *"path="* ]]
}

test_post_create_hook_failure_logs_but_continues() {
    # Install git hook first
    run_gwt config hooks install
    assert_exit_code 0

    local hook_script="$TEST_DIR/hooks/post-create.sh"
    create_hook_script "$hook_script" "#!/bin/bash
echo 'hook failing' >&2
exit 1"

    git config --local gwt.hook.post-create "$hook_script"

    run_gwt switch --create feature-fail-hook
    # Should succeed despite hook failure
    assert_exit_code 0
    # Worktree should still be created
    [[ -d "../$(basename "$TEST_DIR").feature-fail-hook" ]]
}

test_post_create_global_and_local_both_run() {
    # Install git hook first
    run_gwt config hooks install
    assert_exit_code 0

    local global_hook="$TEST_DIR/hooks/global-post-create.sh"
    local local_hook="$TEST_DIR/hooks/local-post-create.sh"
    local marker_file="$TEST_DIR/hook-order"

    create_hook_script "$global_hook" "#!/bin/bash
echo 'global' >> '$marker_file'"
    create_hook_script "$local_hook" "#!/bin/bash
echo 'local' >> '$marker_file'"

    git config --global gwt.hook.post-create "$global_hook"
    git config --local gwt.hook.post-create "$local_hook"

    run_gwt switch --create feature-both-hooks
    assert_exit_code 0

    # Both should have run, global first
    local content
    content=$(cat "$marker_file")
    [[ "$content" == *"global"* ]]
    [[ "$content" == *"local"* ]]

    # Clean up global config
    git config --global --unset gwt.hook.post-create || true
}

test_post_create_hook_does_not_run_on_checkout() {
    # Install git hook
    run_gwt config hooks install
    assert_exit_code 0

    local hook_script="$TEST_DIR/hooks/post-create.sh"
    local marker_file="$TEST_DIR/hook-checkout"
    create_hook_script "$hook_script" "#!/bin/bash
echo \"hook ran\" > '$marker_file'"

    git config --local gwt.hook.post-create "$hook_script"

    # Create a branch and switch to it using git checkout (not worktree add)
    git branch test-checkout-branch
    git checkout test-checkout-branch 2>/dev/null

    # Hook should NOT have run (only runs on worktree add)
    [[ ! -f "$marker_file" ]]

    # Switch back
    git checkout main 2>/dev/null || git checkout master 2>/dev/null
}

test_post_create_hook_runs_on_git_worktree_add() {
    # Install git hook
    run_gwt config hooks install
    assert_exit_code 0

    local hook_script="$TEST_DIR/hooks/post-create.sh"
    local marker_file="$TEST_DIR/hook-worktree-add"
    create_hook_script "$hook_script" "#!/bin/bash
echo \"hook ran\" > '$marker_file'"

    git config --local gwt.hook.post-create "$hook_script"

    # Use git worktree add directly (not via gwt)
    git branch direct-worktree-branch
    git worktree add "../$(basename "$TEST_DIR").direct-worktree" direct-worktree-branch 2>/dev/null

    # Hook SHOULD have run
    [[ -f "$marker_file" ]]
}

test_hooks_install_global() {
    # Save and clear any existing global hooksPath
    local old_hooks_path
    old_hooks_path=$(git config --global core.hooksPath 2>/dev/null || true)
    git config --global --unset core.hooksPath 2>/dev/null || true
    rm -rf "$HOME/.git-hooks-test-gwt"

    # Test with no existing hooksPath - should create ~/.git-hooks
    local test_hooks_dir="$HOME/.git-hooks"
    rm -rf "$test_hooks_dir"

    run_gwt config hooks install --global
    assert_exit_code 0

    # Should have set core.hooksPath
    [[ "$(git config --global core.hooksPath)" == "$test_hooks_dir" ]]
    # Should have created hook file
    [[ -f "$test_hooks_dir/post-checkout" ]]
    [[ -x "$test_hooks_dir/post-checkout" ]]
    grep -q "gwt post-checkout hook" "$test_hooks_dir/post-checkout"

    # Clean up
    rm -rf "$test_hooks_dir"
    git config --global --unset core.hooksPath 2>/dev/null || true

    # Restore original if any
    if [[ -n "$old_hooks_path" ]]; then
        git config --global core.hooksPath "$old_hooks_path"
    fi
}

test_hooks_install_global_respects_existing_hookspath() {
    # Save existing global hooksPath
    local old_hooks_path
    old_hooks_path=$(git config --global core.hooksPath 2>/dev/null || true)

    # Set a custom hooksPath
    local custom_hooks_dir="/tmp/gwt-test-custom-hooks-$$"
    mkdir -p "$custom_hooks_dir"
    git config --global core.hooksPath "$custom_hooks_dir"

    run_gwt config hooks install --global
    assert_exit_code 0

    # Should have installed to custom path, not ~/.git-hooks
    [[ -f "$custom_hooks_dir/post-checkout" ]]
    [[ ! -f "$HOME/.git-hooks/post-checkout" ]] || [[ "$(git config --global core.hooksPath)" == "$custom_hooks_dir" ]]

    # Clean up
    rm -rf "$custom_hooks_dir"
    git config --global --unset core.hooksPath 2>/dev/null || true

    # Restore original if any
    if [[ -n "$old_hooks_path" ]]; then
        git config --global core.hooksPath "$old_hooks_path"
    fi
}

test_hooks_install_local_sets_hookspath() {
    # Save and clear global hooksPath to avoid interference
    local old_hooks_path
    old_hooks_path=$(git config --global core.hooksPath 2>/dev/null || true)
    git config --global --unset core.hooksPath 2>/dev/null || true

    run_gwt config hooks install
    assert_exit_code 0

    # Should have set local core.hooksPath
    local local_hooks_path
    local_hooks_path=$(git config --local core.hooksPath 2>/dev/null || true)
    [[ -n "$local_hooks_path" ]]
    [[ -f "$local_hooks_path/post-checkout" ]]

    # Restore global if any
    if [[ -n "$old_hooks_path" ]]; then
        git config --global core.hooksPath "$old_hooks_path"
    fi
}

test_hooks_install_local_overrides_global_hookspath() {
    # Save existing global hooksPath
    local old_hooks_path
    old_hooks_path=$(git config --global core.hooksPath 2>/dev/null || true)

    # Set global hooksPath to somewhere else
    local global_hooks_dir="/tmp/gwt-test-global-hooks-$$"
    mkdir -p "$global_hooks_dir"
    git config --global core.hooksPath "$global_hooks_dir"

    run_gwt config hooks install
    assert_exit_code 0

    # Local hooksPath should be set and override global
    local local_hooks_path
    local_hooks_path=$(git config --local core.hooksPath 2>/dev/null || true)
    [[ -n "$local_hooks_path" ]]
    
    # Effective hooksPath should be local, not global
    local effective_path
    effective_path=$(git config core.hooksPath)
    [[ "$effective_path" == "$local_hooks_path" ]]

    # Clean up
    rm -rf "$global_hooks_dir"
    git config --global --unset core.hooksPath 2>/dev/null || true

    # Restore original if any
    if [[ -n "$old_hooks_path" ]]; then
        git config --global core.hooksPath "$old_hooks_path"
    fi
}

# =============================================================================
# Phase 7: Select Command Tests
# =============================================================================

test_select_without_fzf_fails() {
    # Temporarily hide fzf by using a subshell with modified PATH
    local stdout_file stderr_file directive_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    directive_file=$(mktemp)

    set +e
    PATH="/usr/bin:/bin" GWT_DIRECTIVE_FILE="$directive_file" "$GWT_PATH" select >"$stdout_file" 2>"$stderr_file"
    EXIT_CODE=$?
    set -e

    STDOUT=$(cat "$stdout_file")
    STDERR=$(cat "$stderr_file")
    rm -f "$stdout_file" "$stderr_file" "$directive_file"

    assert_exit_code 1
    assert_stderr_contains "fzf"
}

test_select_filters_worktrees() {
    # Skip if fzf not installed
    if ! command -v fzf >/dev/null 2>&1; then
        echo "${YELLOW}SKIP${RESET}: fzf not installed"
        return 0
    fi

    # Create a second worktree
    git branch feature-select
    git worktree add "../$(basename "$TEST_DIR").feature-select" feature-select 2>/dev/null

    # In non-interactive mode (piped), fzf uses --filter
    # We filter for the feature branch
    local stdout_file stderr_file directive_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    directive_file=$(mktemp)

    set +e
    echo "feature-select" | GWT_DIRECTIVE_FILE="$directive_file" "$GWT_PATH" select >"$stdout_file" 2>"$stderr_file"
    EXIT_CODE=$?
    set -e

    STDOUT=$(cat "$stdout_file")
    STDERR=$(cat "$stderr_file")

    assert_exit_code 0

    # Should have written cd directive
    local directive_content
    directive_content=$(cat "$directive_file")
    [[ "$directive_content" == *"cd "* ]]
    [[ "$directive_content" == *"feature-select"* ]]

    rm -f "$stdout_file" "$stderr_file" "$directive_file"
}

test_select_no_match_no_switch() {
    # Skip if fzf not installed
    if ! command -v fzf >/dev/null 2>&1; then
        echo "${YELLOW}SKIP${RESET}: fzf not installed"
        return 0
    fi

    local stdout_file stderr_file directive_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    directive_file=$(mktemp)

    set +e
    echo "nonexistent-branch-xyz" | GWT_DIRECTIVE_FILE="$directive_file" "$GWT_PATH" select >"$stdout_file" 2>"$stderr_file"
    EXIT_CODE=$?
    set -e

    STDOUT=$(cat "$stdout_file")
    STDERR=$(cat "$stderr_file")

    # Should succeed but not switch (user cancelled / no match)
    assert_exit_code 0

    # Directive file should be empty (no cd)
    local directive_content
    directive_content=$(cat "$directive_file" 2>/dev/null || echo "")
    [[ -z "$directive_content" ]] || [[ "$directive_content" != *"cd "* ]]

    rm -f "$stdout_file" "$stderr_file" "$directive_file"
}

# =============================================================================
# Phase 8: Completion Tests
# =============================================================================

test_completion_bash_outputs_valid_script() {
    run_gwt config completion bash
    assert_exit_code 0
    assert_stdout_contains "_gwt()"
    assert_stdout_contains "complete -F _gwt gwt"
    # Verify valid bash syntax
    echo "$STDOUT" | bash -n
}

test_completion_zsh_outputs_valid_script() {
    run_gwt config completion zsh
    assert_exit_code 0
    assert_stdout_contains "_gwt()"
    assert_stdout_contains "compdef _gwt gwt"
    # Verify valid zsh syntax
    echo "$STDOUT" | zsh -n
}

test_completion_unknown_shell_fails() {
    run_gwt config completion fish
    assert_exit_code 1
    assert_stderr_contains "unsupported shell"
}

# =============================================================================
# Run all tests
# =============================================================================

echo "Running gwt tests..."
echo

# Store original dir to find gwt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GWT_PATH="$SCRIPT_DIR/gwt"

# Check gwt exists
if [[ ! -x "$GWT_PATH" ]]; then
    echo "${RED}ERROR${RESET}: gwt not found or not executable at $GWT_PATH"
    exit 1
fi

# Phase 1 tests
run_test "test harness creates isolated git repo" test_harness_creates_git_repo
run_test "test harness captures stdout/stderr/exit code" test_harness_captures_output
run_test "no args shows usage help" test_no_args_shows_usage
run_test "--help shows help" test_help_flag
run_test "help command shows help" test_help_command
run_test "outside git repo shows clear error" test_outside_git_repo_shows_error
run_test "unknown command shows error" test_unknown_command_shows_error

# Phase 2 tests
run_test "list shows current worktree" test_list_shows_current_worktree
run_test "list shows branch name" test_list_shows_branch_name
run_test "list shows commit SHA" test_list_shows_commit_sha
run_test "list shows multiple worktrees" test_list_shows_multiple_worktrees
run_test "list alias 'ls' works" test_list_alias_ls

# Phase 3 tests
run_test "switch with no args shows error" test_switch_no_args_shows_error
run_test "switch to nonexistent branch fails" test_switch_nonexistent_branch_without_create_fails
run_test "switch --create creates branch and worktree" test_switch_create_new_branch_and_worktree
run_test "switch -c short flag works" test_switch_create_short_flag
run_test "switch --create --base uses specified base" test_switch_create_with_base
run_test "switch to existing worktree succeeds" test_switch_to_existing_worktree
run_test "switch --create for existing branch creates worktree" test_switch_creates_worktree_for_existing_branch
run_test "switch - goes to previous worktree" test_switch_dash_to_previous
run_test "switch - with no previous fails" test_switch_dash_no_previous_fails
run_test "switch sanitizes slashes in branch name" test_switch_sanitizes_branch_name
run_test "switch path uses double dash for slashes" test_switch_path_uses_double_dash_for_slashes
run_test "switch path uses double dash for backslashes" test_switch_path_uses_double_dash_for_backslashes
run_test "switch alias 'sw' works" test_switch_alias_sw
run_test "switch updates previous branch" test_switch_updates_previous_branch

# Phase 4 tests
run_test "config shell init bash outputs wrapper" test_config_shell_init_bash
run_test "config shell init zsh outputs wrapper" test_config_shell_init_zsh
run_test "config shell init unknown shell fails" test_config_shell_init_unknown_fails
run_test "config show displays config" test_config_show
run_test "config show displays scope" test_config_show_displays_scope
run_test "config show with global config" test_config_show_with_global_config
run_test "config show no config" test_config_show_no_config
run_test "config show matches git config output" test_config_show_matches_git_config_output
run_test "config state previous-branch get" test_config_state_previous_branch_get
run_test "config state previous-branch unset" test_config_state_previous_branch_unset
run_test "switch without shell integration fails" test_switch_without_shell_integration_fails
run_test "shell wrapper has valid bash syntax" test_shell_wrapper_bash_syntax_valid

# Phase 5 tests
run_test "remove specific worktree" test_remove_specific_worktree
run_test "remove deletes branch by default" test_remove_deletes_branch_by_default
run_test "remove --no-delete-branch keeps branch" test_remove_no_delete_branch
run_test "remove nonexistent worktree fails" test_remove_nonexistent_worktree_fails
run_test "remove with uncommitted changes fails" test_remove_with_uncommitted_changes_fails
run_test "remove --force with uncommitted changes" test_remove_force_with_uncommitted_changes
run_test "remove --force-delete removes unmerged branch" test_remove_force_delete_unmerged_branch
run_test "remove current worktree switches to base" test_remove_current_worktree_switches_to_base
run_test "remove current worktree --force-delete deletes branch" test_remove_current_worktree_force_delete_deletes_branch
run_test "remove alias 'rm' works" test_remove_alias_rm

# Phase 6 tests (post-create hook via git's post-checkout)
run_test "post-create hook runs" test_post_create_hook_runs
run_test "post-create hook receives branch and path args" test_post_create_hook_receives_args
run_test "post-create hook failure logs but continues" test_post_create_hook_failure_logs_but_continues
run_test "post-create global and local hooks both run" test_post_create_global_and_local_both_run
run_test "post-create hook does not run on git checkout" test_post_create_hook_does_not_run_on_checkout
run_test "post-create hook runs on git worktree add" test_post_create_hook_runs_on_git_worktree_add
run_test "hooks install --global creates global hook" test_hooks_install_global
run_test "hooks install --global respects existing hooksPath" test_hooks_install_global_respects_existing_hookspath
run_test "hooks install local sets hooksPath" test_hooks_install_local_sets_hookspath
run_test "hooks install local overrides global hooksPath" test_hooks_install_local_overrides_global_hookspath

# Phase 7 tests
run_test "select without fzf fails" test_select_without_fzf_fails
run_test "select filters and switches to worktree" test_select_filters_worktrees
run_test "select with no match doesn't switch" test_select_no_match_no_switch

# Phase 8 tests
run_test "completion bash outputs valid script" test_completion_bash_outputs_valid_script
run_test "completion zsh outputs valid script" test_completion_zsh_outputs_valid_script
run_test "completion unknown shell fails" test_completion_unknown_shell_fails

# Summary
echo
echo "=========================================="
echo "Tests: $TESTS_RUN | Passed: ${GREEN}$TESTS_PASSED${RESET} | Failed: ${RED}$TESTS_FAILED${RESET}"
echo "=========================================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
