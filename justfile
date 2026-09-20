# org-preview.nvim development tasks. Run `just` for the menu.

# Default recipe: list all available targets.
default:
    @just --list

# Run the mini.test suite (clones mini.nvim into deps/ on first run).
test:
    @nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run a single test file (e.g. `just test-file tests/test_server.lua`).
test-file FILE:
    @nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run_file('{{FILE}}')"

# Format Lua code with stylua.
format:
    @stylua lua/ plugin/ tests/ scripts/

# Check Lua formatting (no rewrite). Mirrors CI.
lint:
    @stylua --check lua/ plugin/ tests/ scripts/

# Check shell scripts with shellcheck (skipped if not installed).
lint-sh:
    @if command -v shellcheck >/dev/null 2>&1; then \
        echo "Running shellcheck..."; \
        shellcheck scripts/*.sh; \
    else \
        echo "shellcheck not found, skipping..."; \
    fi

# Build doc/org-preview.txt from DOCS.org locally. CI is the source of truth.
docs:
    @./scripts/build-docs.sh

# Remove the local mini.nvim checkout used by `just test`.
clean:
    @rm -rf deps/

# Cut a release: bump the version, stamp the changelog, tag, push, publish.
release RELEASE_TYPE:
    @./scripts/release.sh {{RELEASE_TYPE}}
