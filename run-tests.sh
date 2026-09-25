#!/usr/bin/env bash

# Keep going after a suite failure so reports from the other suite are collected.
# Fail on unset variables (-u) and propagate pipeline failures.
set -u -o pipefail

# Resolve the script's own directory so it works regardless of the caller's cwd.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$ROOT_DIR/test-results"
FRONT_DIR="$ROOT_DIR/front"
BACK_DIR="$ROOT_DIR/back"
TEST_STATUS=0

# Check whether a directory contains at least one JUnit XML report.
has_junit_reports() {
  compgen -G "$1/*.xml" >/dev/null
}

run_frontend_tests() {
  local reports_dir="$FRONT_DIR/reports"

  # Skip frontend execution if package.json is missing
  [[ -f "$FRONT_DIR/package.json" ]] || return
  printf '%s\n' 'Running Angular tests...'

  # Dependency check: npm must be available on the machine running this script.
  if ! command -v npm >/dev/null 2>&1; then
    printf '%s\n' 'ERROR: npm was not found.' >&2
    TEST_STATUS=1
    return
  fi

  # Install dependencies only if node_modules is missing (first run / fresh checkout).
  if [[ ! -d "$FRONT_DIR/node_modules" ]]; then
    printf '%s\n' 'Frontend dependencies are missing; running npm ci...'
    if ! (cd "$FRONT_DIR" && npm ci --prefer-offline); then
      TEST_STATUS=1
      return
    fi
  fi

  # Remove any leftover report directory from a previous test run.
  rm -rf "$reports_dir"

  # Run unit tests in a headless browser.
  if ! (cd "$FRONT_DIR" && npm run test:junit); then
    TEST_STATUS=1
  fi

  # Copy the JUnit XML report to the results directory, or fail if missing.
  if has_junit_reports "$reports_dir"; then
    mkdir -p "$RESULTS_DIR/front"
    cp "$reports_dir"/*.xml "$RESULTS_DIR/front/"
  else
    printf '%s\n' 'ERROR: no Angular JUnit XML report was generated.' >&2
    TEST_STATUS=1
  fi
}

run_backend_tests() {
  local reports_dir="$BACK_DIR/build/test-results/test"
 
  # Skip backend execution if build.gradle is missing
  [[ -f "$BACK_DIR/build.gradle" ]] || return
  printf '%s\n' 'Running Java tests...'

  # Dependency check: the Gradle wrapper must exist and be executable.
  if [[ ! -x "$BACK_DIR/gradlew" ]]; then
    printf '%s\n' 'ERROR: Gradle Wrapper is missing or not executable.' >&2
    TEST_STATUS=1
    return
  fi

  # Dependency check: a JDK must be available on the machine running this script.
  if ! command -v java >/dev/null 2>&1; then
    printf '%s\n' 'ERROR: Java was not found.' >&2
    TEST_STATUS=1
    return
  fi

  # Remove Gradle report directory from a previous test run.
  rm -rf "$reports_dir"

  # Run Gradle clean build and unit tests.
  if ! (cd "$BACK_DIR" && ./gradlew clean test); then
    TEST_STATUS=1
  fi

  # Copy the JUnit XML reports to the results directory, or fail if missing.
  if has_junit_reports "$reports_dir"; then
    mkdir -p "$RESULTS_DIR/back"
    cp "$reports_dir"/*.xml "$RESULTS_DIR/back/"
  else
    printf '%s\n' 'ERROR: no Java JUnit XML report was generated.' >&2
    TEST_STATUS=1
  fi
}

# Clean up artifacts from a previous run before generating new ones.
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

run_frontend_tests
run_backend_tests

# Validate that at least one supported project exists.
if [[ ! -f "$FRONT_DIR/package.json" && ! -f "$BACK_DIR/build.gradle" ]]; then
  printf '%s\n' 'ERROR: no supported frontend or backend project was found.' >&2
  exit 1
fi

exit "$TEST_STATUS"
