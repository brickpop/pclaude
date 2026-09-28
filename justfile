# List the available recipes
help:
    @just --list

# Run the tests (macOS only: they drive the Keychain sync against a fake Keychain)
[group('dev')]
test:
    ./test.sh
