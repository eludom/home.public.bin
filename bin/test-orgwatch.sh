#!/bin/bash
#
# test-orgwatch.sh - Test suite for orgwatch.sh
#
# Creates a temporary test environment and verifies orgwatch.sh behavior
# for various scenarios including symlinks, encoding, stale/orphan detection.
#
# Usage: ./test-orgwatch.sh [--keep]
#   --keep  Don't delete test directory after running (for debugging)

set -u
set -o pipefail

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORGWATCH="$SCRIPT_DIR/orgwatch.sh"
TEST_DIR=""
KEEP_TEST_DIR=false
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

#------------------------------------------------------------------------------
# Colors
#------------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#------------------------------------------------------------------------------
# Test framework
#------------------------------------------------------------------------------

setup() {
    TEST_DIR=$(mktemp -d)
    export HOME="$TEST_DIR/home"
    mkdir -p "$HOME"

    # Create test orgfiles directory
    export ORGFILES="$TEST_DIR/home/orgfiles"
    mkdir -p "$ORGFILES"

    # Create log directory
    mkdir -p "$HOME/var/log"

    echo -e "${BLUE}Test environment: $TEST_DIR${NC}"
}

teardown() {
    if $KEEP_TEST_DIR; then
        echo -e "${YELLOW}Keeping test directory: $TEST_DIR${NC}"
    else
        rm -rf "$TEST_DIR"
    fi
}

run_orgwatch() {
    "$ORGWATCH" --orgfiles "$ORGFILES" --skip-git --quiet "$@" 2>&1
}

run_orgwatch_verbose() {
    "$ORGWATCH" --orgfiles "$ORGFILES" --skip-git --verbose "$@" 2>&1
}

assert_file_exists() {
    local file="$1"
    local msg="${2:-File should exist: $file}"
    if [[ -e "$file" ]]; then
        return 0
    else
        echo -e "${RED}FAIL: $msg${NC}"
        echo "  Expected file to exist: $file"
        return 1
    fi
}

assert_file_not_exists() {
    local file="$1"
    local msg="${2:-File should not exist: $file}"
    if [[ ! -e "$file" ]]; then
        return 0
    else
        echo -e "${RED}FAIL: $msg${NC}"
        echo "  Expected file to NOT exist: $file"
        return 1
    fi
}

assert_same_inode() {
    local file1="$1"
    local file2="$2"
    local msg="${3:-Files should have same inode}"
    local inode1 inode2
    inode1=$(stat -c%i "$file1" 2>/dev/null)
    inode2=$(stat -c%i "$file2" 2>/dev/null)
    if [[ "$inode1" == "$inode2" ]]; then
        return 0
    else
        echo -e "${RED}FAIL: $msg${NC}"
        echo "  $file1 inode: $inode1"
        echo "  $file2 inode: $inode2"
        return 1
    fi
}

assert_link_count() {
    local file="$1"
    local expected="$2"
    local msg="${3:-Link count should be $expected}"
    local actual
    actual=$(stat -c%h "$file" 2>/dev/null)
    if [[ "$actual" == "$expected" ]]; then
        return 0
    else
        echo -e "${RED}FAIL: $msg${NC}"
        echo "  Expected link count: $expected"
        echo "  Actual link count: $actual"
        return 1
    fi
}

assert_output_contains() {
    local output="$1"
    local pattern="$2"
    local msg="${3:-Output should contain: $pattern}"
    if echo "$output" | grep -q "$pattern"; then
        return 0
    else
        echo -e "${RED}FAIL: $msg${NC}"
        echo "  Pattern not found: $pattern"
        echo "  Output was: $output"
        return 1
    fi
}

run_test() {
    local test_name="$1"
    local test_func="$2"

    ((++TESTS_RUN))
    echo -e "\n${BLUE}[$TESTS_RUN] $test_name${NC}"

    # Create fresh test environment for each test
    rm -rf "$HOME"
    mkdir -p "$HOME/var/log"
    mkdir -p "$ORGFILES"

    if $test_func; then
        echo -e "${GREEN}PASS${NC}"
        ((++TESTS_PASSED))
    else
        echo -e "${RED}FAIL${NC}"
        ((++TESTS_FAILED))
    fi
}

#------------------------------------------------------------------------------
# Tests: Basic functionality
#------------------------------------------------------------------------------

test_basic_org_file() {
    # Create a simple org file
    mkdir -p "$HOME/docs"
    echo "* Test" > "$HOME/docs/test.org"

    run_orgwatch

    assert_file_exists "$ORGFILES/docs%2Ftest.org" "Link should be created with URL encoding" &&
    assert_same_inode "$HOME/docs/test.org" "$ORGFILES/docs%2Ftest.org" "Should be hard link"
}

test_csv_file() {
    mkdir -p "$HOME/data"
    echo "a,b,c" > "$HOME/data/test.csv"

    run_orgwatch

    assert_file_exists "$ORGFILES/data%2Ftest.csv"
}

test_org_archive_file() {
    mkdir -p "$HOME/archive"
    echo "* Archived" > "$HOME/archive/old.org_archive"

    run_orgwatch

    assert_file_exists "$ORGFILES/archive%2Fold.org_archive"
}

test_skips_non_matching_files() {
    mkdir -p "$HOME/docs"
    echo "test" > "$HOME/docs/test.txt"
    echo "test" > "$HOME/docs/test.md"

    run_orgwatch

    assert_file_not_exists "$ORGFILES/docs%2Ftest.txt" &&
    assert_file_not_exists "$ORGFILES/docs%2Ftest.md"
}

#------------------------------------------------------------------------------
# Tests: URL encoding
#------------------------------------------------------------------------------

test_encoding_slash() {
    mkdir -p "$HOME/a/b/c"
    echo "* Deep" > "$HOME/a/b/c/deep.org"

    run_orgwatch

    assert_file_exists "$ORGFILES/a%2Fb%2Fc%2Fdeep.org"
}

test_encoding_space() {
    mkdir -p "$HOME/my docs"
    echo "* Space" > "$HOME/my docs/with space.org"

    run_orgwatch

    assert_file_exists "$ORGFILES/my%20docs%2Fwith%20space.org"
}

test_encoding_percent() {
    mkdir -p "$HOME/100%done"
    echo "* Percent" > "$HOME/100%done/file.org"

    run_orgwatch

    # % should become %25
    assert_file_exists "$ORGFILES/100%25done%2Ffile.org"
}

test_encoding_underscore_preserved() {
    mkdir -p "$HOME/my_docs"
    echo "* Underscore" > "$HOME/my_docs/file_name.org"

    run_orgwatch

    # Underscores should be preserved as-is
    assert_file_exists "$ORGFILES/my_docs%2Ffile_name.org"
}

test_encoding_double_underscore() {
    mkdir -p "$HOME/foo__bar"
    echo "* Double" > "$HOME/foo__bar/test.org"

    run_orgwatch

    # Double underscores should be preserved (not confused with old encoding)
    assert_file_exists "$ORGFILES/foo__bar%2Ftest.org"
}

#------------------------------------------------------------------------------
# Tests: Symlinks
#------------------------------------------------------------------------------

test_symlinked_directory() {
    # Real directory
    mkdir -p "$HOME/real/Org"
    echo "* Real" > "$HOME/real/Org/file.org"

    # Symlink to it
    ln -s "$HOME/real/Org" "$HOME/Org"

    run_orgwatch

    # Should only create ONE link using canonical path
    assert_file_exists "$ORGFILES/real%2FOrg%2Ffile.org" "Should use canonical path" &&
    assert_file_not_exists "$ORGFILES/Org%2Ffile.org" "Should NOT create link via symlink path"
}

test_symlinked_directory_case_variant() {
    # Simulates ~/org -> ~/Org scenario
    mkdir -p "$HOME/Org"
    echo "* Case" > "$HOME/Org/notes.org"
    ln -s "$HOME/Org" "$HOME/org"

    run_orgwatch

    # Should only have one link
    local count
    count=$(ls -1 "$ORGFILES"/*.org 2>/dev/null | wc -l)
    if [[ "$count" -eq 1 ]]; then
        return 0
    else
        echo "Expected 1 link, found $count"
        ls -la "$ORGFILES"
        return 1
    fi
}

test_symlinked_file() {
    mkdir -p "$HOME/real"
    mkdir -p "$HOME/links"
    echo "* Target" > "$HOME/real/target.org"
    ln -s "$HOME/real/target.org" "$HOME/links/link.org"

    run_orgwatch

    # Should link to canonical path (the real file)
    assert_file_exists "$ORGFILES/real%2Ftarget.org"
}

test_symlink_outside_home() {
    # Create file outside HOME
    mkdir -p "$TEST_DIR/outside"
    echo "* Outside" > "$TEST_DIR/outside/external.org"

    # Symlink from inside HOME
    mkdir -p "$HOME/links"
    ln -s "$TEST_DIR/outside/external.org" "$HOME/links/external.org"

    local output
    output=$(run_orgwatch_verbose)

    # Should skip files that resolve outside HOME
    assert_output_contains "$output" "outside HOME\|Skipping"
}

#------------------------------------------------------------------------------
# Tests: Idempotency
#------------------------------------------------------------------------------

test_skip_unchanged_files() {
    mkdir -p "$HOME/docs"
    echo "* Test" > "$HOME/docs/test.org"

    # First run
    run_orgwatch

    # Second run should skip
    local output
    output=$(run_orgwatch_verbose)

    # Should report skipped, not linked
    assert_output_contains "$output" "skipped\|unchanged"
}

test_relink_on_inode_change() {
    mkdir -p "$HOME/docs"
    echo "* Original" > "$HOME/docs/test.org"

    run_orgwatch

    local old_inode
    old_inode=$(stat -c%i "$ORGFILES/docs%2Ftest.org")

    # Delete and recreate file (new inode)
    rm "$HOME/docs/test.org"
    echo "* New content" > "$HOME/docs/test.org"

    run_orgwatch

    # Link should now have new inode
    assert_same_inode "$HOME/docs/test.org" "$ORGFILES/docs%2Ftest.org"
}

#------------------------------------------------------------------------------
# Tests: Stale and orphan detection
#------------------------------------------------------------------------------

test_orphan_detection() {
    mkdir -p "$HOME/docs"
    echo "* Test" > "$HOME/docs/test.org"

    run_orgwatch

    # Delete original, creating orphan (link count = 1)
    rm "$HOME/docs/test.org"

    run_orgwatch

    # Should be moved to .trash
    assert_file_not_exists "$ORGFILES/docs%2Ftest.org" "Should be moved from main dir" &&
    ls "$ORGFILES/.trash/"*"/docs%2Ftest.org" >/dev/null 2>&1
}

test_stale_detection() {
    mkdir -p "$HOME/docs"
    mkdir -p "$HOME/newdocs"
    echo "* Test" > "$HOME/docs/test.org"

    run_orgwatch

    # Move original (creates new link, old becomes stale with link count > 1)
    mv "$HOME/docs/test.org" "$HOME/newdocs/test.org"

    run_orgwatch

    # Old link should be in .stale, new link should exist
    assert_file_exists "$ORGFILES/newdocs%2Ftest.org" "New location should be linked" &&
    ls "$ORGFILES/.stale/"*"/docs%2Ftest.org" >/dev/null 2>&1
}

#------------------------------------------------------------------------------
# Tests: Dry run
#------------------------------------------------------------------------------

test_dry_run_no_changes() {
    mkdir -p "$HOME/docs"
    echo "* Test" > "$HOME/docs/test.org"

    run_orgwatch --dry-run

    # Should not create any links
    assert_file_not_exists "$ORGFILES/docs%2Ftest.org" "Dry run should not create links"
}

test_dry_run_reports_actions() {
    mkdir -p "$HOME/docs"
    echo "* Test" > "$HOME/docs/test.org"

    local output
    output=$(run_orgwatch_verbose --dry-run)

    assert_output_contains "$output" "DRY-RUN"
}

#------------------------------------------------------------------------------
# Tests: Edge cases
#------------------------------------------------------------------------------

test_empty_orgfiles_directory() {
    mkdir -p "$HOME/docs"
    echo "* Test" > "$HOME/docs/test.org"

    # Ensure orgfiles is empty
    rm -rf "$ORGFILES"/*

    run_orgwatch

    assert_file_exists "$ORGFILES/docs%2Ftest.org"
}

test_special_characters_in_filename() {
    mkdir -p "$HOME/docs"
    echo "* Test" > "$HOME/docs/file (1).org"

    run_orgwatch

    assert_file_exists "$ORGFILES/docs%2Ffile%20(1).org"
}

test_deeply_nested_path() {
    mkdir -p "$HOME/a/b/c/d/e/f/g"
    echo "* Deep" > "$HOME/a/b/c/d/e/f/g/deep.org"

    run_orgwatch

    assert_file_exists "$ORGFILES/a%2Fb%2Fc%2Fd%2Fe%2Ff%2Fg%2Fdeep.org"
}

test_multiple_files_same_basename() {
    mkdir -p "$HOME/dir1"
    mkdir -p "$HOME/dir2"
    echo "* One" > "$HOME/dir1/README.org"
    echo "* Two" > "$HOME/dir2/README.org"

    run_orgwatch

    assert_file_exists "$ORGFILES/dir1%2FREADME.org" &&
    assert_file_exists "$ORGFILES/dir2%2FREADME.org" &&
    # They should be different files (different inodes)
    local inode1 inode2
    inode1=$(stat -c%i "$ORGFILES/dir1%2FREADME.org")
    inode2=$(stat -c%i "$ORGFILES/dir2%2FREADME.org")
    [[ "$inode1" != "$inode2" ]]
}

test_prune_orgfiles_directory() {
    mkdir -p "$HOME/docs"
    echo "* Test" > "$HOME/docs/test.org"

    # First run creates link
    run_orgwatch

    # Count links before second run
    local count_before
    count_before=$(ls -1 "$ORGFILES"/*.org 2>/dev/null | wc -l)

    # Second run should not create additional links from orgfiles contents
    run_orgwatch

    local count_after
    count_after=$(ls -1 "$ORGFILES"/*.org 2>/dev/null | wc -l)

    # Should have same number of links (orgfiles itself is pruned from find)
    if [[ "$count_before" -eq "$count_after" ]]; then
        return 0
    else
        echo "Link count changed: before=$count_before after=$count_after"
        echo "orgfiles should be pruned from find"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --keep) KEEP_TEST_DIR=true; shift ;;
            *) echo "Unknown argument: $1"; exit 1 ;;
        esac
    done

    # Check orgwatch.sh exists
    if [[ ! -x "$ORGWATCH" ]]; then
        echo -e "${RED}Error: Cannot find executable orgwatch.sh at $ORGWATCH${NC}"
        exit 1
    fi

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Testing: $ORGWATCH${NC}"
    echo -e "${BLUE}========================================${NC}"

    setup
    trap teardown EXIT

    # Basic functionality
    run_test "Basic org file linking" test_basic_org_file
    run_test "CSV file linking" test_csv_file
    run_test "org_archive file linking" test_org_archive_file
    run_test "Skips non-matching files" test_skips_non_matching_files

    # URL encoding
    run_test "Encoding: slashes" test_encoding_slash
    run_test "Encoding: spaces" test_encoding_space
    run_test "Encoding: percent signs" test_encoding_percent
    run_test "Encoding: underscores preserved" test_encoding_underscore_preserved
    run_test "Encoding: double underscores preserved" test_encoding_double_underscore

    # Symlinks
    run_test "Symlinked directory (canonical path)" test_symlinked_directory
    run_test "Symlinked directory (case variant)" test_symlinked_directory_case_variant
    run_test "Symlinked file" test_symlinked_file
    run_test "Symlink pointing outside HOME" test_symlink_outside_home

    # Idempotency
    run_test "Skip unchanged files" test_skip_unchanged_files
    run_test "Relink on inode change" test_relink_on_inode_change

    # Stale and orphan detection
    run_test "Orphan detection (deleted original)" test_orphan_detection
    run_test "Stale detection (moved original)" test_stale_detection

    # Dry run
    run_test "Dry run makes no changes" test_dry_run_no_changes
    run_test "Dry run reports actions" test_dry_run_reports_actions

    # Edge cases
    run_test "Empty orgfiles directory" test_empty_orgfiles_directory
    run_test "Special characters in filename" test_special_characters_in_filename
    run_test "Deeply nested path" test_deeply_nested_path
    run_test "Multiple files with same basename" test_multiple_files_same_basename
    run_test "Prune orgfiles directory" test_prune_orgfiles_directory

    # Summary
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}Results: $TESTS_PASSED/$TESTS_RUN passed${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}$TESTS_FAILED tests failed${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

main "$@"
